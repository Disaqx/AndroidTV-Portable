@echo off
REM Activa el reescalador por IA (Magpie). El TV se abrira a tamanio nativo y
REM Magpie lo ampliara a pantalla completa con su filtro neuronal.
title Activar reescalador IA
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\escalador.ps1" -Modo si
pause
