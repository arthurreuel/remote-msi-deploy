<#
  Menu.ps1 - lancador dos fluxos internos do toolkit.

  Uso interativo:
      powershell -ExecutionPolicy Bypass -File .\Menu.ps1
  Uso direto (automacao / atalho):
      powershell -ExecutionPolicy Bypass -File .\Menu.ps1 -Flow Deploy
      (-Flow aceita: Inventory | Deploy | Reenroll | Reset)
#>
param(
    [ValidateSet('Inventory','Deploy','Reenroll','Reset')]
    [string]$Flow
)

$root = $PSScriptRoot
. (Join-Path $root "lib\Common.ps1")

$scripts = @{
    Inventory = 'scripts\Get-AgentInventory.ps1'
    Deploy    = 'scripts\Deploy-Agent.ps1'
    Reenroll  = 'scripts\Reenroll-Agent.ps1'
    Reset     = 'scripts\Reset-Agent.ps1'
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Flow {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -eq 'Reset') {
        Write-Host "`n[!] RESET COMPLETO desinstala, purga registro/ProgramData e reinstala." -ForegroundColor Yellow
        Write-Host "    Use somente nas maquinas que resistiram ao Re-enroll." -ForegroundColor Yellow
        if ((Read-Host "    Digite SIM para confirmar") -ne 'SIM') {
            Write-Host "    Cancelado." -ForegroundColor DarkYellow; return
        }
    }
    $path = Join-Path $root $scripts[$Name]
    Write-Host "`n>>> Executando fluxo: $Name`n" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $path
    Write-Host "`n<<< Fluxo $Name finalizado." -ForegroundColor Cyan
}

function Show-Header {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-Host "  Remote MSI Deploy - fluxos internos" -ForegroundColor White
    try {
        $cfg = Get-DeployConfig -Root $root
        Write-Host "  Agente : $($cfg.AgentDisplayName)   Servico: $($cfg.ServiceName)" -ForegroundColor Gray
        Write-Host "  Alvos  : $($cfg.Machines.Count) maquina(s)" -ForegroundColor Gray
    } catch {
        Write-Host "  [config.psd1 pendente] $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "==================================================" -ForegroundColor DarkCyan
}

if (-not (Test-Admin)) {
    Write-Host "AVISO: rode como Administrador (precisa de C$/SCM nas estacoes)." -ForegroundColor Yellow
}

# --- Modo direto (nao-interativo) ---
if ($Flow) { Invoke-Flow -Name $Flow; return }

# --- Modo interativo ---
do {
    Show-Header
    Write-Host "  1) Inventario  (somente leitura: DeviceId, servico, versao)"
    Write-Host "  2) Deploy      (instala onde falta - idempotente)"
    Write-Host "  3) Re-enroll   (renova identidade - conserta 'offline no painel')"
    Write-Host "  4) Reset       (purga + reinstala + diagnostica - ultimo recurso)"
    Write-Host "  0) Sair"
    $op = Read-Host "`n  Escolha"
    switch ($op) {
        '1' { Invoke-Flow Inventory }
        '2' { Invoke-Flow Deploy }
        '3' { Invoke-Flow Reenroll }
        '4' { Invoke-Flow Reset }
        '0' { }
        default { Write-Host "  Opcao invalida." -ForegroundColor Red }
    }
    if ($op -ne '0') { Read-Host "`n  Pressione Enter para voltar ao menu" | Out-Null }
} while ($op -ne '0')

Write-Host "Ate mais." -ForegroundColor DarkCyan
