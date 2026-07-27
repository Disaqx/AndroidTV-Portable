# Activa o desactiva la pantalla tactil del Android TV.
#   -Modo si  -> multi-touch (se puede manejar con el dedo)
#   -Modo no  -> no-touch, como era originalmente (dispositivo de TV puro)
# Sirve para comprobar si el tactil es lo que rompe el mando: pon "no",
# prueba el mando, y si vuelve a funcionar ya sabemos la causa.
param([ValidateSet('si', 'no')][string]$Modo = 'si')
$ErrorActionPreference = 'Stop'

$cfg = "$env:USERPROFILE\.android\avd\AndroidTV.avd\config.ini"
if (-not (Test-Path $cfg)) { Write-Host "  No encuentro el AVD." -ForegroundColor Red; exit 1 }

$valor = if ($Modo -eq 'si') { 'multi-touch' } else { 'no-touch' }
$c = Get-Content $cfg
if ($c -match '^hw\.screen=') {
  $c = $c -replace '^hw\.screen=.*', "hw.screen=$valor"
} else {
  $c += "hw.screen=$valor"
}
Set-Content -Path $cfg -Value $c -Encoding ASCII

Write-Host ""
if ($Modo -eq 'si') {
  Write-Host "  Pantalla tactil ACTIVADA (multi-touch)." -ForegroundColor Green
} else {
  Write-Host "  Pantalla tactil DESACTIVADA (no-touch, como al principio)." -ForegroundColor Green
  Write-Host "  Si con esto el mando vuelve a funcionar, el tactil era la causa." -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  IMPORTANTE: cierra el TV del todo y vuelve a abrirlo." -ForegroundColor Yellow
Write-Host "  (este cambio solo se aplica al arrancar el emulador)" -ForegroundColor Yellow
Write-Host ""
Write-Host ("  config actual: " + ((Get-Content $cfg | Select-String '^hw\.screen=').Line)) -ForegroundColor DarkGray
Write-Host ""
