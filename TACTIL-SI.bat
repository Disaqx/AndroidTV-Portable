@echo off
REM Vuelve a activar la pantalla tactil (multi-touch).
title Activar tactil
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\tactil.ps1" -Modo si
pause
