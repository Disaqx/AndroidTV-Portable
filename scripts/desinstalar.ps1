# ============================================================================
#  Desinstalador de Android TV portatil
#
#  Quita SOLO lo que puso el instalador. Es importante: ~/.android NO es una
#  carpeta de este proyecto — ahi viven tambien las claves de adb
#  (adbkey, adbkey.pub) y el debug.keystore de Android Studio. Borrar la
#  carpeta entera te deja sin firmar tus propias apps y sin autorizacion en
#  los dispositivos que ya tenias emparejados.
#
#  Por eso se borra fichero a fichero, con lista explicita.
# ============================================================================
$ErrorActionPreference = 'Continue'

$sdk     = "$env:LOCALAPPDATA\Android\Sdk"
$avdHome = "$env:USERPROFILE\.android"
$desktop = [Environment]::GetFolderPath('Desktop')

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Desinstalador Android TV portatil" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Parar lo que este corriendo
# ---------------------------------------------------------------------------
Write-Host "[1/5] Cerrando el emulador y el puente del mando..." -ForegroundColor Yellow
$parados = 0
foreach ($n in @('emulator','emulator64-crash-service','qemu-system-x86_64','adb','Magpie','TouchHelper')) {
  Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_.Kill(); $parados++ } catch {}
  }
}
# El puente del mando corre como un powershell oculto lanzado por el .vbs
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'android-tv-(gamepad|launch)' } |
  ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; $parados++ } catch {}
  }
Write-Host "  Procesos cerrados: $parados" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Acceso directo
# ---------------------------------------------------------------------------
Write-Host "[2/5] Quitando el acceso directo del escritorio..." -ForegroundColor Yellow
if (Test-Path "$desktop\Android TV.lnk") {
  Remove-Item "$desktop\Android TV.lnk" -Force
  Write-Host "  Acceso directo eliminado." -ForegroundColor Green
} else {
  Write-Host "  No habia acceso directo." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. El AVD "AndroidTV"
# ---------------------------------------------------------------------------
Write-Host "[3/5] Quitando el dispositivo virtual AndroidTV..." -ForegroundColor Yellow
foreach ($p in @("$avdHome\avd\AndroidTV.avd", "$avdHome\avd\AndroidTV.ini")) {
  if (Test-Path $p) {
    Remove-Item $p -Recurse -Force
    Write-Host "  Eliminado: $p" -ForegroundColor Green
  }
}

# ---------------------------------------------------------------------------
# 4. Los ficheros que copio el instalador a ~/.android
#    LISTA EXPLICITA. Nunca borrar la carpeta entera.
# ---------------------------------------------------------------------------
Write-Host "[4/5] Quitando los scripts del televisor..." -ForegroundColor Yellow
$mios = @(
  'android-tv-launch.ps1', 'android-tv-launch.vbs', 'android-tv-gamepad.ps1',
  'arranque.ps1', 'calidad.ps1', 'diagnostico.ps1', 'escalador.ps1',
  'informe.ps1', 'tactil.ps1',
  'AndroidTV.ico', 'tv.ini', 'puente.log'
)
$n = 0
foreach ($f in $mios) {
  $p = Join-Path $avdHome $f
  if (Test-Path $p) { Remove-Item $p -Force; $n++ }
}
foreach ($d in @('magpie', 'backup-antes-escalador')) {
  $p = Join-Path $avdHome $d
  if (Test-Path $p) { Remove-Item $p -Recurse -Force; $n++ }
}
Write-Host "  Elementos eliminados: $n" -ForegroundColor Green
Write-Host "  NO se han tocado adbkey, debug.keystore ni el resto de tu" -ForegroundColor DarkGray
Write-Host "  configuracion de Android: no son de este proyecto." -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 5. El SDK: aparte y preguntando, porque puede ser compartido
# ---------------------------------------------------------------------------
Write-Host "[5/5] El SDK de Android..." -ForegroundColor Yellow
if (Test-Path $sdk) {
  $gb = 0
  try {
    $gb = [math]::Round((Get-ChildItem $sdk -Recurse -File -ErrorAction SilentlyContinue |
           Measure-Object Length -Sum).Sum / 1GB, 1)
  } catch {}
  # Si hay proyectos de Android Studio, el SDK casi seguro se comparte
  $studio = (Test-Path "$env:USERPROFILE\AndroidStudioProjects") -or
            (Test-Path "$env:APPDATA\Google\AndroidStudio*")
  Write-Host ""
  Write-Host "  Esta en: $sdk  ($gb GB)" -ForegroundColor Cyan
  if ($studio) {
    Write-Host ""
    Write-Host "  CUIDADO: se ha detectado Android Studio en este equipo." -ForegroundColor Red
    Write-Host "  Este SDK probablemente lo comparten tus otros proyectos." -ForegroundColor Red
    Write-Host "  Si lo borras, Android Studio dejara de compilar hasta que lo" -ForegroundColor Red
    Write-Host "  vuelvas a descargar." -ForegroundColor Red
  } else {
    Write-Host "  No se ha detectado Android Studio: probablemente solo lo usa" -ForegroundColor DarkGray
    Write-Host "  este proyecto y puedes borrarlo sin problema." -ForegroundColor DarkGray
  }
  Write-Host ""
  $r = Read-Host "  Borrar tambien el SDK y recuperar $gb GB? (S/N)"
  if ($r -match '^[sS]') {
    Write-Host "  Borrando el SDK (puede tardar un poco)..." -ForegroundColor Yellow
    Remove-Item $sdk -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $sdk) {
      Write-Host "  No se pudo borrar del todo. Cierra Android Studio y reintenta." -ForegroundColor Red
    } else {
      Write-Host "  SDK eliminado. $gb GB recuperados." -ForegroundColor Green
    }
  } else {
    Write-Host "  El SDK se queda donde esta." -ForegroundColor Green
  }
} else {
  Write-Host "  No hay SDK en $sdk" -ForegroundColor DarkGray
}

# Cache de descargas, si quedo alguna
$cache = "$env:TEMP\AndroidTV-sdk-cache"
if (Test-Path $cache) {
  Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "  Cache de descargas limpiada." -ForegroundColor Green
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host " Android TV desinstalado." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host " La carpeta del paquete no se toca: borrala tu si ya" -ForegroundColor DarkGray
Write-Host " no la quieres." -ForegroundColor DarkGray
Write-Host ""
