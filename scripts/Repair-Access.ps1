<#
  Repair-Access.ps1  -  repara pre-requisitos de acesso nas maquinas.
  Roda via PsExec (para maquinas JA alcançaveis). Config: config.psd1.

  Acoes (-Action):
    EnableSharing   - habilita "Compartilhamento de Arquivos e Impressoras" +
                      "Descoberta de Rede" no firewall e garante o servico
                      LanmanServer (destrava C$/SMB).
    DisableFirewall - desativa os 3 perfis do firewall (Dominio/Privado/Publico).
                      Uso temporario/diagnostico. Pede confirmacao (ou -Force).
    EnableFirewall  - reativa os 3 perfis do firewall (reversao).

  ATENCAO: se o C$/SMB ja estiver bloqueado, o PsExec NAO alcanca a maquina
  para aplicar EnableSharing. Nesse caso use scripts\Repair-Access-Local.ps1
  via GPO Startup ou execucao local. Ver docs\USAGE.md.

  Exemplos:
    powershell -ExecutionPolicy Bypass -File .\scripts\Repair-Access.ps1 -Action EnableSharing
    powershell -ExecutionPolicy Bypass -File .\scripts\Repair-Access.ps1 -Action DisableFirewall -Force
#>
param(
    [ValidateSet('EnableSharing','DisableFirewall','EnableFirewall')]
    [string]$Action,
    [switch]$Force
)
. (Join-Path $PSScriptRoot "..\lib\Common.ps1")

$root = Split-Path $PSScriptRoot -Parent
$cfg  = Get-DeployConfig -Root $root
Assert-Prereq -Cfg $cfg

if (-not $Action) {
    Write-Host "Acao nao informada. Escolha:" -ForegroundColor Yellow
    Write-Host "  1) EnableSharing    (habilita C$/SMB + descoberta de rede)"
    Write-Host "  2) DisableFirewall  (desativa firewall - temporario)"
    Write-Host "  3) EnableFirewall   (reativa firewall)"
    switch (Read-Host "Opcao") { '1'{$Action='EnableSharing'} '2'{$Action='DisableFirewall'} '3'{$Action='EnableFirewall'} default{ Write-Host "Cancelado."; return } }
}

if ($Action -eq 'DisableFirewall' -and -not $Force) {
    Write-Host "`n[!] Desativar o firewall expoe a maquina. Use por janela minima e reative depois." -ForegroundColor Yellow
    if ((Read-Host "    Digite SIM para confirmar") -ne 'SIM') { Write-Host "    Cancelado."; return }
}

# Grupos de regra locale-independentes (funciona em Windows PT-BR/EN):
#   File and Printer Sharing = @FirewallAPI.dll,-28502
#   Network Discovery        = @FirewallAPI.dll,-32752
$linhasPorAcao = @{
    EnableSharing = @(
        '$ErrorActionPreference = "SilentlyContinue"'
        'Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28502"'
        'Enable-NetFirewallRule -Group "@FirewallAPI.dll,-32752"'
        'Set-Service LanmanServer -StartupType Automatic'
        'Start-Service LanmanServer'
        '$n = (Get-NetFirewallRule -Group "@FirewallAPI.dll,-28502" | Where-Object { $_.Enabled -eq "True" } | Measure-Object).Count'
        'Write-Output ("RESULT;Acao=EnableSharing;RegrasSMBAtivas=" + $n + ";LanmanServer=" + (Get-Service LanmanServer).Status)'
    )
    DisableFirewall = @(
        '$ErrorActionPreference = "SilentlyContinue"'
        'Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False'
        '$s = ((Get-NetFirewallProfile) | ForEach-Object { $_.Name + "=" + $_.Enabled }) -join ","'
        'Write-Output ("RESULT;Acao=DisableFirewall;" + $s)'
    )
    EnableFirewall = @(
        '$ErrorActionPreference = "SilentlyContinue"'
        'Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True'
        '$s = ((Get-NetFirewallProfile) | ForEach-Object { $_.Name + "=" + $_.Enabled }) -join ","'
        'Write-Output ("RESULT;Acao=EnableFirewall;" + $s)'
    )
}
$linhas = $linhasPorAcao[$Action]
Write-Host "Acao: $Action | $($cfg.Machines.Count) maquina(s)." -ForegroundColor Cyan

$relatorio = foreach ($pc in $cfg.Machines) {
    Write-Host "`n== $pc ==" -ForegroundColor Cyan

    if (-not (Test-MachineOnline $pc)) {
        Write-Host "  [OFFLINE] sem resposta de ping" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Acao=$Action; Detalhe="OFFLINE (sem ping)" }; continue
    }

    $r = Invoke-RemotePSWithRetry -Cfg $cfg -ComputerName $pc -Lines $linhas -Elevated `
             -MaxTries ([int]$cfg.RetryCount) -DelaySeconds ([int]$cfg.RetryDelaySeconds) -SuccessPattern 'RESULT;'
    $linha = ($r.Output | Where-Object { $_ -like "RESULT;*" } | Select-Object -First 1)

    if (-not $linha) {
        Write-Host ("  [FALHA] sem resposta do PsExec apos {0} tentativa(s) - SMB/Admin`$ bloqueado?" -f $cfg.RetryCount) -ForegroundColor Red
        Write-Host "    -> C`$/SMB provavelmente bloqueado ou sessao SEM privilegio de admin." -ForegroundColor DarkYellow
        Write-Host "       Verifique: (1) menu aberto como Administrador; (2) Repair-Access-Local.ps1 via GPO." -ForegroundColor DarkYellow
        [PSCustomObject]@{ Maquina=$pc; Acao=$Action; Detalhe="FALHA (PsExec/SMB) apos $($cfg.RetryCount) tentativas" }; continue
    }

    $det = ($linha -replace '^RESULT;','')
    Write-Host "  OK: $det" -ForegroundColor Green
    [PSCustomObject]@{ Maquina=$pc; Acao=$Action; Detalhe=$det }
}

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$relatorio | Format-Table -AutoSize -Wrap
Save-Report -Cfg $cfg -Prefix "repair-$Action" -Rows ($relatorio | Select-Object @{n='DataHora';e={Get-Date -Format 'yyyy-MM-dd HH:mm:ss'}}, Maquina, Acao, Detalhe) | Out-Null

if ($Action -eq 'DisableFirewall') {
    Write-Host "`n>>> Lembrete: reative o firewall depois com -Action EnableFirewall. <<<" -ForegroundColor Yellow
}
