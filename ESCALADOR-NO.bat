@echo off
REM MARCHA ATRAS: desactiva el reescalador y deja el TV como estaba
REM (pantalla completa normal, sin Magpie). Usalo si en la Legion Go
REM va lento, se calienta o empeora el audio.
title Desactivar reescalador IA
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\escalador.ps1" -Modo no
pause
