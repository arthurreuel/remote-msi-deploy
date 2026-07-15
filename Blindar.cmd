@echo off
REM Aplica a ACL restritiva (Administradores + SYSTEM) nesta pasta, como admin.
cd /d "%~dp0"
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0Harden-Acl.ps1\"'"
