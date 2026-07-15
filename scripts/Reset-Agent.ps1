# ============================================================
#  Reset-Agent.ps1  -  reset completo + diagnostico de conectividade
#  Ultimo recurso: desinstala + purga registro/ProgramData +
#  reinstala + testa HTTP/443/porta-websocket. Gera diag_<PC>.txt.
#  Config: config.psd1. Rodar como administrador.
#     powershell -ExecutionPolicy Bypass -File .\scripts\Reset-Agent.ps1
# ============================================================
. (Join-Path $PSScriptRoot "..\lib\Common.ps1")

$root = Split-Path $PSScriptRoot -Parent
$cfg  = Get-DeployConfig -Root $root
Assert-Prereq -Cfg $cfg -Need @('Msi','Token')

$token   = Get-Token -Cfg $cfg
$msiNome = $cfg.MsiFileName
Write-Host "$($cfg.Machines.Count) maquina(s) para reset completo." -ForegroundColor Cyan

$reset = @(
    '$ErrorActionPreference = "SilentlyContinue"'
    ('$msi = "' + "$($cfg.WorkDir)\$msiNome" + '"')
    ('$log = "' + "$($cfg.WorkDir)\install.log" + '"')
    '$keys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")'
    ('$apps = Get-ItemProperty $keys | Where-Object { $_.DisplayName -like "' + $cfg.AgentDisplayName + '" }')
    'foreach ($a in $apps) { Start-Process msiexec -Wait -ArgumentList "/x",$a.PSChildName,"/qn","/norestart" }'
    ('Remove-Item "' + $cfg.RegistryKey + '" -Recurse -Force')
    ('Remove-Item "' + $cfg.DataDir + '" -Recurse -Force')
    ('$pi = Start-Process msiexec -Wait -PassThru -ArgumentList "/i",$msi,"' + $cfg.TokenProperty + '=' + $token + '","/qn","/norestart","/l*v",$log')
    '$dev = $null'
    ('for ($i=0; $i -lt 18; $i++){ Start-Sleep 5; $dev=(Get-ItemProperty "' + $cfg.RegistryKey + '").DeviceId; if($dev){break} }')
    ('$p = Get-ItemProperty "' + $cfg.RegistryKey + '"')
    ('$svc = (Get-Service "' + $cfg.ServiceName + '").Status')
    '$u = [Uri]$p.ServerUrl'
    '$http = try { "OK/" + (Invoke-WebRequest -Uri $p.ServerUrl -UseBasicParsing -TimeoutSec 15).StatusCode } catch { "ERRO" }'
    '$t443 = (Test-NetConnection -ComputerName $u.Host -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded'
    '$tws = if ($p.ReverbPort) { (Test-NetConnection -ComputerName $u.Host -Port $p.ReverbPort -WarningAction SilentlyContinue).TcpTestSucceeded } else { "n/a" }'
    'Write-Output ("RESULT;ExitInstall=" + $pi.ExitCode + ";DeviceId=" + $dev + ";Servico=" + $svc + ";HTTP=" + $http + ";P443=" + $t443 + ";PortaWS=" + $tws)'
    # Seguranca: remove o MSI e o install.log (com o token) de C:\Temp em caso de sucesso.
    'if ($pi.ExitCode -in 0,3010) { Remove-Item $msi,$log -Force -ErrorAction SilentlyContinue }'
    'exit $pi.ExitCode'
)

$rel = foreach ($pc in $cfg.Machines) {
    Write-Host "`n===== $pc =====" -ForegroundColor Cyan
    if (-not (Test-MachineOnline $pc)) {
        Write-Host "  OFFLINE (rede)" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Info="OFFLINE (rede)" }; continue
    }
    $unc = New-RemoteWorkDir -Cfg $cfg -ComputerName $pc
    if (-not $unc) {
        Write-Host "  SMB (sem acesso C$)" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Info="Sem acesso C$" }; continue
    }
    Copy-Item $cfg.MsiPath "$unc\$msiNome" -Force
    Write-Host "  MSI copiado. Reset + reinstall + reenroll (~2min)..." -ForegroundColor Gray

    $r   = Invoke-RemotePS -Cfg $cfg -ComputerName $pc -Lines $reset -Elevated
    $arq = Join-Path (Get-LogDir -Cfg $cfg) "diag_$pc.txt"; $r.Output | Out-File $arq -Encoding UTF8
    $key = ($r.Output | Where-Object { $_ -like "RESULT;*" } | Select-Object -First 1)
    Write-Host "  $key" -ForegroundColor Green
    Write-Host "  (detalhe em $arq)" -ForegroundColor DarkGray
    [PSCustomObject]@{ Maquina=$pc; Info=$key }
}

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$rel | Format-Table -AutoSize -Wrap
