<#
  Configurar.ps1 - interface grafica de configuracao do toolkit.
  Preenche instalador, token, maquinas, dominio, metodo e os nomes do
  agente, e grava config.psd1 + machines.txt + token.txt nesta pasta.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root       = $PSScriptRoot
$cfgPath    = Join-Path $root "config.psd1"
$tokenPath  = Join-Path $root "token.txt"
$machPath   = Join-Path $root "machines.txt"

# ---- valores padrao (generico) + carga do config existente -------------
$d = @{
    AgentDisplayName  = '*Monitor Agent*'
    ServiceName       = 'MonitorAgent'
    RegistryKey       = 'HKLM:\SOFTWARE\MonitorAgent'
    DataDir           = 'C:\ProgramData\MonitorAgent'
    TokenProperty     = 'TENANT_TOKEN'
    MsiFileName       = 'Agent.msi'
    WorkDir           = 'C:\Temp'
    PsExecServiceName = 'pvdeploy'
    Domain            = ''
    Method            = 'PsExec'
}
if (Test-Path $cfgPath) {
    try { $c = Import-PowerShellDataFile $cfgPath; foreach ($k in @($d.Keys)) { if ($c.ContainsKey($k) -and $c[$k]) { $d[$k] = $c[$k] } } } catch {}
}
$tokenAtual = if (Test-Path $tokenPath) { (Get-Content $tokenPath -Raw).Trim() } else { '' }
$machAtual  = if (Test-Path $machPath)  { (Get-Content $machPath -Raw) } else { '' }

# ---- helpers de layout -------------------------------------------------
function New-Label($text,$x,$y,$w=180) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = "$x,$y"; $l.Size = "$w,20"; $l
}
function New-Text($val,$x,$y,$w=360) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = "$val"; $t.Location = "$x,$y"; $t.Size = "$w,22"; $t
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Configurar - Remote MSI Deploy"
$form.Size = New-Object System.Drawing.Size(660,700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15
$hdr = New-Object System.Windows.Forms.Label
$hdr.Text = "Preencha os campos e clique em Salvar. O menu de fluxos usara estes valores."
$hdr.Location = "15,$y"; $hdr.Size = "610,20"; $hdr.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($hdr); $y += 32

# Instalador (.msi)
$form.Controls.Add((New-Label "Instalador (.msi):" 15 $y))
$txtMsi = New-Text (Join-Path $root $d.MsiFileName) 200 $y 330
$form.Controls.Add($txtMsi)
$btnMsi = New-Object System.Windows.Forms.Button
$btnMsi.Text = "Procurar..."; $btnMsi.Location = "540,$y"; $btnMsi.Size = "90,24"
$btnMsi.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Windows Installer (*.msi)|*.msi"
    if ($ofd.ShowDialog() -eq 'OK') { $txtMsi.Text = $ofd.FileName }
})
$form.Controls.Add($btnMsi); $y += 34

# Token
$form.Controls.Add((New-Label "Token de enrollment:" 15 $y))
$txtToken = New-Text $tokenAtual 200 $y 430
$form.Controls.Add($txtToken); $y += 34

# Dominio
$form.Controls.Add((New-Label "Dominio (informativo):" 15 $y))
$txtDom = New-Text $d.Domain 200 $y 430
$form.Controls.Add($txtDom); $y += 34

# Metodo
$form.Controls.Add((New-Label "Metodo de execucao:" 15 $y))
$cboMet = New-Object System.Windows.Forms.ComboBox
$cboMet.Location = "200,$y"; $cboMet.Size = "200,22"; $cboMet.DropDownStyle = "DropDownList"
[void]$cboMet.Items.Add("PsExec"); $cboMet.SelectedIndex = 0
$form.Controls.Add($cboMet); $y += 40

# Maquinas
$form.Controls.Add((New-Label "Maquinas (uma por linha):" 15 $y)); $y += 22
$txtMach = New-Object System.Windows.Forms.TextBox
$txtMach.Multiline = $true; $txtMach.ScrollBars = "Vertical"
$txtMach.Location = "15,$y"; $txtMach.Size = "615,120"
$txtMach.Font = New-Object System.Drawing.Font("Consolas",9)
$txtMach.Text = $machAtual
$form.Controls.Add($txtMach); $y += 130

# ---- Identidade do agente (avancado) ----
$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = "Identidade do agente (avancado - so mude se trocar de produto)"
$grp.Location = "15,$y"; $grp.Size = "615,180"
$gy = 22
$grp.Controls.Add((New-Label "DisplayName:" 15 $gy 110)); $txtDisp = New-Text $d.AgentDisplayName 130 $gy 200; $grp.Controls.Add($txtDisp)
$grp.Controls.Add((New-Label "Servico:" 350 $gy 60));    $txtSvc = New-Text $d.ServiceName 415 $gy 180; $grp.Controls.Add($txtSvc); $gy += 30
$grp.Controls.Add((New-Label "Chave registro:" 15 $gy 110)); $txtReg = New-Text $d.RegistryKey 130 $gy 465; $grp.Controls.Add($txtReg); $gy += 30
$grp.Controls.Add((New-Label "Pasta de dados:" 15 $gy 110)); $txtData = New-Text $d.DataDir 130 $gy 465; $grp.Controls.Add($txtData); $gy += 30
$grp.Controls.Add((New-Label "Prop. do token:" 15 $gy 110)); $txtProp = New-Text $d.TokenProperty 130 $gy 200; $grp.Controls.Add($txtProp)
$grp.Controls.Add((New-Label "PsExec svc:" 350 $gy 70));  $txtPvc = New-Text $d.PsExecServiceName 415 $gy 180; $grp.Controls.Add($txtPvc); $gy += 30
$grp.Controls.Add((New-Label "Pasta trabalho:" 15 $gy 110)); $txtWork = New-Text $d.WorkDir 130 $gy 200; $grp.Controls.Add($txtWork)
$form.Controls.Add($grp); $y += 190

# Status
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = "15,$y"; $lblStatus.Size = "400,22"
$lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen

# Botoes
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Salvar configuracao"; $btnSave.Location = "420,$y"; $btnSave.Size = "130,28"
$btnMenu = New-Object System.Windows.Forms.Button
$btnMenu.Text = "Abrir menu"; $btnMenu.Location = "555,$y"; $btnMenu.Size = "75,28"
$form.Controls.Add($lblStatus); $form.Controls.Add($btnSave); $form.Controls.Add($btnMenu)

$btnSave.Add_Click({
    try {
        # MSI: copia para a raiz se veio de fora
        $msiSel = $txtMsi.Text.Trim()
        $msiNome = if ($msiSel) { Split-Path $msiSel -Leaf } else { 'Agent.msi' }
        if ($msiSel -and (Test-Path $msiSel) -and ((Split-Path $msiSel -Parent) -ne $root)) {
            Copy-Item $msiSel (Join-Path $root $msiNome) -Force
        }
        # token.txt
        if ($txtToken.Text.Trim()) { Set-Content $tokenPath $txtToken.Text.Trim() -NoNewline -Encoding UTF8 }
        # machines.txt
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
        $lblStatus.Text = "Salvo: config.psd1, machines.txt e token.txt."
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
