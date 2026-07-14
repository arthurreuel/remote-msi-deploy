<#
  Provision-Assets.ps1  -  garante os binarios necessarios na pasta:
    - PsExec64.exe em PSTools\  (copia de PsExecSource ou baixa do Sysinternals)
    - o .msi mais recente vindo de MsiSource (pasta de rede/SysVol ou arquivo)

  Nao precisa de lista de maquinas. Config: config.psd1 (chaves MsiSource /
  PsExecSource). Rodar:
    powershell -ExecutionPolicy Bypass -File .\scripts\Provision-Assets.ps1
#>
. (Join-Path $PSScriptRoot "..\lib\Common.ps1")

$root = Split-Path $PSScriptRoot -Parent
$cfg  = Get-DeployConfig -Root $root -SkipMachineCheck

Write-Host "Provisionando binarios em: $root" -ForegroundColor Cyan
if ($cfg.MsiSource) { Write-Host "  Origem do MSI: $($cfg.MsiSource)" -ForegroundColor Gray }

$msgs = Invoke-ProvisionAssets -Cfg $cfg
foreach ($m in $msgs) {
    $cor = if ($m -match 'FALHA|inacessivel|nenhum') { 'Red' } else { 'Green' }
    Write-Host "  $m" -ForegroundColor $cor
}

# Verificacao final
$okPsexec = Test-Path $cfg.PsExecPath
$okMsi    = Test-Path $cfg.MsiPath
Write-Host "`nPronto para executar fluxos? PsExec=$okPsexec  MSI=$okMsi" -ForegroundColor Cyan
