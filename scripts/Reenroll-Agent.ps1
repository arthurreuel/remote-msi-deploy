# ============================================================
#  Reenroll-Agent.ps1  -  forca novo registro no servidor
#  Use quando o agente esta instalado/rodando mas NAO aparece
#  no painel (identidade DeviceId/DeviceToken orfa).
#  NAO reinstala. Config: config.psd1. Rodar como administrador.
#     powershell -ExecutionPolicy Bypass -File .\scripts\Reenroll-Agent.ps1
# ============================================================
. (Join-Path $PSScriptRoot "..\lib\Common.ps1")

$root = Split-Path $PSScriptRoot -Parent
$cfg  = Get-DeployConfig -Root $root
Assert-Prereq -Cfg $cfg
Write-Host "$($cfg.Machines.Count) maquina(s) para re-enroll." -ForegroundColor Cyan

$reenroll = @(
    '$ErrorActionPreference = "SilentlyContinue"'
    ('$svc = Get-Service "' + $cfg.ServiceName + '" -ErrorAction SilentlyContinue')
    'if (-not $svc) { Write-Output "RESULT=SEM_SERVICO"; exit 20 }'
    ('$antes = (Get-ItemProperty "' + $cfg.RegistryKey + '").DeviceId')
    ('Stop-Service "' + $cfg.ServiceName + '" -Force')
    '$svc.WaitForStatus("Stopped","00:00:30")'
    ('Remove-ItemProperty -Path "' + $cfg.RegistryKey + '" -Name DeviceId -Force')
    ('Remove-ItemProperty -Path "' + $cfg.RegistryKey + '" -Name DeviceToken -Force')
    ('Remove-Item "' + $cfg.BufferFile + '" -Force')
    ('Start-Service "' + $cfg.ServiceName + '"')
    '$depois = $null'
    ('for ($i=0; $i -lt 18; $i++) { Start-Sleep -Seconds 5; $depois = (Get-ItemProperty "' + $cfg.RegistryKey + '").DeviceId; if ($depois) { break } }')
    'Write-Output ("RESULT=OK;ANTES=" + $antes + ";DEPOIS=" + $depois)'
    'exit 0'
)

$relatorio = foreach ($pc in $cfg.Machines) {
    Write-Host "`n== $pc ==" -ForegroundColor Cyan

    if (-not (Test-MachineOnline $pc)) {
        Write-Host "  [OFFLINE]" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=""; DeviceDepois=""; Status="OFFLINE (sem ping)" }; continue
    }

    $r = Invoke-RemotePS -Cfg $cfg -ComputerName $pc -Lines $reenroll -Elevated
    $linha = ($r.Output | Where-Object { $_ -like "RESULT=*" } | Select-Object -First 1)

    if (-not $linha) {
        Write-Host "  [FALHA] sem resposta do PsExec. Sessao sem admin? Informe Usuario/Senha admin no Configurar." -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; DeviceAntes=""; DeviceDepois=""; Status="FALHA (PsExec/SMB)" }; continue
    }
    if ($linha -like "RESULT=SEM_SERVICO*") {
        Write-Host "  SEM AGENTE - use Deploy-Agent.ps1." -ForegroundColor Yellow
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

Disconnect-RemoteShares -Cfg $cfg -Machines $cfg.Machines

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$relatorio | Format-Table -AutoSize
Save-Report -Cfg $cfg -Prefix "reenroll" -Rows ($relatorio | Select-Object @{n='DataHora';e={Get-Date -Format 'yyyy-MM-dd HH:mm:ss'}}, Maquina, DeviceAntes, DeviceDepois, Status) | Out-Null
Write-Host ">>> Confira no painel se as REENROLLED aparecem. <<<" -ForegroundColor Yellow
