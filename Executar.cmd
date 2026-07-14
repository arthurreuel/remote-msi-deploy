@echo off
REM Atalho de duplo-clique: abre o menu de fluxos como Administrador.
cd /d "%~dp0"
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0Menu.ps1\"'"
