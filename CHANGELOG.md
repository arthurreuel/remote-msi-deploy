# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.4.0] - 2026-07-14

### Adicionado
- **Auto-elevação do menu** (`Menu.ps1`): se não estiver como Administrador, o
  menu se reabre elevado (UAC) automaticamente — o PsExec precisa de admin para
  acessar `Admin$`/SCM das estações. Antes era só um aviso passivo.
- **Retry nas execuções remotas** (`Invoke-RemotePSWithRetry`): repete a
  chamada via PsExec até obter resposta, **variando o nome do serviço `-r`** a
  cada tentativa (dribla PSEXESVC preso), com espera entre elas. Aplicado ao
  fluxo **Reparar acesso**. Novas chaves: `RetryCount` e `RetryDelaySeconds`.

### Corrigido
- Mensagem de falha exibia `SMB/AdminTrue` (o `$?` do PowerShell era
  interpolado por engano) — corrigido em Reparar acesso e Re-enroll.

## [1.3.1] - 2026-07-14

### Alterado
- **Interface**: seção "Instalador (.msi)" reorganizada — **Origem (rede/SysVol)**
  marcada como recomendada e **Local** como **opcional (fallback)** para máquinas
  sem acesso à origem, com dicas explicativas. O campo local agora começa vazio.

### Corrigido
- **Máquinas na interface**: quebras de linha `\n` apareciam grudadas (a caixa
  do WinForms só renderiza `\r\n`) e podiam zerar a lista ao salvar. Normalizado
  na carga.
- Ao salvar com o instalador local vazio, o `MsiFileName` configurado é
  preservado (antes caía para 'Agent.msi').

## [1.3.0] - 2026-07-14

### Adicionado
- **Provisionamento de binários** (`scripts/Provision-Assets.ps1` +
  `Invoke-ProvisionAssets`): garante `PSTools\PsExec64.exe` (copiando de
  `PsExecSource` ou baixando do Sysinternals) e copia o **.msi mais recente**
  de `MsiSource` (pasta de rede/compartilhamento ou arquivo) para a pasta.
- Novas chaves de config: **`MsiSource`** e **`PsExecSource`**.
- **Interface**: campo "Origem do instalador (pasta)" e opção
  "Copiar PsExec e MSI ao salvar (provisionar)" — ao Salvar, os binários já
  são copiados para a pasta.
- Menu: opção **6) Provisionar**.

### Corrigido
- `Get-DeployConfig` tolera `config.psd1` mínimo sob StrictMode e ganhou
  `-SkipMachineCheck` (provisionar não exige lista de máquinas).

## [1.2.0] - 2026-07-14

### Adicionado
- **Fluxo "Reparar acesso"** para os bloqueios recorrentes de pré-requisito:
  - `scripts/Repair-Access.ps1` (remoto, via PsExec): habilita
    Compartilhamento de Arquivos e Impressoras + Descoberta de Rede
    (destrava `C$`/SMB), ou desativa/reativa o firewall dos 3 perfis.
  - `scripts/Repair-Access-Local.ps1` (local/GPO): mesma correção de
    compartilhamento rodando **na própria máquina**, para os casos em que
    o PsExec não alcança (SMB já bloqueado).
  - Usa identificadores de regra locale-independentes (Windows PT-BR/EN).
  - Opção **5) Reparar acesso** no `Menu.ps1`; `DisableFirewall` pede
    confirmação e lembra de reativar.

## [1.1.0] - 2026-07-10

### Adicionado
- **Interface gráfica de configuração** (`Configurar.ps1` / `Configurar.cmd`):
  formulário para apontar instalador, token, máquinas, domínio, método e os
  nomes do agente, gerando `config.psd1` + `machines.txt` + `token.txt` sem
  editar arquivo à mão.

## [1.0.0] - 2026-07-10

Primeira versão estável. Toolkit completo para gerenciar um agente de
monitoramento (`.msi`) em massa num domínio Windows sem WinRM.

### Adicionado
- **Menu de fluxos** (`Menu.ps1`) — lançador único (interativo ou `-Flow`)
  para Inventário, Deploy, Re-enroll e Reset.
- **Atalho de duplo-clique** (`Executar.cmd`) — abre o menu já elevado (UAC).
- **Configuração central** (`config.psd1`) — nomes do agente e lista de
  máquinas num só lugar; todos os scripts consomem.
- **Biblioteca compartilhada** (`lib/Common.ps1`) — loader de config e
  helpers (ping-first, execução via PsExec com `-r`, geração de CSV).
- **Fluxos:**
  - `Get-AgentInventory.ps1` — snapshot somente leitura.
  - `Deploy-Agent.ps1` — instala onde falta (idempotente, detecção por
    DisplayName).
  - `Reenroll-Agent.ps1` — renova a identidade órfã (conserta
    "instalado mas offline no painel") sem reinstalar.
  - `Reset-Agent.ps1` — purga estado + reinstala + diagnostica
    conectividade (HTTP / 443 / porta websocket).
- Lista de máquinas via `Machines` inline ou arquivo externo (`machines.txt`).
- Relatórios `resultado_*.csv` por execução; `diag_*.txt` no Reset.
- Documentação: `README.md`, `docs/USAGE.md`, `docs/CASE-STUDY.md`.
- `.gitignore` protege segredos (`token.txt`, `config.psd1`, `machines.txt`,
  `*.msi`, `PSTools/`) e saídas de execução.

[1.4.0]: https://github.com/arthurreuel/remote-msi-deploy/releases/tag/v1.4.0
[1.3.1]: https://github.com/arthurreuel/remote-msi-deploy/releases/tag/v1.3.1
[1.3.0]: https://github.com/arthurreuel/remote-msi-deploy/releases/tag/v1.3.0
[1.2.0]: https://github.com/arthurreuel/remote-msi-deploy/releases/tag/v1.2.0
[1.1.0]: https://github.com/arthurreuel/remote-msi-deploy/releases/tag/v1.1.0
[1.0.0]: https://github.com/arthurreuel/remote-msi-deploy/releases/tag/v1.0.0
