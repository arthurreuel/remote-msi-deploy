<#
  Configurar.ps1 - interface grafica de configuracao do toolkit.
  Preenche instalador, origem do instalador, token, maquinas, dominio,
  metodo e os nomes do agente; grava config.psd1 + machines.txt + token.txt
  e, ao salvar, provisiona os binarios (PsExec + .msi) na pasta.
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
$tokenAtual = if (Test-Path $tokenPath) { (Get-Content $tokenPath -Raw).Trim() } else { '' }
$machAtual  = if (Test-Path $machPath)  { (Get-Content $machPath -Raw) } else { '' }

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
$form.Size = New-Object System.Drawing.Size(660,760)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15
$hdr = New-Object System.Windows.Forms.Label
$hdr.Text = "Preencha e clique em Salvar. Ao salvar, os binarios (PsExec + .msi) sao copiados para esta pasta."
$hdr.Location = "15,$y"; $hdr.Size = "620,20"; $hdr.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($hdr); $y += 30

# Origem do instalador (pasta de rede / SysVol)
$form.Controls.Add((New-Label "Origem do instalador (pasta):" 15 $y 190))
$txtSrc = New-Text $d.MsiSource 210 $y 320
$form.Controls.Add($txtSrc)
$btnSrc = New-Object System.Windows.Forms.Button
$btnSrc.Text = "Pasta..."; $btnSrc.Location = "540,$y"; $btnSrc.Size = "90,24"
$btnSrc.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq 'OK') { $txtSrc.Text = $fbd.SelectedPath }
})
$form.Controls.Add($btnSrc); $y += 32

# Instalador (.msi) local
$form.Controls.Add((New-Label "Instalador (.msi) local:" 15 $y 190))
$txtMsi = New-Text (Join-Path $root $d.MsiFileName) 210 $y 320
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
$form.Controls.Add((New-Label "Token de enrollment:" 15 $y 190))
$txtToken = New-Text $tokenAtual 210 $y 420
$form.Controls.Add($txtToken); $y += 32

# Dominio
$form.Controls.Add((New-Label "Dominio (informativo):" 15 $y 190))
$txtDom = New-Text $d.Domain 210 $y 420
$form.Controls.Add($txtDom); $y += 32

# Metodo
$form.Controls.Add((New-Label "Metodo de execucao:" 15 $y 190))
$cboMet = New-Object System.Windows.Forms.ComboBox
$cboMet.Location = "210,$y"; $cboMet.Size = "200,22"; $cboMet.DropDownStyle = "DropDownList"
[void]$cboMet.Items.Add("PsExec"); $cboMet.SelectedIndex = 0
$form.Controls.Add($cboMet); $y += 36

# Maquinas
$form.Controls.Add((New-Label "Maquinas (uma por linha):" 15 $y 200)); $y += 22
$txtMach = New-Object System.Windows.Forms.TextBox
$txtMach.Multiline = $true; $txtMach.ScrollBars = "Vertical"
$txtMach.Location = "15,$y"; $txtMach.Size = "615,110"
$txtMach.Font = New-Object System.Drawing.Font("Consolas",9)
$txtMach.Text = $machAtual
$form.Controls.Add($txtMach); $y += 120

# Identidade do agente (avancado)
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

# Checkbox provisionar
$chkProv = New-Object System.Windows.Forms.CheckBox
$chkProv.Text = "Copiar PsExec e MSI para a pasta ao salvar (provisionar)"
$chkProv.Location = "15,$y"; $chkProv.Size = "500,22"; $chkProv.Checked = $true
$form.Controls.Add($chkProv); $y += 28

# Status + botoes
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = "15,$y"; $lblStatus.Size = "390,22"; $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Salvar configuracao"; $btnSave.Location = "410,$y"; $btnSave.Size = "140,28"
$btnMenu = New-Object System.Windows.Forms.Button
$btnMenu.Text = "Abrir menu"; $btnMenu.Location = "555,$y"; $btnMenu.Size = "75,28"
$form.Controls.Add($lblStatus); $form.Controls.Add($btnSave); $form.Controls.Add($btnMenu)

$btnSave.Add_Click({
    try {
        $msiSel  = $txtMsi.Text.Trim()
        $msiNome = if ($msiSel) { Split-Path $msiSel -Leaf } else { 'Agent.msi' }
        if ($msiSel -and (Test-Path $msiSel) -and ((Split-Path $msiSel -Parent) -ne $root)) {
            Copy-Item $msiSel (Join-Path $root $msiNome) -Force
        }
        if ($txtToken.Text.Trim()) { Set-Content $tokenPath $txtToken.Text.Trim() -NoNewline -Encoding UTF8 }
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
