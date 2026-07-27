@echo off
REM Desactiva la pantalla tactil (deja el TV como estaba al principio).
REM Usalo para comprobar si el tactil es lo que rompe el mando.
title Desactivar tactil
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\tactil.ps1" -Modo no
pause
