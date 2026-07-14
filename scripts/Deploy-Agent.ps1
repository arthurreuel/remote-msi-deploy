# ============================================================
#  Deploy-Agent.ps1  -  instala o agente onde falta (idempotente)
#  Config: config.psd1 na raiz | Rodar como administrador.
#     powershell -ExecutionPolicy Bypass -File .\scripts\Deploy-Agent.ps1
# ============================================================
. (Join-Path $PSScriptRoot "..\lib\Common.ps1")

$root = Split-Path $PSScriptRoot -Parent
$cfg  = Get-DeployConfig -Root $root
Assert-Prereq -Cfg $cfg -Need @('Msi','Token')

$token   = Get-Token -Cfg $cfg
$msiNome = $cfg.MsiFileName
Write-Host "Token carregado ($($token.Length) caracteres) | $($cfg.Machines.Count) maquina(s)." -ForegroundColor Cyan

# Checagem remota "ja instalado?" por DisplayName -> exit 10 = sim, 20 = nao
$check = @(
    '$keys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"'
    ('$app = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "' + $cfg.AgentDisplayName + '" } | Select-Object -First 1')
    'if ($app) { exit 10 } else { exit 20 }'
)

$relatorio = foreach ($pc in $cfg.Machines) {
    Write-Host "`n== $pc ==" -ForegroundColor Cyan

    if (-not (Test-MachineOnline $pc)) {
        Write-Host "  [OFFLINE] sem resposta de ping" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Codigo="OFFLINE"; Status="OFFLINE (sem ping)" }; continue
    }

    $unc = New-RemoteWorkDir -Cfg $cfg -ComputerName $pc
    if (-not $unc) {
        Write-Host "  [FALHA] Sem acesso a C$/SMB" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Codigo="SMB"; Status="Sem acesso C$" }; continue
    }

    $r = Invoke-RemotePS -Cfg $cfg -ComputerName $pc -Lines $check
    if ($r.ExitCode -eq 10) {
        Write-Host "  JA INSTALADO - pulando." -ForegroundColor Yellow
        [PSCustomObject]@{ Maquina=$pc; Codigo=0; Status="JA INSTALADO (pulado)" }; continue
    }

    Copy-Item $cfg.MsiPath "$unc\$msiNome" -Force
    Write-Host "  MSI copiado." -ForegroundColor Green

    $install = @(
        ('$p = Start-Process msiexec -Wait -PassThru -ArgumentList "/i","' + "$($cfg.WorkDir)\$msiNome" + '","' + $cfg.TokenProperty + '=' + $token + '","/qn","/norestart","/l*v","' + "$($cfg.WorkDir)\install.log" + '"')
        'exit $p.ExitCode'
    )
    $ri   = Invoke-RemotePS -Cfg $cfg -ComputerName $pc -Lines $install -Elevated
    $code = $ri.ExitCode

    $status = switch ($code) {
        0     { "SUCESSO" }
        3010  { "SUCESSO (requer reinicio)" }
        1603  { "FALHA 1603 - ver $($cfg.WorkDir)\install.log na maquina" }
        1619  { "FALHA 1619 - MSI nao encontrado" }
        default { "FALHA (cod. $code)" }
    }
    $cor = if ($code -in 0,3010) { "Green" } else { "Red" }
    Write-Host "  Resultado: $status" -ForegroundColor $cor
    [PSCustomObject]@{ Maquina=$pc; Codigo=$code; Status=$status }
}

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$relatorio | Format-Table -AutoSize
Save-Report -Cfg $cfg -Prefix "deploy" -Rows ($relatorio | Select-Object @{n='DataHora';e={Get-Date -Format 'yyyy-MM-dd HH:mm:ss'}}, Maquina, Codigo, Status) | Out-Null

$i = @($relatorio | Where-Object { $_.Status -like 'SUCESSO*' }).Count
$j = @($relatorio | Where-Object { $_.Status -like 'JA INSTALADO*' }).Count
$k = @($relatorio | Where-Object { $_.Status -notlike 'SUCESSO*' -and $_.Status -notlike 'JA INSTALADO*' }).Count
Write-Host ("Instaladas agora: {0}  |  Ja tinham: {1}  |  Pendentes/Falhas: {2}" -f $i,$j,$k) -ForegroundColor Cyan
