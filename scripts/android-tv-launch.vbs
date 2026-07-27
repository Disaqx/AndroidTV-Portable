' Lanza el Android TV en pantalla completa sin mostrar ventana de consola.
' Portatil: resuelve la ruta con %USERPROFILE%, funciona en cualquier PC/usuario.
Set sh = CreateObject("WScript.Shell")
ps1 = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.android\android-tv-launch.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False
