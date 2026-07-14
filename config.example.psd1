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
    # Origem do .msi (opcional): pasta de rede/compartilhamento onde a versao
    # mais recente sempre fica. O provisionamento copia o .msi mais novo dela.
    # Pode ser uma PASTA (pega o .msi mais recente) ou um ARQUIVO especifico.
    #   ex.: '\\servidor\share\pasta-com-o-msi'
    MsiSource        = ''
    # Origem do PsExec (opcional): se vazio, o provisionamento baixa do
    # Sysinternals. Aponte um caminho local/rede para ambientes sem internet.
    #   ex.: '\\servidor\share\PsExec64.exe'
    PsExecSource     = ''

    # ---- Execucao -------------------------------------------------------
    # Pasta de trabalho criada na maquina-alvo.
    WorkDir          = 'C:\Temp'
    # Nome alternativo do servico do PsExec (-r), evita o PSEXESVC preso.
    PsExecServiceName = 'pvdeploy'
    # Retry das execucoes remotas (util para falhas transitorias / PSEXESVC preso).
    RetryCount        = 3     # tentativas por maquina
    RetryDelaySeconds = 4     # espera entre tentativas
    # Pasta dos relatorios (resultado_*.csv, diag_*.txt). Relativa a raiz ou
    # um caminho absoluto (ex.: 'D:\Logs\Deploy'). Mantem a raiz limpa.
    LogDir            = 'Logs'

    # ---- Alvos ----------------------------------------------------------
    # Lista inline OU aponte MachinesFile para um .txt (um host por linha).
    Machines     = @('WS-001','WS-002','WS-003')
    MachinesFile = ''   # ex.: 'machines.txt' (tem prioridade sobre Machines)
}
