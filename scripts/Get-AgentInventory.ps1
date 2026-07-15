# ============================================================
#  Get-AgentInventory.ps1  -  fotografia (somente leitura)
#  DeviceId, status do servico e versao por maquina.
#  Config: config.psd1. Rodar como administrador.
#     powershell -ExecutionPolicy Bypass -File .\scripts\Get-AgentInventory.ps1
# ============================================================
. (Join-Path $PSScriptRoot "..\lib\Common.ps1")

$root = Split-Path $PSScriptRoot -Parent
$cfg  = Get-DeployConfig -Root $root
Assert-Prereq -Cfg $cfg
Write-Host "Inventariando $($cfg.Machines.Count) maquina(s)..." -ForegroundColor Cyan

$scan = @(
    '$ErrorActionPreference = "SilentlyContinue"'
    ('$d = (Get-ItemProperty "' + $cfg.RegistryKey + '" -ErrorAction SilentlyContinue).DeviceId')
    ('$s = (Get-Service "' + $cfg.ServiceName + '" -ErrorAction SilentlyContinue).Status')
    '$keys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"'
    ('$app = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "' + $cfg.AgentDisplayName + '" } | Select-Object -First 1')
    'Write-Output ("RESULT;DeviceId=" + $d + ";Servico=" + $s + ";Versao=" + $app.DisplayVersion)'
)

$snap = foreach ($pc in $cfg.Machines) {
    if (-not (Test-MachineOnline $pc)) {
        [PSCustomObject]@{ Maquina=$pc; DeviceId=""; Servico="OFFLINE"; Versao="" }; continue
    }
    $r = Invoke-RemotePS -Cfg $cfg -ComputerName $pc -Lines $scan
    $linha = ($r.Output | Where-Object { $_ -like "RESULT;*" } | Select-Object -First 1)
    if (-not $linha) {
        [PSCustomObject]@{ Maquina=$pc; DeviceId=""; Servico="FALHA PsExec"; Versao="" }; continue
    }
    [PSCustomObject]@{
        Maquina  = $pc
        DeviceId = ($linha -replace '.*DeviceId=([^;]*).*','$1')
        Servico  = ($linha -replace '.*Servico=([^;]*).*','$1')
        Versao   = ($linha -replace '.*Versao=(.*)$','$1')
    }
}

Disconnect-RemoteShares -Cfg $cfg -Machines $cfg.Machines
$snap | Format-Table -AutoSize
Save-Report -Cfg $cfg -Prefix "inventario" -Rows $snap | Out-Null
