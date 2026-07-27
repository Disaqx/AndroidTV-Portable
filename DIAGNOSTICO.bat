@echo off
title Diagnostico Android TV
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\diagnostico.ps1"
pause
