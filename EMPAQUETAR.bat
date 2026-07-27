@echo off
title Empaquetar Android TV
cd /d "%~dp0"
echo.
echo   Empaquetando Android TV para compartir...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\empaquetar.ps1" %*
pause
