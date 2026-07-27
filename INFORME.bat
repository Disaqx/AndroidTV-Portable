@echo off
REM Recoge TODO el estado del Android TV en un fichero de texto en el
REM escritorio, para poder diagnosticar desde otro equipo.
REM EJECUTALO CON EL TV ABIERTO y con el mando conectado.
title Generar informe Android TV
echo.
echo   Recogiendo informacion... (ten el TV abierto y el mando conectado)
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\informe.ps1"
pause
