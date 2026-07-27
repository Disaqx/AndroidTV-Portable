@echo off
REM Reaplica scripts + resolucion SIN reinstalar el SDK ni tocar las apps.
REM Usalo en un equipo donde el Android TV ya estaba instalado.
title Actualizar Android TV
cd /d "%~dp0"
echo.
echo   Actualizando scripts y resolucion (no se reinstala nada mas)...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1" -SoloScripts
pause
