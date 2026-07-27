@echo off
title Desinstalador Android TV
cd /d "%~dp0"
echo.
echo   Desinstalando Android TV...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\desinstalar.ps1"
if errorlevel 1 (
  echo.
  echo   La desinstalacion termino con errores. Revisa los mensajes de arriba.
)
pause
