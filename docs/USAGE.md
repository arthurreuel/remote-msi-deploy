# Guia de uso

## Setup (uma vez)

1. **Clone o repo** para o servidor de gestão (ou copie a pasta).
2. **Coloque na raiz:**
   - `Agent.msi` — o instalador do seu agente.
   - `token.txt` — o token de enrollment (copie de `token.example.txt`).
   - `PSTools\PsExec64.exe` — baixe o [Sysinternals PsTools](https://learn.microsoft.com/sysinternals/downloads/psexec).
3. **Crie o `config.psd1`:** copie `config.example.psd1` → `config.psd1` e ajuste os nomes do **seu** agente:
   - `AgentDisplayName`, `ServiceName`, `RegistryKey`, `DataDir`, `BufferFile`, `TokenProperty`.
4. **Defina as máquinas:** edite `Machines` no `config.psd1`, **ou** crie um `machines.txt` (um host por linha) e aponte `MachinesFile = 'machines.txt'`.

> `config.psd1`, `machines.txt`, `token.txt`, `*.msi`, `PSTools/` e as saídas (`resultado_*.csv`, `diag_*.txt`) estão no `.gitignore` — nunca sobem por acidente.

### Como descobrir os valores do seu agente

| Valor | Onde achar |
|---|---|
| `AgentDisplayName` | `Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* \| ? DisplayName -like '*<agente>*'` numa máquina que já tem |
| `TokenProperty` | Tabela `Property` do MSI: `SecureCustomProperties` (ver snippet abaixo) |
| `ServiceName` | `Get-Service \| ? DisplayName -like '*<agente>*'` |
| `RegistryKey` / `DataDir` | Inspecione `HKLM:\SOFTWARE\` e `C:\ProgramData\` numa máquina saudável |

Descobrir a propriedade do token no MSI:
```powershell
$i = New-Object -ComObject WindowsInstaller.Installer
$db = $i.OpenDatabase("Agent.msi", 0)
$v = $db.OpenView("SELECT Property, Value FROM Property"); $v.Execute()
while ($r = $v.Fetch()) { "{0} = {1}" -f $r.StringData(1), $r.StringData(2) }
# procure em SecureCustomProperties o nome da propriedade do token
```

## Fluxo de trabalho recomendado

```powershell
cd <pasta-do-repo>

# 1. Fotografe o estado atual
powershell -ExecutionPolicy Bypass -File .\scripts\Get-AgentInventory.ps1

# 2. Instale onde falta (idempotente — pula quem já tem)
powershell -ExecutionPolicy Bypass -File .\scripts\Deploy-Agent.ps1

# 3. Máquinas instaladas mas invisíveis no painel? Re-enroll
powershell -ExecutionPolicy Bypass -File .\scripts\Reenroll-Agent.ps1

# 4. As teimosas que resistem: reset completo + diagnóstico
powershell -ExecutionPolicy Bypass -File .\scripts\Reset-Agent.ps1
```

**Sempre confirme no painel de destino**, não só no DeviceId local. Cada execução grava um `resultado_*.csv` auditável na pasta **`Logs\`** (configurável em `LogDir`).

## Reparar acesso (pré-requisitos das estações)

Dois bloqueios recorrentes impedem a ferramenta de agir: **`C$`/SMB fechado**
(erro `Sem acesso C$`) e **firewall** atrapalhando. O fluxo **5) Reparar acesso**
(menu) trata os dois:

| Ação | O que faz | Quando usar |
|---|---|---|
| Habilitar compartilhamento | Liga "Arquivos e Impressoras" + "Descoberta de Rede" e o serviço `LanmanServer` | Padronizar/destravar `C$` em máquinas **alcançáveis** |
| Desativar firewall | Desliga os 3 perfis (temporário) | Diagnóstico (ex.: testar se o firewall local bloqueia o agente) |
| Reativar firewall | Religa os 3 perfis | Sempre, após o diagnóstico |

### O paradoxo do SMB (importante)

Se o `C$`/SMB **já está bloqueado**, o PsExec **não consegue entrar** para
consertar — `Repair-Access.ps1` vai falhar nessas. Para esses casos use
**`scripts/Repair-Access-Local.ps1`**, que roda **na própria máquina** e não
depende de PsExec:

- **Via GPO (recomendado para muitas máquinas):** Configuração do Computador →
  Políticas → Configurações do Windows → Scripts → **Inicialização** — aponte o
  `Repair-Access-Local.ps1`. Roda como SYSTEM no boot e abre o compartilhamento.
- **Localmente:** PowerShell como Administrador na estação:
  `powershell -ExecutionPolicy Bypass -File .\Repair-Access-Local.ps1`

Depois que ele rodar, o servidor de gestão volta a alcançar o `C$` e os demais
fluxos (Deploy/Re-enroll) passam a funcionar naquela máquina. Ele registra um
log em `C:\ProgramData\RemoteMsiDeploy\repair-access.log`.

## Dicas de campo

- **PsExec bloqueado como "arquivo da internet":** `Unblock-File .\PSTools\PsExec64.exe`.
- **`PSEXESVC marked for deletion`:** os scripts já usam `-r <nome>` (config `PsExecServiceName`) para contornar; se persistir, `sc.exe \\PC delete PSEXESVC`.
- **Testar em 1 máquina primeiro:** aponte `Machines = @('WS-001')` no config antes de rodar no lote.
- **Firewall para diagnóstico:** se desabilitar para testar, **reative** logo depois:
  ```powershell
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
  ```
