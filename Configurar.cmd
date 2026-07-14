@echo off
REM Abre a interface grafica de configuracao (gera config.psd1, machines.txt, token.txt).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configurar.ps1"
