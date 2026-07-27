@echo off
REM Mide la calidad real (resolucion y bitrate) del canal que estas viendo.
REM Reproduce algo 20-30 segundos ANTES de ejecutarlo.
title Medir calidad del video
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\calidad.ps1"
