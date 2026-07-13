# Remote MSI Deploy

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-Domain-0078D4?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

Toolkit em **PowerShell + PsExec** para instalar, re-registrar (re-enroll) e diagnosticar um agente de monitoramento (`.msi`) em massa nas estações de um domínio Windows — **sem depender de WinRM**, que costuma estar desabilitado em parques legados.

Nasceu de um caso real: dezenas de estações precisavam receber um agente de monitoramento, parte delas tinha o agente instalado mas **não aparecia no painel** (identidade órfã no servidor), e o WinRM estava desabilitado em todas. O toolkit resolve o ciclo completo: deploy → detecção de instalação existente → re-enroll → reset completo → diagnóstico de conectividade, sempre com relatório em CSV por execução.

## Por que PsExec e não WinRM/GPO?

| Método | Situação encontrada |
|---|---|
| `Invoke-Command` (WinRM) | Desabilitado nas estações; habilitar exigiria GPO + reinício do ciclo |
| GPO Software Installation | Instala apenas no boot/logon; sem feedback imediato; difícil segmentar máquinas avulsas |
| **PsExec (SMB + SCM)** | **Funciona onde `C$` funciona; execução como SYSTEM; código de saída capturável** |

## Estrutura esperada

Os scripts são **portáteis**: usam `$PSScriptRoot`, então basta clonar a pasta para qualquer servidor de gestão e rodar de lá.

```
deploy-folder/
├── Agent.msi              # instalador do agente (não versionado)
├── token.txt              # token de enrollment (não versionado — ver token.example.txt)
├── PSTools/
│   └── PsExec64.exe       # Sysinternals PsTools (não versionado)
├── scripts/
│   ├── Deploy-Agent.ps1           # instala onde falta (idempotente)
│   ├── Reenroll-Agent.ps1         # força novo registro no servidor
│   ├── Reset-Agent.ps1            # desinstala + purga estado + reinstala + diagnostica
│   └── Get-AgentInventory.ps1     # snapshot: DeviceId, serviço, versão (somente leitura)
└── resultado_*.csv        # relatórios gerados por execução (não versionados)
```

## Início rápido

```powershell
# 1. Coloque Agent.msi, token.txt e PSTools\ na raiz da pasta
# 2. Edite a lista $maquinas no topo do script desejado
# 3. Rode como administrador:
cd C:\deploy-folder
powershell -ExecutionPolicy Bypass -File .\scripts\Deploy-Agent.ps1
```

Cada execução imprime um resumo colorido por máquina e grava um `resultado_<operacao>_<timestamp>.csv` — o histórico de execuções fica auditável na própria pasta.

## Os quatro scripts

### 1. `Deploy-Agent.ps1` — instalar onde falta
Por máquina: **ping** (evita travar em host desligado) → acesso `C$` → detecta instalação existente **pelo DisplayName no registro de Uninstall** → copia o MSI → `msiexec /i ... TOKEN_PROPERTY="<token>" /qn` como SYSTEM. Máquinas que já têm o agente são puladas — é seguro re-executar quantas vezes quiser.

> **Por que detectar pelo DisplayName e não pelo ProductCode?** Instaladores WiX geram um ProductCode **novo a cada versão** (major upgrade). Checar o ProductCode do seu MSI não encontra a versão anterior instalada → o instalador aborta com `1603` por proteção de downgrade. A busca por nome funciona para qualquer versão.

### 2. `Reenroll-Agent.ps1` — consertar "instalado mas offline no painel"
O cenário mais traiçoeiro: o agente roda, mas o painel não mostra a máquina. Causa: a chave de identidade (`DeviceId`/`DeviceToken` em `HKLM\SOFTWARE\<Agent>`) **sobrevive à desinstalação do MSI**. O agente reinstalado reutiliza a identidade antiga — que foi removida/orfanada no servidor — e nunca se registra de novo.

O script força o re-registro **sem reinstalar nada**:

```
parar serviço → apagar DeviceId + DeviceToken + buffer local → iniciar serviço
```

O agente encontra o token de instalação (que permanece no registro), registra-se do zero e ganha um DeviceId novo. Validado em produção: identidades antigas (id 9, 34, 37, 72...) renovadas para ids ativos em segundos.

### 3. `Reset-Agent.ps1` — o martelo: reset completo + diagnóstico
Para máquinas que resistem ao re-enroll: desinstala **todas** as versões encontradas, **purga** a chave de registro inteira e o `ProgramData`, reinstala com o token e, ao final, roda um diagnóstico de conectividade (HTTP ao servidor, teste TCP na porta 443 e na porta do websocket). Cada máquina gera um `diag_<PC>.txt` e uma linha-resumo:

```
RESULT;ExitInstall=0;DeviceId=171;Servico=Running;HTTP=OK/200;P443=True;ReverbPort=False
```

### 4. `Get-AgentInventory.ps1` — fotografia sem efeitos colaterais
Somente leitura: DeviceId, status do serviço e presença do agente em cada máquina. Use antes e depois de qualquer operação em massa.

## Troubleshooting de campo (lições que custaram horas)

| Sintoma | Causa real | Correção |
|---|---|---|
| `1603` ao reinstalar | Versão igual/maior já instalada (proteção de downgrade do WiX) | Detectar por DisplayName e pular, ou usar o Reset |
| Instalado mas invisível no painel | `DeviceId` órfão sobrevive ao uninstall | `Reenroll-Agent.ps1` (não adianta reinstalar!) |
| PsExec: *"service marked for deletion"* | `PSEXESVC` preso no alvo (handle aberto) | Flag `-r <nome>` usa um serviço com outro nome |
| Script trava minutos em máquina desligada | Timeout longo do SMB | `Test-Connection` (ping) **antes** de tocar SMB |
| Registro ok, mas painel oscila offline | Porta do websocket bloqueada no firewall | Testar a porta com `Test-NetConnection`; liberar saída |
| MSI instala mas token não aplica | Propriedade passada com nome errado | Ler `SecureCustomProperties` do MSI (script na wiki) |

Detalhes e a investigação completa: [docs/CASE-STUDY.md](docs/CASE-STUDY.md).

## Segurança

- `token.txt`, MSI, binários da Sysinternals e CSVs de resultado estão no `.gitignore` — **nunca** versione tokens.
- Os scripts rodam como SYSTEM nas máquinas-alvo; execute-os apenas de um servidor de gestão controlado, com conta autorizada.
- Se precisar desabilitar firewall para diagnóstico, faça por janela mínima e **reative ao final** (os comandos de reativação estão no case study).

## Requisitos

- Windows PowerShell 5.1+ no servidor de gestão
- [Sysinternals PsTools](https://learn.microsoft.com/sysinternals/downloads/psexec) (PsExec64)
- Compartilhamentos administrativos (`C$`/`ADMIN$`) acessíveis nas máquinas-alvo
- Conta com privilégio administrativo nas estações

## Licença

[MIT](LICENSE)
