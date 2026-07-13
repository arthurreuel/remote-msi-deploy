# ============================================================
#  Reenroll-Agent.ps1
#  Forca o RE-REGISTRO do agente no servidor de monitoramento.
#  Use quando a maquina TEM o agente instalado e rodando, mas
#  NAO aparece no painel (identidade DeviceId/DeviceToken orfa).
#
#  Por maquina (como SYSTEM):
#    para o servico -> apaga DeviceId + DeviceToken + buffer local
#    -> inicia o servico -> aguarda ate 90s o novo DeviceId.
#  NAO reinstala nada. Seguro re-executar.
#
#  Rodar como administrador:
#     powershell -ExecutionPolicy Bypass -File .\scripts\Reenroll-Agent.ps1
# ============================================================

# --- CONFIGURACAO -----------------------------------------------
$maquinas = @(
    "WS-001","WS-002"                    # <- maquinas "invisiveis no painel"
)

$serviceName = "MonitorAgent"            # nome do servico Windows do agente
$regKey      = "HKLM:\SOFTWARE\MonitorAgent"   # chave de identidade do agente
$bufferPath  = "C:\ProgramData\MonitorAgent\buffer.db"
# ----------------------------------------------------------------

$raiz   = Split-Path $PSScriptRoot -Parent
$psexec = Join-Path $raiz "PSTools\PsExec64.exe"
if (-not (Test-Path $psexec)) { Write-Host "PsExec nao encontrado em $psexec" -ForegroundColor Red; return }

$remotoLinhas = @(
    '$ErrorActionPreference = "SilentlyContinue"'
    ('$svc = Get-Service "' + $serviceName + '" -ErrorAction SilentlyContinue')
    'if (-not $svc) { Write-Output "RESULT=SEM_SERVICO"; exit 20 }'
    ('$antes = (Get-ItemProperty "' + $regKey + '").DeviceId')
    ('Stop-Service "' + $serviceName + '" -Force')
    '$svc.WaitForStatus("Stopped","00:00:30")'
    ('Remove-ItemProperty -Path "' + $regKey + '" -Name DeviceId -Force')
    ('Remove-ItemProperty -Path "' + $regKey + '" -Name DeviceToken -Force')
    ('Remove-Item "' + $bufferPath + '" -Force')
    ('Start-Service "' + $serviceName + '"')
    '$depois = $null'
    ('for ($i=0; $i -lt 18; $i++) { Start-Sleep -Seconds 5; $depois = (Get-ItemProperty "' + $regKey + '").DeviceId; if ($depois) { break } }')
    'Write-Output ("RESULT=OK;ANTES=" + $antes + ";DEPOIS=" + $depois)'
    'exit 0'
)
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($remotoLinhas -join "`n")))

$relatorio = foreach ($pc in $maquinas) {
    Write-Host "`n== $pc ==" -ForegroundColor Cyan

    if (-not (Test-Connection -ComputerName $pc -Count 1 -Quiet)) {
        Write-Host "  [OFFLINE] sem resposta de ping" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=""; DeviceDepois=""; Status="OFFLINE (sem ping)" }; continue
    }

    $out = & $psexec "\\$pc" -r pvdeploy -s -h -nobanner -accepteula powershell -NoProfile -EncodedCommand $b64 2>$null
    $linha = ($out | Where-Object { $_ -like "RESULT=*" } | Select-Object -First 1)

    if (-not $linha) {
        Write-Host "  [FALHA] sem resposta do PsExec (SMB/Admin$?)" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=""; DeviceDepois=""; Status="FALHA (PsExec/SMB)" }; continue
    }
    if ($linha -like "RESULT=SEM_SERVICO*") {
        Write-Host "  SEM AGENTE - use Deploy-Agent.ps1 nesta maquina." -ForegroundColor Yellow
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=""; DeviceDepois=""; Status="SEM AGENTE (instalar)" }; continue
    }

    $antes  = ($linha -replace '.*ANTES=([^;]*).*','$1')
    $depois = ($linha -replace '.*DEPOIS=([^;]*).*','$1')

    if ($depois -and $depois -ne $antes) {
        Write-Host "  REENROLLED (Device $antes -> $depois)" -ForegroundColor Green
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=$antes; DeviceDepois=$depois; Status="REENROLLED" }
    } elseif ($depois) {
        Write-Host "  DeviceId presente ($depois) - conferir painel" -ForegroundColor Yellow
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=$antes; DeviceDepois=$depois; Status="OK (mesmo id)" }
    } else {
        Write-Host "  DeviceId VAZIO - nao registrou (ver conectividade)" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=$antes; DeviceDepois=$depois; Status="VAZIO (nao registrou)" }
    }
}

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$relatorio | Format-Table -AutoSize

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$csv   = Join-Path $raiz "resultado_reenroll_$stamp.csv"
$relatorio | Select-Object @{n='DataHora';e={$stamp}}, Maquina, DeviceAntes, DeviceDepois, Status |
    Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "`nRelatorio salvo em: $csv" -ForegroundColor Cyan
Write-Host ">>> Confira no painel de monitoramento se as REENROLLED aparecem. <<<" -ForegroundColor Yellow
