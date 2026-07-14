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
    Write-Host "Empacotando (sem Logs / PSTools / *.msi)..." -ForegroundColor Cyan
    # /E todos os subdirs; /XD exclui pastas; /XF exclui arquivos
    robocopy $root $staging /E /XD Logs PSTools /XF *.msi *.log | Out-Null

    if (Test-Path $destZip) { Remove-Item $destZip -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $destZip -Force

    $mb = [math]::Round((Get-Item $destZip).Length / 1MB, 2)
    Write-Host "`nPacote portatil criado:" -ForegroundColor Green
    Write-Host "  $destZip  ($mb MB)" -ForegroundColor Cyan
    $temToken = Test-Path (Join-Path $root 'token.txt')
    if ($temToken) {
        Write-Host "  [!] O pacote INCLUI o token.txt - trate como confidencial." -ForegroundColor Yellow
    }
    Write-Host "`nNo destino (maquina admin do setor):" -ForegroundColor Gray
    Write-Host "  1) Descompacte a pasta." -ForegroundColor Gray
    Write-Host "  2) Rode Executar.cmd (ele provisiona PsExec + MSI na 1a vez)." -ForegroundColor Gray
} finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
