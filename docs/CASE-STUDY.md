# Case Study — 12 estações, 1 dia, 4 causas-raiz diferentes

Registro (anonimizado) da operação real que originou este toolkit: colocar **12 estações de um domínio Windows** reportando em um painel de monitoramento, partindo de um cenário onde a maioria "parecia instalada" mas não aparecia no painel.

## Contexto

- Agente de monitoramento distribuído como `.msi` (WiX), que exige um **token de enrollment** passado na instalação (propriedade pública `TENANT_TOKEN`).
- WinRM **desabilitado** em todas as estações → toda execução remota via **PsExec** (SMB + Service Control Manager).
- Operação disparada de um servidor de gestão do domínio.

## Linha do tempo

### Rodada 1 — Deploy inicial: a surpresa do `1603`

Primeiro disparo nas 11 máquinas da lista original. Resultado: 3 instalações limpas com sucesso, 2 offline… e **5 falhas `1603`**.

O log verboso do msiexec (`/l*v`) revelou: *"A versão mais recente já está instalada"* + `WIX_DOWNGRADE_DETECTED`. As máquinas **já tinham o agente** — instalado por outra via (GPO) — e o instalador abortava por proteção de downgrade.

> **Lição 1:** `1603` não é um erro, é um sintoma. Sempre instale com `/l*v` e leia o log.
>
> **Lição 2:** a checagem "já instalado?" por **ProductCode não funciona** com WiX major upgrade (cada versão tem ProductCode novo). Detectar por **DisplayName** no registro de Uninstall.

### Rodada 2 — Reinstalar não resolve: a identidade órfã

As máquinas "já instaladas" não apareciam no painel. Hipótese inicial: reinstalar por cima com o token. Testado em 1 máquina: instalação OK (código 0)… e **continuou invisível no painel**.

Diagnóstico comparativo entre uma máquina saudável e uma quebrada (mesmo serviço rodando, mesmos arquivos, mesmo registro) revelou a única diferença: o **DeviceId**. A máquina quebrada tinha um id antigo (34); a saudável, um id recente (163). Conclusão:

- A chave de identidade do agente (`DeviceId`/`DeviceToken` em `HKLM\SOFTWARE\<Agent>`) **sobrevive à desinstalação do MSI**;
- O agente reinstalado **reutiliza** a identidade antiga;
- Esse device havia sido removido no servidor → o agente autenticava numa identidade morta e nunca se re-registrava.

> **Lição 3:** para agentes com enrollment, *instalado* e *registrado* são estados independentes. Reinstalar não re-registra.

### Rodada 3 — O fix de 3 linhas: re-enroll

Validado em 1 máquina antes do lote:

```powershell
Stop-Service <Agent> -Force
Remove-ItemProperty HKLM:\SOFTWARE\<Agent> -Name DeviceId, DeviceToken
Remove-Item C:\ProgramData\<Agent>\buffer.db
Start-Service <Agent>
```

DeviceId saltou de 34 → 164 e a máquina apareceu no painel em segundos. Rodado no lote: mais 4 máquinas recuperadas. Sem tocar no MSI.

> **Lição 4:** valide a correção em 1 máquina e **confirme no sistema de destino** (o painel), não apenas no indicador local, antes de aplicar em massa.

### Rodada 4 — Os teimosos: PSEXESVC preso e reset completo

Duas classes de problema restantes:

**a) PsExec falhando com** *"service marked for deletion"*: o serviço `PSEXESVC` ficou preso na máquina-alvo (handle aberto). Correção sem reboot: flag **`-r <nome>`**, que faz o PsExec operar com um serviço de nome alternativo.

**b) Máquinas que re-enrollavam mas não registravam** (DeviceId permanecia vazio): nesses casos o estado local estava corrompido além da identidade. Solução: **reset completo** — desinstalar todas as versões, **purgar a chave de registro inteira e o ProgramData**, reinstalar com token e diagnosticar a conectividade na sequência (HTTP + TCP 443 + TCP porta do websocket). As 4 máquinas restantes registraram com ids novos na primeira tentativa pós-reset.

> **Lição 5:** escale a agressividade gradualmente: *deploy → re-enroll → reset*. O reset destrói histórico local; use por último.
>
> **Lição 6:** ping **antes** de qualquer SMB. Timeout de SMB em máquina desligada trava o pipeline por minutos e pode derrubar a sessão do servidor de gestão.

## Resultado

| Fase | Máquinas resolvidas | Método |
|---|---|---|
| Deploy inicial | 3 | Instalação limpa com token |
| Re-enroll | 5 | Limpeza de identidade + restart do serviço |
| Reset completo | 4 | Uninstall + purge + reinstall + diagnóstico |
| **Total** | **12** | |

Cada execução deixou um CSV auditável (`resultado_*.csv`), permitindo reconstruir a linha do tempo inteira depois.

## Checklist de diagnóstico (ordem de custo)

1. `Get-AgentInventory.ps1` — o agente existe? serviço roda? DeviceId presente?
2. Painel — a máquina aparece? (DeviceId local ≠ registrado no servidor)
3. `Reenroll-Agent.ps1` — identidade órfã é a causa mais comum
4. Conectividade — HTTP ao servidor, TCP 443, TCP porta websocket (painel "oscilando offline" com agente saudável = suspeite da porta do websocket)
5. `Reset-Agent.ps1` — último recurso, com diagnóstico embutido
