<#
  Uninstall-Agent.ps1  -  REMOVE o agente das maquinas da lista.
  -Purge : alem de desinstalar, apaga a chave de registro e o ProgramData
           (limpeza total - deixa a maquina "virgem").
  -Force : pula a confirmacao (o Menu ja confirma e passa -Force).

  Nao precisa de token nem do MSI (desinstala pelo ProductCode que ja esta
  na maquina). Config: config.psd1. Rodar como administrador.
    powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-Agent.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-Agent.ps1 -Purge
#>
param([switch]$Purge, [switch]$Force)
. (Join-Path $PSScriptRoot "..\lib\Common.ps1")

$root = Split-Path $PSScriptRoot -Parent
$cfg  = Get-DeployConfig -Root $root
Assert-Prereq -Cfg $cfg
Write-Host "$($cfg.Machines.Count) maquina(s) | modo: $(if ($Purge) {'DESINSTALAR + PURGAR'} else {'DESINSTALAR'})" -ForegroundColor Cyan

if (-not $Force) {
    Write-Host "`n[!] Isto REMOVE o agente das maquinas listadas." -ForegroundColor Yellow
    if ($Purge) { Write-Host "    -Purge tambem apaga registro e ProgramData (irreversivel)." -ForegroundColor Yellow }
    if ((Read-Host "    Digite SIM para confirmar") -ne 'SIM') { Write-Host "    Cancelado."; return }
}

# Monta o script remoto (roda como SYSTEM): desinstala todas as versoes e,
# se -Purge, apaga registro + ProgramData; ao final confirma a remocao.
$linhas = @(
    '$ErrorActionPreference = "SilentlyContinue"'
    '$keys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")'
    ('$apps = Get-ItemProperty $keys | Where-Object { $_.DisplayName -like "' + $cfg.AgentDisplayName + '" }')
    'if (-not $apps) { Write-Output "RESULT=NAO_INSTALADO"; exit 0 }'
    'foreach ($a in $apps) { Start-Process msiexec -Wait -ArgumentList "/x",$a.PSChildName,"/qn","/norestart" }'
)
if ($Purge) {
    $linhas += ('Remove-Item "' + $cfg.RegistryKey + '" -Recurse -Force')
    $linhas += ('Remove-Item "' + $cfg.DataDir + '" -Recurse -Force')
}
$linhas += @(
    ('$still = Get-ItemProperty $keys | Where-Object { $_.DisplayName -like "' + $cfg.AgentDisplayName + '" }')
    'if ($still) { Write-Output "RESULT=FALHA_PRESENTE"; exit 1 } else { Write-Output "RESULT=REMOVIDO"; exit 0 }'
)

$relatorio = foreach ($pc in $cfg.Machines) {
    Write-Host "`n== $pc ==" -ForegroundColor Cyan

    if (-not (Test-MachineOnline $pc)) {
        Write-Host "  [OFFLINE] sem resposta de ping" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Status="OFFLINE (sem ping)" }; continue
    }

    $r = Invoke-RemotePSWithRetry -Cfg $cfg -ComputerName $pc -Lines $linhas -Elevated `
             -MaxTries ([int]$cfg.RetryCount) -DelaySeconds ([int]$cfg.RetryDelaySeconds) -SuccessPattern 'RESULT='
    $linha = ($r.Output | Where-Object { $_ -like "RESULT=*" } | Select-Object -First 1)

    if (-not $linha) {
        Write-Host "  [FALHA] sem resposta do PsExec (sessao admin? SMB/Admin`$?)" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Status="FALHA (PsExec/SMB)" }; continue
    }
    switch -Wildcard ($linha) {
        "*NAO_INSTALADO*"  { Write-Host "  Nao tinha o agente." -ForegroundColor Yellow;  $st="NAO INSTALADO" }
        "*REMOVIDO*"       { Write-Host "  REMOVIDO." -ForegroundColor Green;             $st="REMOVIDO" }
        "*FALHA_PRESENTE*" { Write-Host "  FALHA - ainda presente." -ForegroundColor Red; $st="FALHA (ainda presente)" }
        default            { Write-Host "  Resposta inesperada." -ForegroundColor Red;    $st="FALHA (inesperado)" }
    }
    [PSCustomObject]@{ Maquina=$pc; Status=$st }
}

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$relatorio | Format-Table -AutoSize
Save-Report -Cfg $cfg -Prefix "uninstall" -Rows ($relatorio | Select-Object @{n='DataHora';e={Get-Date -Format 'yyyy-MM-dd HH:mm:ss'}}, Maquina, Status) | Out-Null

$rem = @($relatorio | Where-Object { $_.Status -eq 'REMOVIDO' }).Count
$fal = @($relatorio | Where-Object { $_.Status -like 'FALHA*' }).Count
Write-Host ("Removidas: {0}  |  Falhas: {1}" -f $rem, $fal) -ForegroundColor Cyan
