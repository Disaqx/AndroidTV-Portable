@echo off
title Instalar apps en Android TV
cd /d "%~dp0"
echo.
echo   Instalando las apps de la carpeta apps\ ...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\instalar-apps.ps1"
pause
