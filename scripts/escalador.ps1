# Activa o desactiva el reescalador por IA (Magpie) para el Android TV.
#   -Modo si  -> el TV se abre a tamanio nativo y Magpie lo amplia
#   -Modo no  -> vuelve a pantalla completa normal, sin Magpie
# Cambia una sola linea de %USERPROFILE%\.android\tv.ini y cierra Magpie si toca.
param([ValidateSet('si', 'no')][string]$Modo = 'si')
$ErrorActionPreference = 'Stop'

$tvIni  = "$env:USERPROFILE\.android\tv.ini"
$magpie = "$env:USERPROFILE\.android\magpie\Magpie.exe"

# Leer el tv.ini actual (o empezar uno nuevo) conservando las demas lineas
$lineas = @()
if (Test-Path $tvIni) { $lineas = @(Get-Content $tvIni | Where-Object { $_ -notmatch '^\s*escalador\s*=' }) }
$lineas += "escalador=$Modo"
Set-Content -Path $tvIni -Value $lineas -Encoding ASCII

Write-Host ""
if ($Modo -eq 'si') {
  if (-not (Test-Path $magpie)) {
    Write-Host "  AVISO: no encuentro Magpie en $magpie" -ForegroundColor Yellow
    Write-Host "  El TV se abrira en pequenio y SIN ampliar. Ejecuta el instalador" -ForegroundColor Yellow
    Write-Host "  o pon ESCALADOR-NO para volver a pantalla completa normal." -ForegroundColor Yellow
  } else {
    Write-Host "  Reescalador por IA ACTIVADO." -ForegroundColor Green
    Write-Host "  Al abrir el TV se lanzara Magpie y ampliara la imagen." -ForegroundColor Green
  }
} else {
  Write-Host "  Reescalador DESACTIVADO. El TV vuelve a pantalla completa normal." -ForegroundColor Green
  Get-Process Magpie -ErrorAction SilentlyContinue | Stop-Process -Force
}
Write-Host ""
Write-Host "  Cierra el TV y vuelve a abrirlo para que el cambio tenga efecto." -ForegroundColor Cyan
Write-Host ("  (tv.ini: {0})" -f ((Get-Content $tvIni) -join '  |  ')) -ForegroundColor DarkGray
Write-Host ""
