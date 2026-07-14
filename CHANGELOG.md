# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e [Versionamento Semântico](https://semver.org/lang/pt-BR/).

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

[1.0.0]: https://github.com/arthurreuel/remote-msi-deploy/releases/tag/v1.0.0
