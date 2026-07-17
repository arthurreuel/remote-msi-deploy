<#
  Menu.ps1 - lancador dos fluxos internos do toolkit.

  Uso interativo:
      powershell -ExecutionPolicy Bypass -File .\Menu.ps1
  Uso direto (automacao / atalho):
      powershell -ExecutionPolicy Bypass -File .\Menu.ps1 -Flow Deploy
      (-Flow aceita: Inventory | Deploy | Reenroll | Reset)
#>
param(
    [ValidateSet('Inventory','Deploy','Reenroll','Reset','Provision')]
    [string]$Flow
)

$root = $PSScriptRoot
. (Join-Path $root "lib\Common.ps1")

$scripts = @{
    Inventory = 'scripts\Get-AgentInventory.ps1'
    Deploy    = 'scripts\Deploy-Agent.ps1'
    Reenroll  = 'scripts\Reenroll-Agent.ps1'
    Reset     = 'scripts\Reset-Agent.ps1'
    Provision = 'scripts\Provision-Assets.ps1'
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

function Invoke-Repair {
    Write-Host "`n  Reparar acesso (pre-requisitos das estacoes):" -ForegroundColor Cyan
    Write-Host "   a) Habilitar compartilhamento  (C$/SMB + descoberta de rede)"
    Write-Host "   b) Desativar firewall          (temporario / diagnostico)"
    Write-Host "   c) Reativar firewall"
    $map = @{ a='EnableSharing'; b='DisableFirewall'; c='EnableFirewall' }
    $act = $map[(Read-Host "   Escolha (a/b/c)")]
    if (-not $act) { Write-Host "   Cancelado." -ForegroundColor DarkYellow; return }

    $callArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\Repair-Access.ps1'),'-Action',$act)
    if ($act -eq 'DisableFirewall') {
        Write-Host "   [!] Desativar o firewall expoe a maquina - use por janela minima." -ForegroundColor Yellow
        if ((Read-Host "   Digite SIM para confirmar") -ne 'SIM') { Write-Host "   Cancelado."; return }
        $callArgs += '-Force'
    }
    Write-Host "`n>>> Reparar acesso: $act`n" -ForegroundColor Cyan
    & powershell @callArgs
    Write-Host "`n<<< Reparar acesso finalizado." -ForegroundColor Cyan
    if ($act -eq 'EnableSharing') {
        Write-Host "    (Para maquinas que o PsExec NAO alcanca, use scripts\Repair-Access-Local.ps1 via GPO.)" -ForegroundColor DarkGray
    }
}

function Invoke-Uninstall {
    Write-Host "`n  Remover agente das estacoes:" -ForegroundColor Cyan
    Write-Host "   u) Desinstalar"
    Write-Host "   p) Desinstalar + purgar registro/ProgramData (limpeza total)"
    $sub = Read-Host "   Escolha (u/p)"
    $callArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\Uninstall-Agent.ps1'))
    if     ($sub -eq 'p') { $callArgs += '-Purge' }
    elseif ($sub -ne 'u') { Write-Host "   Cancelado." -ForegroundColor DarkYellow; return }
    Write-Host "   [!] Isto REMOVE o agente das maquinas da lista." -ForegroundColor Yellow
    if ($sub -eq 'p') { Write-Host "       O purge apaga registro e ProgramData (irreversivel)." -ForegroundColor Yellow }
    if ((Read-Host "   Digite SIM para confirmar") -ne 'SIM') { Write-Host "   Cancelado."; return }
    $callArgs += '-Force'
    Write-Host "`n>>> Removendo agente...`n" -ForegroundColor Cyan
    & powershell @callArgs
    Write-Host "`n<<< Remocao finalizada." -ForegroundColor Cyan
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

# --- Auto-elevacao: PsExec precisa de Administrador para acessar Admin$/SCM
#     das estacoes. Se nao estiver elevado, reabre este menu como admin (UAC).
if (-not (Test-Admin)) {
    Write-Host "Elevando para Administrador (necessario para o PsExec acessar as estacoes)..." -ForegroundColor Yellow
    $relArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    if ($Flow) { $relArgs += @('-Flow', $Flow) }
    try {
        Start-Process powershell -Verb RunAs -ArgumentList $relArgs
    } catch {
        Write-Host "Elevacao cancelada/negada. O menu precisa de Administrador para funcionar." -ForegroundColor Red
        Read-Host "Pressione Enter para sair" | Out-Null
    }
    return
}

# --- Auto-provisionamento (portabilidade): se esta e uma copia recem-transportada
#     sem PsExec (ou sem o MSI), busca os binarios antes de comecar.
try {
    $cfg0 = Get-DeployConfig -Root $root -SkipMachineCheck
    $faltaPsexec = -not (Test-Path $cfg0.PsExecPath)
    $faltaMsi    = $cfg0.MsiSource -and -not (Test-Path $cfg0.MsiPath)
    if ($faltaPsexec -or $faltaMsi) {
        Write-Host "Primeira execucao nesta maquina: provisionando binarios..." -ForegroundColor Yellow
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Provision-Assets.ps1')
        Write-Host ""
    }
} catch { }

# --- Credencial: por padrao usa a IDENTIDADE DA SESSAO (usuario logado no
#     servidor). So pede credencial de admin do DOMINIO se o usuario logado
#     NAO for admin de dominio (grupos com SID -512 Domain Admins / -519
#     Enterprise Admins). Assim, quem opera como admin de dominio nao ve prompt.
if (-not $Flow -and -not $env:RMD_CRED) {
    $grp = [Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value
    $isDomAdmin = @($grp | Where-Object { $_ -match '-512$' -or $_ -match '-519$' }).Count -gt 0
    if ($isDomAdmin) {
        Write-Host "Usando as credenciais da sua sessao (admin de dominio detectado)." -ForegroundColor Green
    } else {
        Write-Host "Sua sessao nao e admin de dominio - operacoes nas estacoes podem exigir credencial." -ForegroundColor Yellow
        $u = Read-Host "  Usuario admin do DOMINIO (Enter em branco = tentar com a sessao atual)"
        if ($u) {
            $sp = Read-Host "  Senha" -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sp)
            try { $p = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            $env:RMD_CRED = Protect-String -Plain ("$u`n$p")
            Write-Host "  Credencial definida para esta sessao (nao gravada em disco)." -ForegroundColor Green
        } else {
            Write-Host "  Usando a identidade da sua sessao." -ForegroundColor Gray
        }
    }
    Write-Host ""
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
    Write-Host "  5) Reparar acesso  (compartilhamento C$/SMB e firewall)"
    Write-Host "  6) Provisionar     (baixa/atualiza PsExec + .msi na pasta)"
    Write-Host "  7) Remover         (desinstala o agente das maquinas)"
    Write-Host "  0) Sair"
    $op = Read-Host "`n  Escolha"
    switch ($op) {
        '1' { Invoke-Flow Inventory }
        '2' { Invoke-Flow Deploy }
        '3' { Invoke-Flow Reenroll }
        '4' { Invoke-Flow Reset }
        '5' { Invoke-Repair }
        '6' { Invoke-Flow Provision }
        '7' { Invoke-Uninstall }
        '0' { }
        default { Write-Host "  Opcao invalida." -ForegroundColor Red }
    }
    if ($op -ne '0') { Read-Host "`n  Pressione Enter para voltar ao menu" | Out-Null }
} while ($op -ne '0')

Write-Host "Ate mais." -ForegroundColor DarkCyan
