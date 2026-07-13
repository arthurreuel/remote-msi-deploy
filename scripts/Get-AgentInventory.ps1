# ============================================================
#  Get-AgentInventory.ps1
#  Fotografia (somente leitura) do estado do agente por maquina:
#  DeviceId, status do servico e presenca/versao do agente.
#  Nao altera nada. Use antes e depois de operacoes em massa.
#
#  Rodar como administrador:
#     powershell -ExecutionPolicy Bypass -File .\scripts\Get-AgentInventory.ps1
# ============================================================

# --- CONFIGURACAO -----------------------------------------------
$maquinas = @(
    "WS-001","WS-002","WS-003"
)

$agentDisplayName = "*Monitor Agent*"
$regKey           = "HKLM:\SOFTWARE\MonitorAgent"
$serviceName      = "MonitorAgent"
# ----------------------------------------------------------------

$raiz   = Split-Path $PSScriptRoot -Parent
$psexec = Join-Path $raiz "PSTools\PsExec64.exe"
if (-not (Test-Path $psexec)) { Write-Host "PsExec nao encontrado em $psexec" -ForegroundColor Red; return }

$linhas = @(
    '$ErrorActionPreference = "SilentlyContinue"'
    ('$d = (Get-ItemProperty "' + $regKey + '" -ErrorAction SilentlyContinue).DeviceId')
    ('$s = (Get-Service "' + $serviceName + '" -ErrorAction SilentlyContinue).Status')
    '$keys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"'
    ('$app = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "' + $agentDisplayName + '" } | Select-Object -First 1')
    'Write-Output ("RESULT;DeviceId=" + $d + ";Servico=" + $s + ";Versao=" + $app.DisplayVersion)'
)
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($linhas -join "`n")))

$snap = foreach ($pc in $maquinas) {
    if (-not (Test-Connection -ComputerName $pc -Count 1 -Quiet)) {
        [PSCustomObject]@{ Maquina=$pc; DeviceId=""; Servico="OFFLINE"; Versao="" }; continue
    }
    $out = & $psexec "\\$pc" -r pvdeploy -s -nobanner -accepteula powershell -NoProfile -EncodedCommand $b64 2>$null
    $linha = ($out | Where-Object { $_ -like "RESULT;*" } | Select-Object -First 1)
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

$snap | Format-Table -AutoSize

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$csv   = Join-Path $raiz "resultado_inventario_$stamp.csv"
$snap | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "`nInventario salvo em: $csv" -ForegroundColor Cyan
