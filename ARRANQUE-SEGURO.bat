@echo off
REM Vuelve al arranque en frio de siempre (~30 s, sin instantaneas).
title Arranque seguro
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\arranque.ps1" -Modo seguro
pause
