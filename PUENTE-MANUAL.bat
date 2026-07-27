@echo off
REM Arranca el puente del mando A LA VISTA (normalmente corre oculto).
REM Usalo cuando el TV esta abierto pero el mando no responde: aqui se ve
REM el error si lo hay, en vez de fallar en silencio.
REM Cierra esta ventana para parar el puente.
title Puente del mando (visible)
echo.
echo   Arrancando el puente del mando a la vista.
echo   Si ves un error en rojo, esa es la causa: mandamelo.
echo   Deja esta ventana ABIERTA mientras usas el TV.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Continue'; & '%USERPROFILE%\.android\android-tv-gamepad.ps1'"
echo.
echo   El puente ha terminado.
pause
