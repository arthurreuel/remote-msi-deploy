<#
  Configurar.ps1 - interface grafica de configuracao do toolkit.
  Preenche origem/instalador, token, maquinas, dominio, metodo e os nomes
  do agente; grava config.psd1 + machines.txt + token.txt e, ao salvar,
  provisiona os binarios (PsExec + .msi) na pasta.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root       = $PSScriptRoot
$cfgPath    = Join-Path $root "config.psd1"
$tokenPath  = Join-Path $root "token.txt"   # legado (texto claro)
$secPath    = Join-Path $root "token.sec"   # DPAPI (preferido)
$machPath   = Join-Path $root "machines.txt"
$tokenEntropy = [Text.Encoding]::UTF8.GetBytes('RemoteMsiDeploy/token/v1')

# ---- valores padrao (generico) + carga do config existente -------------
$d = @{
    AgentDisplayName  = '*Monitor Agent*'
    ServiceName       = 'MonitorAgent'
    RegistryKey       = 'HKLM:\SOFTWARE\MonitorAgent'
    DataDir           = 'C:\ProgramData\MonitorAgent'
    TokenProperty     = 'TENANT_TOKEN'
    MsiFileName       = 'Agent.msi'
    MsiSource         = ''
    PsExecSource      = ''
    WorkDir           = 'C:\Temp'
    PsExecServiceName = 'pvdeploy'
    Domain            = ''
    Method            = 'PsExec'
}
if (Test-Path $cfgPath) {
    try { $c = Import-PowerShellDataFile $cfgPath; foreach ($k in @($d.Keys)) { if ($c.ContainsKey($k) -and $c[$k]) { $d[$k] = $c[$k] } } } catch {}
}
# Carrega o token existente: prefere token.sec (DPAPI), senao token.txt legado.
$tokenAtual = ''
if (Test-Path $secPath) {
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $enc = [Convert]::FromBase64String((Get-Content $secPath -Raw).Trim())
        $tokenAtual = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($enc, $tokenEntropy, [Security.Cryptography.DataProtectionScope]::LocalMachine))
    } catch { $tokenAtual = '' }
} elseif (Test-Path $tokenPath) { $tokenAtual = (Get-Content $tokenPath -Raw).Trim() }
# Normaliza quebras de linha para CRLF (a caixa de texto do WinForms so
# renderiza \r\n; arquivos salvos com \n apareceriam grudados numa linha).
$machAtual  = if (Test-Path $machPath)  { (Get-Content $machPath) -join "`r`n" } else { '' }

function New-Label($text,$x,$y,$w=180) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = "$x,$y"; $l.Size = "$w,20"; $l
}
function New-Text($val,$x,$y,$w=360) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = "$val"; $t.Location = "$x,$y"; $t.Size = "$w,22"; $t
}
function New-Hint($text,$x,$y,$w=610) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = "$x,$y"; $l.Size = "$w,16"
    $l.ForeColor = [System.Drawing.Color]::Gray
    $l.Font = New-Object System.Drawing.Font("Segoe UI",8)
    $l
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Configurar - Remote MSI Deploy"
$form.Size = New-Object System.Drawing.Size(660,780)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 12
$hdr = New-Object System.Windows.Forms.Label
$hdr.Text = "Preencha e clique em Salvar. Ao salvar, os binarios (PsExec + .msi) sao copiados para esta pasta."
$hdr.Location = "15,$y"; $hdr.Size = "620,20"; $hdr.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($hdr); $y += 28

# ===== Instalador (.msi) =====
$secMsi = New-Label "Instalador (.msi)" 15 $y 200
$secMsi.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($secMsi); $y += 22

# Origem (recomendado)
$form.Controls.Add((New-Label "Origem (rede/SysVol):" 15 $y 150))
$txtSrc = New-Text $d.MsiSource 170 $y 360
$form.Controls.Add($txtSrc)
$btnSrc = New-Object System.Windows.Forms.Button
$btnSrc.Text = "Pasta..."; $btnSrc.Location = "540,$y"; $btnSrc.Size = "90,24"
$btnSrc.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq 'OK') { $txtSrc.Text = $fbd.SelectedPath } })
$form.Controls.Add($btnSrc); $y += 24
$form.Controls.Add((New-Hint "Recomendado: o instalador e trazido daqui automaticamente ao salvar." 170 $y)); $y += 20

# Local (opcional / fallback)
$form.Controls.Add((New-Label "Local (opcional):" 15 $y 150))
$txtMsi = New-Text '' 170 $y 360
$form.Controls.Add($txtMsi)
$btnMsi = New-Object System.Windows.Forms.Button
$btnMsi.Text = "Procurar..."; $btnMsi.Location = "540,$y"; $btnMsi.Size = "90,24"
$btnMsi.Add_Click({ $ofd = New-Object System.Windows.Forms.OpenFileDialog; $ofd.Filter = "Windows Installer (*.msi)|*.msi"; if ($ofd.ShowDialog() -eq 'OK') { $txtMsi.Text = $ofd.FileName } })
$form.Controls.Add($btnMsi); $y += 24
$form.Controls.Add((New-Hint "Use SO em maquina sem acesso a origem acima. Normalmente deixe em branco." 170 $y)); $y += 24

# ===== Enrollment / rede =====
$form.Controls.Add((New-Label "Token de enrollment:" 15 $y 150))
$txtToken = New-Text $tokenAtual 170 $y 460
$form.Controls.Add($txtToken); $y += 30

$form.Controls.Add((New-Label "Dominio (informativo):" 15 $y 150))
$txtDom = New-Text $d.Domain 170 $y 460
$form.Controls.Add($txtDom); $y += 30

$form.Controls.Add((New-Label "Metodo de execucao:" 15 $y 150))
$cboMet = New-Object System.Windows.Forms.ComboBox
$cboMet.Location = "170,$y"; $cboMet.Size = "200,22"; $cboMet.DropDownStyle = "DropDownList"
[void]$cboMet.Items.Add("PsExec"); $cboMet.SelectedIndex = 0
$form.Controls.Add($cboMet); $y += 34

# ===== Maquinas =====
$form.Controls.Add((New-Label "Maquinas (uma por linha):" 15 $y 200)); $y += 22
$txtMach = New-Object System.Windows.Forms.TextBox
$txtMach.Multiline = $true; $txtMach.ScrollBars = "Vertical"; $txtMach.WordWrap = $false
$txtMach.Location = "15,$y"; $txtMach.Size = "615,100"
$txtMach.Font = New-Object System.Drawing.Font("Consolas",9)
$txtMach.Text = $machAtual
$form.Controls.Add($txtMach); $y += 108

# ===== Identidade do agente (avancado) =====
$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = "Identidade do agente (avancado - so mude se trocar de produto)"
$grp.Location = "15,$y"; $grp.Size = "615,150"
$gy = 20
$grp.Controls.Add((New-Label "DisplayName:" 15 $gy 90)); $txtDisp = New-Text $d.AgentDisplayName 110 $gy 190; $grp.Controls.Add($txtDisp)
$grp.Controls.Add((New-Label "Servico:" 320 $gy 55)); $txtSvc = New-Text $d.ServiceName 380 $gy 215; $grp.Controls.Add($txtSvc); $gy += 28
$grp.Controls.Add((New-Label "Chave registro:" 15 $gy 90)); $txtReg = New-Text $d.RegistryKey 110 $gy 485; $grp.Controls.Add($txtReg); $gy += 28
$grp.Controls.Add((New-Label "Pasta de dados:" 15 $gy 90)); $txtData = New-Text $d.DataDir 110 $gy 485; $grp.Controls.Add($txtData); $gy += 28
$grp.Controls.Add((New-Label "Prop. token:" 15 $gy 90)); $txtProp = New-Text $d.TokenProperty 110 $gy 190; $grp.Controls.Add($txtProp)
$grp.Controls.Add((New-Label "PsExec svc:" 320 $gy 55)); $txtPvc = New-Text $d.PsExecServiceName 380 $gy 100; $grp.Controls.Add($txtPvc)
$txtWork = New-Text $d.WorkDir 500 $gy 95; $grp.Controls.Add($txtWork)
$form.Controls.Add($grp); $y += 158

# ===== Provisionar + botoes =====
$chkProv = New-Object System.Windows.Forms.CheckBox
$chkProv.Text = "Copiar PsExec e MSI para a pasta ao salvar (provisionar)"
$chkProv.Location = "15,$y"; $chkProv.Size = "500,22"; $chkProv.Checked = $true
$form.Controls.Add($chkProv); $y += 28

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = "15,$y"; $lblStatus.Size = "390,22"; $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Salvar configuracao"; $btnSave.Location = "410,$y"; $btnSave.Size = "140,28"
$btnMenu = New-Object System.Windows.Forms.Button
$btnMenu.Text = "Abrir menu"; $btnMenu.Location = "555,$y"; $btnMenu.Size = "75,28"
$form.Controls.Add($lblStatus); $form.Controls.Add($btnSave); $form.Controls.Add($btnMenu)

$btnSave.Add_Click({
    try {
        # Instalador local e OPCIONAL. Vazio => mantem o nome ja configurado
        # e conta com a origem (MsiSource) para trazer o arquivo.
        $msiSel = $txtMsi.Text.Trim()
        if ($msiSel) {
            $msiNome = Split-Path $msiSel -Leaf
            if ((Test-Path $msiSel) -and ((Split-Path $msiSel -Parent) -ne $root)) {
                Copy-Item $msiSel (Join-Path $root $msiNome) -Force
            }
        } else {
            $msiNome = $d.MsiFileName
        }
        # Token: cifra com DPAPI (escopo de maquina) em token.sec; remove o .txt legado.
        if ($txtToken.Text.Trim()) {
            Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
            $b = [Text.Encoding]::UTF8.GetBytes($txtToken.Text.Trim())
            $enc = [Security.Cryptography.ProtectedData]::Protect($b, $tokenEntropy, [Security.Cryptography.DataProtectionScope]::LocalMachine)
            [Convert]::ToBase64String($enc) | Set-Content $secPath -Encoding ASCII -NoNewline
            if (Test-Path $tokenPath) { Remove-Item $tokenPath -Force }
        }
        Set-Content $machPath $txtMach.Text -Encoding UTF8

        $esc = { param($s) "$s".Replace("'","''") }
        $buffer = (& $esc $txtData.Text).TrimEnd('\') + '\buffer.db'
        $psd = @"
@{
    AgentDisplayName  = '$(& $esc $txtDisp.Text)'
    ServiceName       = '$(& $esc $txtSvc.Text)'
    RegistryKey       = '$(& $esc $txtReg.Text)'
    DataDir           = '$(& $esc $txtData.Text)'
    BufferFile        = '$buffer'
    TokenProperty     = '$(& $esc $txtProp.Text)'
    MsiFileName       = '$(& $esc $msiNome)'
    MsiSource         = '$(& $esc $txtSrc.Text)'
    PsExecSource      = '$(& $esc $d.PsExecSource)'
    WorkDir           = '$(& $esc $txtWork.Text)'
    PsExecServiceName = '$(& $esc $txtPvc.Text)'
    Domain            = '$(& $esc $txtDom.Text)'
    Method            = '$($cboMet.SelectedItem)'
    Machines          = @()
    MachinesFile      = 'machines.txt'
}
"@
        Set-Content $cfgPath $psd -Encoding UTF8
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblStatus.Text = "Config salva."

        if ($chkProv.Checked) {
            $lblStatus.Text = "Salvo. Provisionando binarios (aguarde)..."; $form.Refresh()
            $prov = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Provision-Assets.ps1') 2>&1 | Out-String
            [System.Windows.Forms.MessageBox]::Show($prov, "Provisionamento de binarios", 'OK', 'Information') | Out-Null
            $lblStatus.Text = "Config salva e binarios provisionados."
        }
    } catch {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "Erro: $($_.Exception.Message)"
    }
})

$btnMenu.Add_Click({
    $menu = Join-Path $root "Menu.ps1"
    if (Test-Path $menu) { Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$menu`"" }
})

[void]$form.ShowDialog()
