# ============================================================================
#  Instala en el TV los .apk que haya en la carpeta apps\
#
#  Existe porque anadir una app despues de instalar no tenia forma de hacerse:
#  INSTALAR.bat solo instala apps en una instalacion completa, y ACTUALIZAR.bat
#  usa -SoloScripts, que se salta ese paso a proposito. Dejar el .apk en apps\
#  y reiniciar el TV no hacia nada.
#
#  Sirve con el TV abierto o cerrado: si no hay emulador, lo arranca.
# ============================================================================
$ErrorActionPreference = 'Continue'

$pkg     = Split-Path $PSScriptRoot -Parent
$sdk     = "$env:LOCALAPPDATA\Android\Sdk"
$adb     = "$sdk\platform-tools\adb.exe"
$emu     = "$sdk\emulator\emulator.exe"
$avdHome = "$env:USERPROFILE\.android"
$avdDir  = "$avdHome\avd\AndroidTV.avd"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Instalar apps en Android TV" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $adb)) {
  Write-Host "  No encuentro adb. Ejecuta primero INSTALAR.bat." -ForegroundColor Red
  exit 1
}

# --- Que hay para instalar -------------------------------------------------
$apks = @(Get-ChildItem "$pkg\apps\*.apk" -ErrorAction SilentlyContinue)
if ($apks.Count -eq 0) {
  Write-Host "  La carpeta apps\ no tiene ningun .apk." -ForegroundColor Yellow
  Write-Host "  Deja ahi los que quieras instalar y vuelve a ejecutar esto." -ForegroundColor Yellow
  exit 0
}
Write-Host "  Encontradas $($apks.Count) app(s):" -ForegroundColor Green
foreach ($a in $apks) { Write-Host ("    {0} ({1:N1} MB)" -f $a.Name, ($a.Length/1MB)) -ForegroundColor Gray }
Write-Host ""

# --- Conseguir un emulador -------------------------------------------------
& $adb start-server 2>$null | Out-Null

function Get-Serial {
  $l = (& $adb devices 2>$null | Select-String '^emulator-\d+\s+device')
  if ($l) { return ($l -split '\s+')[0] }
  return ''
}

$serial = Get-Serial
if ($serial) {
  Write-Host "  El TV ya esta abierto ($serial)." -ForegroundColor Green
} else {
  Write-Host "  El TV no esta abierto, arrancandolo..." -ForegroundColor Yellow

  # Mismas precauciones que el instalador: cerrojos huerfanos de un cierre
  # brusco, datos de fallo que sacan un dialogo modal, y el modo de GPU que
  # este equipo necesite.
  foreach ($lock in @('hardware-qemu.ini.lock', 'multiinstance.lock')) {
    Remove-Item (Join-Path $avdDir $lock) -Recurse -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -Recurse -Force "$env:TEMP\AndroidEmulator" -ErrorAction SilentlyContinue

  $gpu = ''
  $tvIni = "$avdHome\tv.ini"
  if (Test-Path $tvIni) {
    $mg = (Get-Content $tvIni | Select-String '^\s*gpu\s*=\s*(\S+)')
    if ($mg) { $gpu = $mg.Matches[0].Groups[1].Value }
  }

  $a = @('-avd','AndroidTV','-no-snapshot','-no-metrics','-crash-report-mode','disabled')
  if ($gpu) { $a += @('-gpu', $gpu) }
  Start-Process $emu -ArgumentList $a

  Write-Host "  Esperando al emulador" -NoNewline -ForegroundColor DarkGray
  $lim = (Get-Date).AddSeconds(300)
  do {
    Start-Sleep -Seconds 3
    Write-Host "." -NoNewline -ForegroundColor DarkGray
    $serial = Get-Serial
  } until ($serial -or ((Get-Date) -gt $lim))
  Write-Host ""

  if (-not $serial) {
    Write-Host "  El emulador no arranco. Ejecuta DIAGNOSTICO.bat." -ForegroundColor Red
    exit 1
  }
}

# Android puede estar aun arrancando aunque adb ya lo vea
Write-Host "  Esperando a que Android termine de arrancar" -NoNewline -ForegroundColor DarkGray
$lim = (Get-Date).AddSeconds(180)
do {
  Start-Sleep -Seconds 3
  Write-Host "." -NoNewline -ForegroundColor DarkGray
  $boot = & $adb -s $serial shell getprop sys.boot_completed 2>$null
} until (($boot -match '1') -or ((Get-Date) -gt $lim))
Write-Host ""

if (-not ($boot -match '1')) {
  Write-Host "  Android no termino de arrancar a tiempo." -ForegroundColor Red
  exit 1
}

# --- Instalar --------------------------------------------------------------
Write-Host ""
$ok = 0; $fallos = @()

# -r reinstala conservando datos; -g concede los permisos de una vez, que en un
# TV sin teclado comodo es la diferencia entre usable y no usable.
foreach ($a in $apks) {
  Write-Host ("  Instalando {0}..." -f $a.Name) -NoNewline
  $salida = (& $adb -s $serial install -r -g $a.FullName 2>&1) -join ' '
  if ($salida -match 'Success') {
    Write-Host "  OK" -ForegroundColor Green
    $ok++
  } else {
    Write-Host "  FALLO" -ForegroundColor Red
    $fallos += @{ Nombre = $a.Name; Salida = $salida }
  }
}

# --- Conjuntos de splits ---------------------------------------------------
# Una app descargada de Play suele venir partida en varios .apk (base +
# configuracion). Instalarlos sueltos falla con MISSING_SPLIT. Si se meten
# todos en una SUBCARPETA de apps\, se instalan juntos con install-multiple.
$grupos = @(Get-ChildItem "$pkg\apps" -Directory -ErrorAction SilentlyContinue)
foreach ($g in $grupos) {
  $partes = @(Get-ChildItem "$($g.FullName)\*.apk" -ErrorAction SilentlyContinue)
  if ($partes.Count -eq 0) { continue }
  Write-Host ("  Instalando {0} ({1} partes)..." -f $g.Name, $partes.Count) -NoNewline
  $rutas = $partes | ForEach-Object { $_.FullName }
  $salida = (& $adb -s $serial install-multiple -r -g @rutas 2>&1) -join ' '
  if ($salida -match 'Success') {
    Write-Host "  OK" -ForegroundColor Green
    $ok++
  } else {
    Write-Host "  FALLO" -ForegroundColor Red
    $fallos += @{ Nombre = $g.Name; Salida = $salida }
  }
}

$total = $apks.Count + @($grupos | Where-Object { (Get-ChildItem "$($_.FullName)\*.apk" -ErrorAction SilentlyContinue) }).Count

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host " $ok de $total app(s) instaladas." -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

if ($fallos) {
  Write-Host ""
  foreach ($f in $fallos) {
    Write-Host "  $($f.Nombre)" -ForegroundColor Red
    # Se traduce el error de adb: a secas no le dice nada a nadie.
    $s = $f.Salida
    if ($s -match 'MISSING_SPLIT') {
      Write-Host "    Es un APK partido (App Bundle): le faltan sus otras piezas." -ForegroundColor Yellow
      Write-Host "    Consigue la version UNIVERSAL del apk, o mete todas las" -ForegroundColor Yellow
      Write-Host "    partes juntas en una subcarpeta dentro de apps\ y repite." -ForegroundColor Yellow
    }
    elseif ($s -match 'NO_MATCHING_ABIS') {
      Write-Host "    El apk es solo para ARM y esta imagen es x86." -ForegroundColor Yellow
      Write-Host "    Busca una version universal o x86." -ForegroundColor Yellow
    }
    elseif ($s -match 'ALREADY_EXISTS|VERSION_DOWNGRADE') {
      Write-Host "    Ya hay una version igual o mas nueva instalada." -ForegroundColor Yellow
    }
    elseif ($s -match 'INSUFFICIENT_STORAGE') {
      Write-Host "    No cabe: el TV se quedo sin espacio." -ForegroundColor Yellow
    }
    elseif ($s -match 'INVALID_APK|Invalid file') {
      Write-Host "    El fichero no es un apk valido (descarga incompleta?)." -ForegroundColor Yellow
    }
    else {
      Write-Host "    $s" -ForegroundColor Gray
    }
    Write-Host ""
  }
}
Write-Host ""
Write-Host " Las apps aparecen en la fila de aplicaciones del TV." -ForegroundColor DarkGray
Write-Host ""
