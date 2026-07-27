@echo off
title Instalador Android TV
cd /d "%~dp0"
echo.
echo   Instalando Android TV...  (no cierres esta ventana)
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1"
if errorlevel 1 (
  echo.
  echo   La instalacion termino con errores. Revisa los mensajes de arriba.
  pause
)
