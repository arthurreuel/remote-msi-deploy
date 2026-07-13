# ============================================================
#  Deploy-Agent.ps1
#  Instala o agente (.msi) nas maquinas da lista via PsExec.
#  - Idempotente: pula maquinas que ja tem o agente (deteccao
#    por DisplayName, funciona para qualquer versao/ProductCode).
#  - Ping antes de tocar SMB (nao trava em maquina desligada).
#  - Gera resultado_deploy_<timestamp>.csv na pasta raiz.
#
#  Estrutura esperada (pasta raiz = um nivel acima de \scripts):
#     Agent.msi | token.txt | PSTools\PsExec64.exe
#
#  Rodar como administrador:
#     powershell -ExecutionPolicy Bypass -File .\scripts\Deploy-Agent.ps1
# ============================================================

# --- CONFIGURACAO -----------------------------------------------
$maquinas = @(
    "WS-001","WS-002","WS-003"          # <- suas maquinas
)

$agentDisplayName = "*Monitor Agent*"   # padrao do DisplayName no registro Uninstall
$propToken        = "TENANT_TOKEN"      # propriedade publica do MSI que recebe o token
$pastaDestino     = "C:\Temp"           # pasta de trabalho na maquina-alvo
# ----------------------------------------------------------------

$raiz      = Split-Path $PSScriptRoot -Parent
$msiOrigem = Join-Path $raiz "Agent.msi"
$tokenArq  = Join-Path $raiz "token.txt"
$psexec    = Join-Path $raiz "PSTools\PsExec64.exe"

foreach ($req in $msiOrigem, $tokenArq, $psexec) {
    if (-not (Test-Path $req)) { Write-Host "Arquivo obrigatorio ausente: $req" -ForegroundColor Red; return }
}

$token   = (Get-Content $tokenArq -Raw).Trim()
$msiNome = Split-Path $msiOrigem -Leaf
if ([string]::IsNullOrWhiteSpace($token)) { Write-Host "Token vazio! Verifique token.txt" -ForegroundColor Red; return }
Write-Host "Token carregado ($($token.Length) caracteres)." -ForegroundColor Cyan

# Checagem remota "ja instalado?" por DisplayName -> exit 10 = sim, 20 = nao
$remotoCheck = @(
    '$keys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"'
    ('$app = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "' + $agentDisplayName + '" } | Select-Object -First 1')
    'if ($app) { exit 10 } else { exit 20 }'
)
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($remotoCheck -join "`n")))

$relatorio = foreach ($pc in $maquinas) {
    Write-Host "`n== $pc ==" -ForegroundColor Cyan

    if (-not (Test-Connection -ComputerName $pc -Count 1 -Quiet)) {
        Write-Host "  [OFFLINE] sem resposta de ping" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Codigo="OFFLINE"; Status="OFFLINE (sem ping)" }; continue
    }

    $unc = "\\$pc\$($pastaDestino.Replace(':','$'))"
    try {
        if (-not (Test-Path $unc)) { New-Item -ItemType Directory -Path $unc -Force -ErrorAction Stop | Out-Null }
    } catch {
        Write-Host "  [FALHA] Sem acesso a $unc (C$/SMB)" -ForegroundColor Red
        [PSCustomObject]@{ Maquina=$pc; Codigo="SMB"; Status="Sem acesso C$" }; continue
    }

    & $psexec "\\$pc" -r pvdeploy -s -nobanner -accepteula powershell -NoProfile -EncodedCommand $b64 2>$null | Out-Null
    if ($LASTEXITCODE -eq 10) {
        Write-Host "  JA INSTALADO - pulando." -ForegroundColor Yellow
        [PSCustomObject]@{ Maquina=$pc; Codigo=0; Status="JA INSTALADO (pulado)" }; continue
    }

    Copy-Item $msiOrigem "$unc\$msiNome" -Force
    Write-Host "  MSI copiado." -ForegroundColor Green

    & $psexec "\\$pc" -r pvdeploy -s -h -accepteula -nobanner msiexec /i "$pastaDestino\$msiNome" "$propToken=$token" /qn /norestart /l*v "$pastaDestino\install.log" 2>$null
    $code = $LASTEXITCODE

    $status = switch ($code) {
        0     { "SUCESSO" }
        3010  { "SUCESSO (requer reinicio)" }
        1603  { "FALHA 1603 - ver $pastaDestino\install.log na maquina" }
        1619  { "FALHA 1619 - MSI nao encontrado" }
        default { "FALHA (cod. $code)" }
    }
    $cor = if ($code -in 0,3010) { "Green" } else { "Red" }
    Write-Host "  Resultado: $status" -ForegroundColor $cor
    [PSCustomObject]@{ Maquina=$pc; Codigo=$code; Status=$status }
}

Write-Host "`n===== RESUMO =====" -ForegroundColor Cyan
$relatorio | Format-Table -AutoSize

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$csv   = Join-Path $raiz "resultado_deploy_$stamp.csv"
$relatorio | Select-Object @{n='DataHora';e={$stamp}}, Maquina, Codigo, Status |
    Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "`nRelatorio salvo em: $csv" -ForegroundColor Cyan

$instaladas = ($relatorio | Where-Object { $_.Status -like 'SUCESSO*' }).Count
$puladas    = ($relatorio | Where-Object { $_.Status -like 'JA INSTALADO*' }).Count
$pendentes  = ($relatorio | Where-Object { $_.Status -notlike 'SUCESSO*' -and $_.Status -notlike 'JA INSTALADO*' }).Count
Write-Host ("Instaladas agora: {0}  |  Ja tinham: {1}  |  Pendentes/Falhas: {2}" -f $instaladas, $puladas, $pendentes) -ForegroundColor Cyan
