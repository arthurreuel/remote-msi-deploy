<#
  Harden-Acl.ps1 - restringe as permissoes desta pasta a Administradores + SYSTEM.

  Por que: os scripts aqui rodam como SYSTEM nas estacoes. Se um usuario nao-admin
  puder editar config.psd1 / scripts / token.txt, ele injeta codigo que roda como
  SYSTEM em todo o dominio. Esta ACL impede isso.

  Rode UMA vez, como Administrador, no servidor de operacao:
    powershell -ExecutionPolicy Bypass -File .\Harden-Acl.ps1
  (ou duplo-clique em Blindar.cmd)
#>
$root = $PSScriptRoot
Write-Host "Aplicando ACL restritiva (somente Administradores + SYSTEM) em:" -ForegroundColor Cyan
Write-Host "  $root`n"

# SIDs conhecidos (locale-independentes):
#   S-1-5-32-544 = Administradores | S-1-5-18 = SYSTEM
# /inheritance:r remove heranca; /grant:r substitui as permissoes existentes.
& icacls "$root" /inheritance:r /T /C /Q /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "OK - agora so Administradores e SYSTEM podem ler/gravar esta pasta." -ForegroundColor Green
    Write-Host "Confira com:  icacls `"$root`"" -ForegroundColor Gray
} else {
    Write-Host "icacls retornou $LASTEXITCODE. Rode como Administrador." -ForegroundColor Red
}
