@echo off
REM Gera um .zip portatil desta ferramenta (leve, pronto para copiar).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Empacotar.ps1"
pause
