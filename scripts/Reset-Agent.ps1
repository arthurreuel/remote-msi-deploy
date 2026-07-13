# ============================================================
#  Reset-Agent.ps1
#  RESET COMPLETO do agente + diagnostico de conectividade.
#  Para maquinas que resistem ao re-enroll simples.
#
#  Por maquina (como SYSTEM):
#    desinstala TODAS as versoes (por DisplayName) ->
#    purga a chave de registro do agente e o ProgramData ->
#    reinstala com o token -> aguarda enrollment (ate 90s) ->
#    testa HTTP ao servidor + TCP 443 + TCP porta websocket.
#  Gera diag_<PC>.txt por maquina + linha-resumo RESULT.
#
#  Rodar como administrador:
#     powershell -ExecutionPolicy Bypass -File .\scripts\Reset-Agent.ps1
# ============================================================

# --- CONFIGURACAO -----------------------------------------------
$maquinas = @(
    "WS-001"                              # <- maquinas problematicas
)

$agentDisplayName = "*Monitor Agent*"
$propToken        = "TENANT_TOKEN"
$regKey           = "HKLM:\SOFTWARE\MonitorAgent"
$dataDir          = "C:\ProgramData\MonitorAgent"
$serviceName      = "MonitorAgent"
# ----------------------------------------------------------------

$raiz      = Split-Path $PSScriptRoot -Parent
$msiOrigem = Join-Path $raiz "Agent.msi"
$tokenArq  = Join-Path $raiz "token.txt"
$psexec    = Join-Path $raiz "PSTools\PsExec64.exe"

foreach ($req in $msiOrigem, $tokenArq, $psexec) {
    if (-not (Test-Path $req)) { Write-Host "Arquivo obrigatorio ausente: $req" -ForegroundColor Red; return }
}
$token   = (Get-Content $tokenArq -Raw).Trim()
$msiNome = "Agent.msi"

$linhas = @(
    '$ErrorActionPreference = "SilentlyContinue"'
    '$msi = "C:\Temp\Agent.msi"'
    '$log = "C:\Temp\install.log"'
    '$token = "__TOKEN__"'
    '$keys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")'
    ('$apps = Get-ItemProperty $keys | Where-Object { $_.DisplayName -like "' + $agentDisplayName + '" }')
    'foreach ($a in $apps) { Start-Process msiexec -Wait -ArgumentList "/x",$a.PSChildName,"/qn","/norestart" }'
    ('Remove-Item "' + $regKey + '" -Recurse -Force')
    ('Remove-Item "' + $dataDir + '" -Recurse -Force')
    ('$pi = Start-Process msiexec -Wait -PassThru -ArgumentList "/i",$msi,"' + $propToken + '=$token","/qn","/norestart","/l*v",$log')
    '$dev = $null'
    ('for ($i=0; $i -lt 18; $i++){ Start-Sleep 5; $dev=(Get-ItemProperty "' + $regKey + '").DeviceId; if($dev){break} }')
    ('$p = Get-ItemProperty "' + $regKey + '"')
    ('$svc = (Get-Service "' + $serviceName + '").Status')
    '$u = [Uri]$p.ServerUrl'
    '$http = try { "OK/" + (Invoke-WebRequest -Uri $p.ServerUrl -UseBasicParsing -TimeoutSec 15).StatusCode } catch { "ERRO" }'
    '$t443 = (Test-NetConnection -ComputerName $u.Host -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded'
    '$tws = if ($p.ReverbPort) { (Test-NetConnection -ComputerName $u.Host -Port $p.ReverbPort -WarningAction SilentlyContinue).TcpTestSucceeded } else { "n/a" }'
    'Write-Output ("RESULT;ExitInstall=" + $pi.ExitCode + ";DeviceId=" + $dev + ";Servico=" + $svc + ";HTTP=" + $http + ";P443=" + $t443 + ";PortaWS=" + $tws)'
    'exit $pi.ExitCode'
)
$remoto = ($linhas -join "`n").Replace("__TOKEN__", $token)
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remoto))

$rel = foreach ($pc in $maquinas) {
    Write-Host "`n===== $pc =====" -ForegroundColor Cyan
    if (-not (Test-Connection -ComputerName $pc -Count 1 -Quiet)) {
        Write-Host "  OFFLINE (rede)" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Info="OFFLINE (rede)" }; continue
    }
    $unc = "\\$pc\C$\Temp"
    if (-not (Test-Path $unc)) { New-Item -ItemType Directory -Path $unc -Force | Out-Null }
    Copy-Item $msiOrigem "$unc\$msiNome" -Force
    Write-Host "  MSI copiado. Reset + reinstall + reenroll (~2min)..." -ForegroundColor Gray
    $out = & $psexec "\\$pc" -r pvdeploy -s -h -nobanner -accepteula powershell -NoProfile -EncodedCommand $b64 2>$null
    $arq = Join-Path $raiz "diag_$pc.txt"; $out | Out-File $arq -Encoding UTF8
    $key = ($out | Where-Object { $_ -like "RESULT;*" } | Select-Object -First 1)
    Write-Host "  $key" -ForegroundColor Green
    Write-Host "  (detalhe em $arq)" -ForegroundColor DarkGray
    [PSCustomObject]@{ Maquina=$pc; Info=$key }
}

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$rel | Format-Table -AutoSize -Wrap
