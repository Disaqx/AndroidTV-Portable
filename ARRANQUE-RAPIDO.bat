@echo off
REM Arranque rapido con instantanea. Deberia mejorar el audio del principio.
title Arranque rapido
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\arranque.ps1" -Modo rapido
pause
