# Segurança

Esta ferramenta executa comandos **como SYSTEM** nas estações (via PsExec) a
partir de um servidor de operação, com uma conta **administradora do domínio**.
Isso é poderoso — trate a pasta e a conta como ativos privilegiados.

## Modelo de ameaça e mitigações

| Risco | Mitigação embutida |
|---|---|
| Adulteração de `config.psd1`/`scripts`/`token.txt` por não-admin → RCE como SYSTEM no domínio | **`Harden-Acl.ps1`** restringe a pasta a Administradores + SYSTEM. **`Assert-SafeConfig`** valida os valores. |
| PsExec adulterado/MITM (roda como SYSTEM em todas as estações) | **Verificação Authenticode**: só executa com PsExec **assinado pela Microsoft** (`Assert-PsExecTrusted`, checado a cada fluxo e no provisionamento). |
| Injeção via nome de máquina ou valor de config nos scripts remotos | **`Assert-SafeConfig`**: hostnames restritos a `[A-Za-z0-9._-]`; campos rejeitam aspas/backtick/`$(`/quebra de linha. Token idem. |
| Token em texto claro no servidor | O token é guardado em **`token.sec` cifrado com DPAPI (escopo de máquina)** — sem texto claro no disco. O `token.txt` legado é migrado e apagado automaticamente. |
| Token em texto claro no `install.log` das estações | Deploy/Reset **apagam o MSI e o `install.log`** de `C:\Temp` da estação em caso de sucesso. |
| Segredos no pacote portátil | O `.zip` **não inclui** o token: o `token.sec` é atrelado à máquina (inútil noutra) e não viaja; reinforme via `Configurar` no destino. |
| Firewall desativado esquecido ligado | `Reparar acesso` pede confirmação e lembra de reativar. |

## Checklist de blindagem (fazer no servidor)

1. **Coloque a pasta num local controlado** (ex.: `C:\Ferramentas\...`), não numa pasta compartilhada/gravável por todos.
2. **Rode a blindagem de ACL** uma vez, como admin:
   `Blindar.cmd` (ou `powershell -File .\Harden-Acl.ps1`) → só Administradores + SYSTEM podem ler/gravar.
3. **Mantenha o PsExec autêntico**: use o **6) Provisionar** (baixa do Sysinternals e valida a assinatura). A ferramenta se recusa a rodar com um PsExec não assinado pela Microsoft.
4. **Token**: informado pela interface `Configurar` e guardado cifrado em `token.sec` (DPAPI, escopo de máquina). Não há texto claro no disco, e o token não viaja no pacote portátil — reinforme-o em cada servidor.
5. **Execute sempre elevado**: o menu se auto-eleva (UAC); use a conta de operação, não uma conta de uso diário.

## O que NÃO é responsabilidade desta ferramenta

- O agente instalado grava o `InstallToken` no registro de cada estação (design do produto). Isso é inerente ao agente, não à ferramenta.
- A confiança no MSI vem do **domínio** (ele fica no SysVol, controlado pelos DCs); o MSI em si não é assinado.

## Reportar um problema

Abra uma *issue* no repositório descrevendo o cenário (sem incluir segredos reais).
