@{
    # ---- Identidade do agente (ajuste para o SEU produto) --------------
    # Padrao do DisplayName no registro de Uninstall (para detectar instalacao).
    AgentDisplayName = '*Monitor Agent*'
    # Nome do servico Windows do agente.
    ServiceName      = 'MonitorAgent'
    # Chave de registro onde o agente guarda identidade/config.
    RegistryKey      = 'HKLM:\SOFTWARE\MonitorAgent'
    # Pasta de dados do agente (purgada no Reset).
    DataDir          = 'C:\ProgramData\MonitorAgent'
    # Arquivo de buffer local apagado no Re-enroll.
    BufferFile       = 'C:\ProgramData\MonitorAgent\buffer.db'
    # Propriedade publica do MSI que recebe o token de enrollment.
    TokenProperty    = 'TENANT_TOKEN'

    # ---- Instalador -----------------------------------------------------
    # Nome do .msi na raiz do repo (o arquivo em si NAO e versionado).
    MsiFileName      = 'Agent.msi'

    # ---- Execucao -------------------------------------------------------
    # Pasta de trabalho criada na maquina-alvo.
    WorkDir          = 'C:\Temp'
    # Nome alternativo do servico do PsExec (-r), evita o PSEXESVC preso.
    PsExecServiceName = 'pvdeploy'

    # ---- Alvos ----------------------------------------------------------
    # Lista inline OU aponte MachinesFile para um .txt (um host por linha).
    Machines     = @('WS-001','WS-002','WS-003')
    MachinesFile = ''   # ex.: 'machines.txt' (tem prioridade sobre Machines)
}
