<#
  Empacotar.ps1 - cria um .zip PORTATIL desta ferramenta para levar a outra
  maquina do setor. Fica leve: exclui o que e reconstruido no destino
  (Logs, PSTools, *.msi). Inclui config.psd1 e token.txt (ja pronto p/ uso).

  No destino: descompacte e rode Executar.cmd - o menu provisiona PsExec + MSI
  sozinho na primeira execucao.
#>
$root    = $PSScriptRoot
$stamp   = Get-Date -Format "yyyy-MM-dd_HH-mm"
$nome    = "RemoteMsiDeploy-portatil_$stamp.zip"
$destZip = Join-Path (Split-Path $root -Parent) $nome
$staging = Join-Path $env:TEMP ("pkg_" + [guid]::NewGuid().ToString('N').Substring(0,8))

New-Item -ItemType Directory -Force $staging | Out-Null
try {
    Write-Host "Empacotando (sem Logs / PSTools / *.msi / token)..." -ForegroundColor Cyan
    # /E todos os subdirs; /XD exclui pastas; /XF exclui arquivos.
    # O token NAO viaja: token.sec e atrelado a maquina (inutil noutra) e o
    # token.txt seria texto claro. Reinforme o token via Configurar no destino.
    robocopy $root $staging /E /XD Logs PSTools /XF *.msi *.log token.txt token.sec | Out-Null

    if (Test-Path $destZip) { Remove-Item $destZip -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $destZip -Force

    $mb = [math]::Round((Get-Item $destZip).Length / 1MB, 2)
    Write-Host "`nPacote portatil criado:" -ForegroundColor Green
    Write-Host "  $destZip  ($mb MB)" -ForegroundColor Cyan
    Write-Host "  (o token NAO vai no pacote - reinforme-o via Configurar no destino)" -ForegroundColor Gray
    Write-Host "`nNo destino (maquina admin do setor):" -ForegroundColor Gray
    Write-Host "  1) Descompacte a pasta." -ForegroundColor Gray
    Write-Host "  2) Rode Configurar.cmd e informe o token." -ForegroundColor Gray
    Write-Host "  3) Rode Executar.cmd (provisiona PsExec + MSI na 1a vez)." -ForegroundColor Gray
} finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
