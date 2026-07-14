# ============================================================
#  lib\Common.ps1
#  Funcoes compartilhadas pelos scripts do toolkit.
#  Dot-source no inicio de cada script:
#     . (Join-Path $PSScriptRoot "..\lib\Common.ps1")
# ============================================================

Set-StrictMode -Version Latest

# Carrega config.psd1 da raiz do repo, resolve caminhos e a lista de maquinas.
function Get-DeployConfig {
    param([Parameter(Mandatory)][string]$Root, [switch]$SkipMachineCheck)

    $cfgPath = Join-Path $Root "config.psd1"
    if (-not (Test-Path $cfgPath)) {
        throw "config.psd1 nao encontrado. Copie config.example.psd1 para config.psd1 e ajuste os valores."
    }
    $cfg = Import-PowerShellDataFile -Path $cfgPath

    # Chaves opcionais recebem padrao se ausentes (evita erro sob StrictMode
    # em config.psd1 minimos, e permite rodar o reparo so com a lista de maquinas).
    $defaults = @{ MsiFileName = 'Agent.msi'; WorkDir = 'C:\Temp'; PsExecServiceName = 'pvdeploy'
                   MachinesFile = ''; MsiSource = ''; PsExecSource = '' }
    foreach ($k in $defaults.Keys) { if (-not $cfg.ContainsKey($k)) { $cfg[$k] = $defaults[$k] } }

    # Lista de maquinas: arquivo externo tem prioridade sobre a lista inline.
    if ($cfg.MachinesFile) {
        $mf = if ([IO.Path]::IsPathRooted($cfg.MachinesFile)) { $cfg.MachinesFile } else { Join-Path $Root $cfg.MachinesFile }
        if (-not (Test-Path $mf)) { throw "MachinesFile definido mas nao encontrado: $mf" }
        $cfg.Machines = @(Get-Content $mf | ForEach-Object { $_.Trim() } |
                        Where-Object { $_ -and -not $_.StartsWith('#') })
    }
    if (-not $cfg.ContainsKey('Machines')) { $cfg.Machines = @() }
    if (-not $SkipMachineCheck -and @($cfg.Machines).Count -eq 0) {
        throw "Nenhuma maquina definida (config.Machines ou MachinesFile)."
    }

    $cfg.Root       = $Root
    $cfg.MsiPath    = Join-Path $Root $cfg.MsiFileName
    $cfg.TokenPath  = Join-Path $Root "token.txt"
    $cfg.PsExecPath = Join-Path $Root "PSTools\PsExec64.exe"
    $cfg
}

# Valida pre-requisitos. $Need pode conter 'Msi' e/ou 'Token'.
function Assert-Prereq {
    param([Parameter(Mandatory)]$Cfg, [string[]]$Need = @())

    if (-not (Test-Path $Cfg.PsExecPath)) {
        throw "PsExec nao encontrado em $($Cfg.PsExecPath). Baixe o Sysinternals PsTools e coloque em PSTools\."
    }
    if ($Need -contains 'Msi' -and -not (Test-Path $Cfg.MsiPath)) {
        throw "MSI nao encontrado em $($Cfg.MsiPath)."
    }
    if ($Need -contains 'Token') {
        if (-not (Test-Path $Cfg.TokenPath)) { throw "token.txt nao encontrado em $($Cfg.TokenPath)." }
        $t = (Get-Content $Cfg.TokenPath -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { throw "token.txt esta vazio." }
    }
}

function Get-Token { param([Parameter(Mandatory)]$Cfg); (Get-Content $Cfg.TokenPath -Raw).Trim() }

# Ping rapido — evita travar no timeout de SMB de maquina desligada.
function Test-MachineOnline {
    param([Parameter(Mandatory)][string]$ComputerName)
    Test-Connection -ComputerName $ComputerName -Count 1 -Quiet
}

# Executa um bloco PowerShell (array de linhas) na maquina remota via PsExec.
# Retorna @{ Output = <linhas>; ExitCode = <int> }.
function Invoke-RemotePS {
    param(
        [Parameter(Mandatory)]$Cfg,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string[]]$Lines,
        [switch]$Elevated                       # -h (roda elevado); use para msiexec
    )
    $b64  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($Lines -join "`n")))
    $args = @("\\$ComputerName", "-r", $Cfg.PsExecServiceName, "-s")
    if ($Elevated) { $args += "-h" }
    $args += @("-nobanner", "-accepteula", "powershell", "-NoProfile", "-EncodedCommand", $b64)

    $out  = & $Cfg.PsExecPath @args 2>$null
    @{ Output = $out; ExitCode = $LASTEXITCODE }
}

# Garante C:\...\WorkDir na maquina via C$ e retorna o caminho UNC (ou $null se sem acesso).
function New-RemoteWorkDir {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$ComputerName)
    $unc = "\\$ComputerName\$($Cfg.WorkDir.Replace(':','$'))"
    try {
        if (-not (Test-Path $unc)) { New-Item -ItemType Directory -Path $unc -Force -ErrorAction Stop | Out-Null }
        return $unc
    } catch { return $null }
}

# Provisiona os binarios necessarios na pasta: PsExec64.exe e o .msi.
# - PsExec: se ausente, copia de PsExecSource (se definido) ou baixa do Sysinternals.
# - MSI: se MsiSource definido (pasta ou arquivo), copia o .msi mais recente
#        para a raiz com o nome MsiFileName.
# Retorna uma lista de mensagens de status.
function Invoke-ProvisionAssets {
    param([Parameter(Mandatory)]$Cfg)
    $msgs = New-Object System.Collections.Generic.List[string]

    # 1) PsExec ------------------------------------------------------------
    if (Test-Path $Cfg.PsExecPath) {
        $msgs.Add("PsExec: ja presente.")
    } elseif ($Cfg.PsExecSource -and (Test-Path $Cfg.PsExecSource)) {
        $dir = Split-Path $Cfg.PsExecPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        Copy-Item $Cfg.PsExecSource $Cfg.PsExecPath -Force
        Unblock-File $Cfg.PsExecPath -ErrorAction SilentlyContinue
        $msgs.Add("PsExec: copiado de $($Cfg.PsExecSource).")
    } else {
        try {
            $zip = Join-Path $env:TEMP "PSTools.zip"
            $ext = Join-Path $env:TEMP ("PSTools_" + [guid]::NewGuid().ToString('N').Substring(0,6))
            Invoke-WebRequest "https://download.sysinternals.com/files/PSTools.zip" -OutFile $zip -UseBasicParsing
            Expand-Archive $zip $ext -Force
            $dir = Split-Path $Cfg.PsExecPath -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
            Copy-Item (Join-Path $ext "PsExec64.exe") $Cfg.PsExecPath -Force
            Unblock-File $Cfg.PsExecPath -ErrorAction SilentlyContinue
            Remove-Item $zip,$ext -Recurse -Force -ErrorAction SilentlyContinue
            $msgs.Add("PsExec: baixado do Sysinternals.")
        } catch {
            $msgs.Add("PsExec: FALHA ao obter ($($_.Exception.Message)). Coloque PsExec64.exe em PSTools\ manualmente.")
        }
    }

    # 2) MSI ---------------------------------------------------------------
    if (-not $Cfg.MsiSource) {
        $msgs.Add("MSI: origem nao definida (MsiSource vazio); mantem o que ja houver na pasta.")
    } elseif (-not (Test-Path $Cfg.MsiSource)) {
        $msgs.Add("MSI: origem inacessivel -> $($Cfg.MsiSource)")
    } else {
        $item = Get-Item $Cfg.MsiSource
        $msiFile = if ($item.PSIsContainer) {
            Get-ChildItem $Cfg.MsiSource -Filter *.msi -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        } else { $item }
        if (-not $msiFile) {
            $msgs.Add("MSI: nenhum .msi encontrado em $($Cfg.MsiSource)")
        } else {
            Copy-Item $msiFile.FullName $Cfg.MsiPath -Force
            $mb = [math]::Round($msiFile.Length/1MB,1)
            $msgs.Add("MSI: copiado '$($msiFile.Name)' ($mb MB) -> $($Cfg.MsiFileName).")
        }
    }
    $msgs
}

# Salva um relatorio CSV com timestamp na raiz. Retorna o caminho.
function Save-Report {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$Prefix,
          [Parameter(Mandatory)][object[]]$Rows, [string]$Stamp)
    if (-not $Stamp) { $Stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss" }
    $csv = Join-Path $Cfg.Root "resultado_${Prefix}_$Stamp.csv"
    $Rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-Host "`nRelatorio salvo em: $csv" -ForegroundColor Cyan
    $csv
}
