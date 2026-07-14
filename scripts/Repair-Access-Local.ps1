<#
  Repair-Access-Local.ps1  -  destrava o acesso RODANDO NA PROPRIA MAQUINA.
  Use quando o PsExec NAO alcança a maquina (C$/SMB bloqueado) - o remoto
  nao consegue entrar para consertar, entao este roda localmente.

  Como aplicar:
    a) GPO: Configuracao do Computador > Politicas > Config. do Windows >
       Scripts > Inicializacao (roda como SYSTEM no boot). OU
    b) Localmente na maquina, PowerShell como Administrador:
         powershell -ExecutionPolicy Bypass -File .\Repair-Access-Local.ps1

  Nao depende de config.psd1 nem de PsExec. Habilita compartilhamento de
  arquivos (C$/SMB) + descoberta de rede e garante o servico LanmanServer.
  Grava um log em C:\ProgramData\RemoteMsiDeploy\repair-access.log.
#>
$ErrorActionPreference = "SilentlyContinue"

$logDir = "C:\ProgramData\RemoteMsiDeploy"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force $logDir | Out-Null }
$log = Join-Path $logDir "repair-access.log"
function Write-Log($m) { "$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')  $m" | Tee-Object -FilePath $log -Append }

Write-Log "===== Repair-Access-Local em $env:COMPUTERNAME ====="

# Grupos locale-independentes:
#   File and Printer Sharing = @FirewallAPI.dll,-28502
#   Network Discovery        = @FirewallAPI.dll,-32752
Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28502"
Write-Log "Compartilhamento de Arquivos e Impressoras: habilitado."
Enable-NetFirewallRule -Group "@FirewallAPI.dll,-32752"
Write-Log "Descoberta de Rede: habilitada."

# Garante o servico de compartilhamento (Server / LanmanServer) ativo.
Set-Service LanmanServer -StartupType Automatic
Start-Service LanmanServer
Write-Log ("LanmanServer: " + (Get-Service LanmanServer).Status)

# Confirmacao
$n = (Get-NetFirewallRule -Group "@FirewallAPI.dll,-28502" | Where-Object { $_.Enabled -eq "True" } | Measure-Object).Count
Write-Log "Regras SMB ativas: $n"
Write-Log "Concluido. C$/SMB deve estar acessivel para o servidor de gestao."
