# ============================================================================
#  Instalador "Android TV" portatil  -  PAQUETE TODO INCLUIDO
#  Deja en este PC el mismo televisor Android que en el PC original:
#  emulador a PANTALLA COMPLETA (detecta la resolucion real) + puente de mando
#  + acceso directo en el escritorio.
#
#  El SDK de Android (emulador + platform-tools + imagen de TV) viene incluido
#  en sdk.7z - NO necesitas instalar Android Studio, Java ni tener internet.
#
#  USO:  doble clic en  INSTALAR.bat
#        (para actualizar scripts/resolucion sin reinstalar: ACTUALIZAR.bat)
#
#  REQUISITO UNICO: la virtualizacion debe estar activada en la BIOS
#  y el "Windows Hypervisor Platform" activado en Caracteristicas de Windows.
# ============================================================================
param(
  # Reaplica scripts + resolucion en un equipo donde ya estaba instalado.
  # No extrae el SDK, no arranca el emulador y no reinstala las apps.
  [switch]$SoloScripts
)
$ErrorActionPreference = 'Stop'
$pkg = $PSScriptRoot
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
if ($SoloScripts) {
  Write-Host "  Android TV - actualizar scripts" -ForegroundColor Cyan
} else {
  Write-Host "  Instalador Android TV portatil" -ForegroundColor Cyan
  Write-Host "  (paquete todo incluido)" -ForegroundColor Cyan
}
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# --- Rutas ---
$sdk     = "$env:LOCALAPPDATA\Android\Sdk"
$adb     = "$sdk\platform-tools\adb.exe"
$emu     = "$sdk\emulator\emulator.exe"
$avdHome = "$env:USERPROFILE\.android"
$sysDir  = "$sdk\system-images\android-36\android-tv\x86"
$sdkArchive = "$pkg\sdk.7z"
$7z      = "$pkg\tools\7z.exe"

# ---------------------------------------------------------------------------
#  DESCARGA DEL SDK DESDE LOS REPOSITORIOS PUBLICOS DE GOOGLE
#
#  Se usa cuando el paquete NO trae sdk.7z (por ejemplo al clonar el repo de
#  GitHub, donde ese fichero no cabe: pesa 996 MB y el limite son 100 MB).
#
#  No necesita token, ni Java, ni Android Studio, ni sdkmanager: se leen los
#  manifiestos XML publicos de Google y se bajan los .zip directamente.
#
#  IMPORTANTE: se filtra por canal ESTABLE (channel-0). Coger "la revision mas
#  alta" a secas devuelve builds de los canales dev/canary.
# ---------------------------------------------------------------------------
$RepoBase   = "https://dl.google.com/android/repository/"
$SysImgBase = "${RepoBase}sys-img/android-tv/"

function Get-PaqueteEstable {
  # Devuelve @{ Url; Sha1; Size } del archivo windows del canal estable.
  param([xml]$Xml, [string]$Path, [string]$UrlBase)
  $mejor = $null; $mejorRev = -1
  foreach ($pkg in $Xml.SelectNodes("//remotePackage")) {
    if ($pkg.path -ne $Path) { continue }
    $canal = $pkg.SelectSingleNode("channelRef")
    if (-not $canal -or $canal.ref -ne "channel-0") { continue }   # solo estable
    $r = $pkg.SelectSingleNode("revision")
    $rev = 0
    if ($r) {
      foreach ($c in @("major","minor","micro")) {
        $n = $r.SelectSingleNode($c)
        $val = 0; if ($n) { $val = [int]$n.InnerText }
        $rev = $rev * 1000 + $val
      }
    }
    foreach ($a in $pkg.SelectNodes(".//archive")) {
      $ho = $a.SelectSingleNode("host-os")
      # las imagenes de sistema no declaran host-os: valen para cualquiera
      if ($ho -and $ho.InnerText -ne "windows") { continue }
      if ($rev -gt $mejorRev) {
        $mejorRev = $rev
        $c = $a.SelectSingleNode("complete")
        $mejor = @{
          Url  = $UrlBase + $c.SelectSingleNode("url").InnerText
          Sha1 = $c.SelectSingleNode("checksum").InnerText
          Size = [long]$c.SelectSingleNode("size").InnerText
        }
      }
      break
    }
  }
  return $mejor
}

function Get-Componente {
  # Descarga (reanudable), verifica SHA1 y extrae. Reutiliza el zip si ya es valido.
  param([hashtable]$Info, [string]$Destino, [string]$Nombre, [string]$Cache)

  $zip = Join-Path $Cache (Split-Path $Info.Url -Leaf)
  $mb  = [math]::Round($Info.Size / 1MB)

  $valido = $false
  if (Test-Path $zip) {
    Write-Host "      ya descargado, verificando..." -ForegroundColor DarkGray
    if ((Get-FileHash $zip -Algorithm SHA1).Hash -eq $Info.Sha1.ToUpper()) { $valido = $true }
    else { Remove-Item $zip -Force }
  }

  if (-not $valido) {
    Write-Host "      bajando $Nombre ($mb MB)..." -ForegroundColor Yellow
    $ok = $false
    try {
      # BITS: reanudable y con progreso real. Es lo mejor en Windows.
      Import-Module BitsTransfer -ErrorAction Stop
      Start-BitsTransfer -Source $Info.Url -Destination $zip -DisplayName $Nombre -ErrorAction Stop
      $ok = $true
    } catch {
      Write-Host "      BITS no disponible, usando descarga directa..." -ForegroundColor DarkGray
      try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("user-agent","AndroidTV-Portable")
        $wc.DownloadFile($Info.Url, $zip)
        $ok = $true
      } catch {
        Write-Host "      ERROR bajando ${Nombre}: $_" -ForegroundColor Red
      }
    }
    if (-not $ok) { return $false }

    if ((Get-FileHash $zip -Algorithm SHA1).Hash -ne $Info.Sha1.ToUpper()) {
      Write-Host "      ERROR: el SHA1 de $Nombre no coincide. Descarga corrupta." -ForegroundColor Red
      Remove-Item $zip -Force -ErrorAction SilentlyContinue
      return $false
    }
  }

  Write-Host "      extrayendo $Nombre..." -ForegroundColor Yellow
  New-Item -ItemType Directory -Force -Path $Destino | Out-Null
  if (Test-Path $7z) {
    & $7z x $zip -o"$Destino" -y | Out-Null
  } else {
    Expand-Archive -Path $zip -DestinationPath $Destino -Force
  }
  return $true
}

function Install-SdkDesdeGoogle {
  Write-Host "  El paquete no trae sdk.7z: se bajara el SDK de Google (~1,3 GB)." -ForegroundColor Yellow
  Write-Host "  Solo pasa la primera vez. Con 50 Mbps es cosa de 1-2 minutos;" -ForegroundColor DarkGray
  Write-Host "  con 10 Mbps puede irse a 20-25. Se puede reanudar si se corta." -ForegroundColor DarkGray
  Write-Host ""

  # Se descargan 1,3 GB pero al extraer ocupan 9,3 GB (la imagen de sistema
  # sola son 8,3 GB). Mas los zips en la cache. Se comprueba ANTES de empezar
  # para no reventar a mitad de la extraccion con el disco lleno.
  $NECESARIO_GB = 12
  try {
    $unidad = (Get-Item $sdk -ErrorAction SilentlyContinue)
    $letra = if ($unidad) { $unidad.PSDrive.Name } else { (Split-Path $sdk -Qualifier).TrimEnd(':') }
    $libre = (Get-PSDrive $letra -ErrorAction Stop).Free / 1GB
    Write-Host ("  Espacio libre en {0}: {1:N1} GB (hacen falta ~{2} GB)" -f $letra, $libre, $NECESARIO_GB) -ForegroundColor DarkGray
    if ($libre -lt $NECESARIO_GB) {
      Write-Host ""
      Write-Host "  AVISO: puede que no haya sitio suficiente." -ForegroundColor Red
      Write-Host "  El SDK descargado son ~1,3 GB, pero extraido ocupa ~9,3 GB." -ForegroundColor Red
      Write-Host ""
      $r = Read-Host "  Continuar de todos modos? (S/N)"
      if ($r -notmatch '^[sS]') { return $false }
    }
  } catch {
    Write-Host "  (no se pudo comprobar el espacio libre, se continua)" -ForegroundColor DarkGray
  }
  Write-Host ""

  $cache = "$env:TEMP\AndroidTV-sdk-cache"
  New-Item -ItemType Directory -Force -Path $cache | Out-Null

  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "      leyendo manifiestos de Google..." -ForegroundColor DarkGray
    $xmlRepo = [xml](New-Object System.Net.WebClient).DownloadString("${RepoBase}repository2-3.xml")
    $xmlSys  = [xml](New-Object System.Net.WebClient).DownloadString("${SysImgBase}sys-img2-3.xml")
  } catch {
    Write-Host "  ERROR: no se pudieron leer los manifiestos de Google: $_" -ForegroundColor Red
    Write-Host "  Comprueba tu conexion a internet." -ForegroundColor Red
    return $false
  }

  $comps = @(
    @{ Info = (Get-PaqueteEstable $xmlRepo "platform-tools" $RepoBase)
       Dest = $sdk; Nombre = "platform-tools" },
    @{ Info = (Get-PaqueteEstable $xmlRepo "emulator" $RepoBase)
       Dest = $sdk; Nombre = "emulator" },
    @{ Info = (Get-PaqueteEstable $xmlSys "system-images;android-36;android-tv;x86" $SysImgBase)
       Dest = "$sdk\system-images\android-36\android-tv"; Nombre = "imagen de Android TV" }
  )

  $i = 0
  foreach ($c in $comps) {
    $i++
    if (-not $c.Info) {
      Write-Host "  ERROR: no se encontro '$($c.Nombre)' en el manifiesto de Google." -ForegroundColor Red
      return $false
    }
    Write-Host "    ($i/3) $($c.Nombre)" -ForegroundColor Cyan
    if (-not (Get-Componente $c.Info $c.Dest $c.Nombre $cache)) { return $false }
  }

  Write-Host "  SDK descargado e instalado." -ForegroundColor Green
  return $true
}

# ---------------------------------------------------------------------------
# 0. Verificar WHPX (Windows Hypervisor Platform)
# ---------------------------------------------------------------------------
if (-not $SoloScripts) {
  Write-Host "[0/5] Verificando aceleracion por hardware (WHPX)..." -ForegroundColor Yellow
  $whpx = (Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -ErrorAction SilentlyContinue)
  if ($whpx -and $whpx.State -eq 'Enabled') {
    Write-Host "  WHPX activado." -ForegroundColor Green
  } else {
    Write-Host "  WHPX NO esta activado. Intentando activarlo (requiere permisos de admin)..." -ForegroundColor Yellow
    try {
      $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
      if (-not $isAdmin) {
        Write-Host "  Este script no tiene permisos de administrador." -ForegroundColor Red
        Write-Host "  Para activar WHPX: clic derecho en INSTALAR.bat -> 'Ejecutar como administrador'," -ForegroundColor Red
        Write-Host "  o activalo a mano en:" -ForegroundColor Red
        Write-Host "    Panel de control -> Programas -> Activar o desactivar caracteristicas de Windows" -ForegroundColor Red
        Write-Host "    -> marca 'Plataforma de hipervisor de Windows' y reinicia." -ForegroundColor Red
        Write-Host ""
        $resp = Read-Host "Quieres continuar de todos modos? (S/N)"
        if ($resp -notmatch '^[sS]') { exit 1 }
      } else {
        Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -NoRestart -ErrorAction Stop | Out-Null
        Write-Host "  WHPX activado. NECESITARAS REINICIAR antes de usar el emulador." -ForegroundColor Yellow
      }
    } catch {
      Write-Host "  No se pudo activar WHPX automaticamente: $_" -ForegroundColor Red
      Write-Host "  Activalo manualmente desde Caracteristicas de Windows y reinicia." -ForegroundColor Red
      $resp = Read-Host "Quieres continuar de todos modos? (S/N)"
      if ($resp -notmatch '^[sS]') { exit 1 }
    }
  }

  # -------------------------------------------------------------------------
  # 1. Extraer el SDK incluido (sdk.7z) si falta algo
  # -------------------------------------------------------------------------
  #  Cascada, de mas rapido a mas lento. En los tres casos basta un solo clic:
  #    1. El SDK ya esta instalado           -> no hace nada
  #    2. El paquete trae sdk.7z             -> lo extrae (instalacion sin internet)
  #    3. No hay sdk.7z                      -> lo baja de Google (repo clonado)
  $needExtract = (-not (Test-Path $emu)) -or (-not (Test-Path $adb)) -or (-not (Test-Path $sysDir))
  if (-not $needExtract) {
    Write-Host "[1/5] SDK ya presente, omitiendo instalacion." -ForegroundColor Green
  }
  elseif (Test-Path $sdkArchive) {
    if (-not (Test-Path $7z)) {
      Write-Host "ERROR: No se encuentra tools\7z.exe en el paquete." -ForegroundColor Red
      Read-Host "Pulsa Enter para salir"; exit 1
    }
    Write-Host "[1/5] Extrayendo SDK incluido (esto puede tardar unos minutos)..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $sdk | Out-Null
    & $7z x $sdkArchive -o"$sdk" -y | Out-Null
    if (-not (Test-Path $emu) -or -not (Test-Path $adb) -or -not (Test-Path $sysDir)) {
      Write-Host "ERROR: La extraccion no quedo completa. Verifica que sdk.7z no esta corrupto." -ForegroundColor Red
      Read-Host "Pulsa Enter para salir"; exit 1
    }
    Write-Host "  SDK extraido correctamente." -ForegroundColor Green
  }
  else {
    Write-Host "[1/5] Instalando el SDK de Android..." -ForegroundColor Yellow
    if (-not (Install-SdkDesdeGoogle)) {
      Write-Host ""
      Write-Host "ERROR: No se pudo instalar el SDK automaticamente." -ForegroundColor Red
      Write-Host "Alternativa: copia sdk.7z a la raiz del paquete y vuelve a ejecutar," -ForegroundColor Red
      Write-Host "o descargalo de la Release del repositorio (ver README.md)." -ForegroundColor Red
      Read-Host "Pulsa Enter para salir"; exit 1
    }
    if (-not (Test-Path $emu) -or -not (Test-Path $adb) -or -not (Test-Path $sysDir)) {
      Write-Host "ERROR: El SDK se bajo pero falta algun componente." -ForegroundColor Red
      Write-Host "  emulator     : $(Test-Path $emu)"  -ForegroundColor DarkGray
      Write-Host "  platform-tools: $(Test-Path $adb)" -ForegroundColor DarkGray
      Write-Host "  imagen TV    : $(Test-Path $sysDir)" -ForegroundColor DarkGray
      Read-Host "Pulsa Enter para salir"; exit 1
    }
  }
}

# ---------------------------------------------------------------------------
# 2. DETECTAR la resolucion de ESTA pantalla y crear/ajustar el AVD "AndroidTV"
#    escribiendo sus .ini directamente (no hace falta avdmanager).
#
#    IMPORTANTE: la medida se saca de EnumDisplaySettings, que devuelve pixeles
#    FISICOS. GetSystemMetrics devuelve pixeles LOGICOS si Windows tiene
#    escalado (la Legion Go viene al 150%): con el metodo antiguo un panel de
#    2560x1600 se detectaba como 1707x1067 y el TV no llenaba la pantalla.
# ---------------------------------------------------------------------------
Write-Host "[2/5] Detectando resolucion y configurando AVD..." -ForegroundColor Yellow
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Scr {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType;
    public int dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  // El nombre de dispositivo debe ir como NULL de verdad (pantalla actual).
  [DllImport("user32.dll", CharSet=CharSet.Ansi, EntryPoint="EnumDisplaySettingsA")]
  private static extern bool EnumDisplaySettingsRaw(IntPtr dev, int mode, ref DEVMODE dm);
  public static int[] RealSize() {
    DEVMODE dm = new DEVMODE();
    dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (EnumDisplaySettingsRaw(IntPtr.Zero, -1, ref dm) && dm.dmPelsWidth > 0) {
      return new int[] { dm.dmPelsWidth, dm.dmPelsHeight };
    }
    return new int[] { GetSystemMetrics(0), GetSystemMetrics(1) };
  }
}
"@
[Scr]::SetProcessDPIAware() | Out-Null
$real = [Scr]::RealSize()
$scrW = $real[0]
$scrH = $real[1]
# La imagen de Android TV NO dibuja la interfaz mas ancha de 1920 px: aunque le
# pongas un AVD de 2560, Android lo limita a 1920 y luego lo estira (comprobado:
# un AVD nuevo a 2560x1440 arranca con "Override size: 1920x1080"). Asi que
# pedirle mas resolucion no da mas detalle, solo hace que la maquina virtual
# componga pixeles que despues tira. Se topa en 1920 respetando la proporcion:
# la ampliacion final hasta tu pantalla la hace la GPU del equipo, que ademas
# le quita trabajo a la VM.
$maxW = 1920
if ($scrW -gt $maxW) {
  $avdW = $maxW
  # alto proporcional y par (algunos codecs se atragantan con alturas impares)
  $avdH = [int]([math]::Round($scrH * $maxW / $scrW / 2) * 2)
  # 320 dpi es la densidad estandar de Android TV a 1080p (perfil tv_1080p)
  $dens = 320
} else {
  $avdW = $scrW
  $avdH = $scrH
  $dens = [math]::Round($scrH / 4.5)
}
Write-Host ("  Pantalla detectada: {0}x{1}" -f $scrW,$scrH) -ForegroundColor Cyan
if ($scrW -gt $maxW) {
  Write-Host ("  AVD a {0}x{1} (Android TV topa en 1920; tu GPU amplia el resto)" -f $avdW,$avdH) -ForegroundColor Cyan
}

# Recursos del invitado segun la maquina. Un invitado corto de CPU/RAM no le da
# tiempo a llenar el buffer de audio y se oyen chasquidos ("explosiones") y
# cortes al reproducir video. Se deja siempre margen para el propio Windows.
$hostCores = [int](Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$hostRamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$ncore = [math]::Max(2, [math]::Min(6, $hostCores - 2))
$ram   = if     ($hostRamGB -ge 12) { 4096 }
         elseif ($hostRamGB -ge 8)  { 3072 }
         else                       { 2048 }
Write-Host ("  Equipo: {0} nucleos logicos, {1} GB RAM  ->  invitado: {2} nucleos, {3} MB" -f $hostCores,$hostRamGB,$ncore,$ram) -ForegroundColor Cyan

$avdDir  = "$avdHome\avd\AndroidTV.avd"
$existia = Test-Path "$avdDir\config.ini"
New-Item -ItemType Directory -Force -Path $avdDir | Out-Null

# config.ini a partir de la plantilla, con la resolucion y recursos detectados
$cfg = Get-Content "$pkg\config\config.ini"
$cfg = $cfg -replace '^hw\.lcd\.width=.*',   "hw.lcd.width=$avdW"
$cfg = $cfg -replace '^hw\.lcd\.height=.*',  "hw.lcd.height=$avdH"
$cfg = $cfg -replace '^hw\.lcd\.density=.*', "hw.lcd.density=$dens"
$cfg = $cfg -replace '^skin\.name=.*',       "skin.name=${avdW}x${avdH}"
$cfg = $cfg -replace '^hw\.cpu\.ncore=.*',   "hw.cpu.ncore=$ncore"
$cfg = $cfg -replace '^hw\.ramSize=.*',      "hw.ramSize=$ram"
Set-Content -Path "$avdDir\config.ini" -Value $cfg -Encoding ASCII

# puntero AndroidTV.ini (rutas de ESTE equipo)
@(
  "avd.ini.encoding=UTF-8"
  "path=$avdDir"
  "path.rel=avd\AndroidTV.avd"
  "target=android-36"
) | Set-Content -Path "$avdHome\avd\AndroidTV.ini" -Encoding ASCII
Write-Host ("  AVD 'AndroidTV' configurado a {0}x{1}." -f $avdW,$avdH) -ForegroundColor Green

if ($SoloScripts -and $existia) {
  # Android cachea el tamanio de pantalla en su particion de datos la primera
  # vez que arranca. Si el AVD ya existia con OTRA resolucion, la ventana ira
  # a pantalla completa igualmente, pero Android seguira dibujando al tamanio
  # viejo y lo estirara (se ve algo menos nitido).
  Write-Host "  NOTA: el AVD ya existia. La ventana ira a pantalla completa, pero" -ForegroundColor Yellow
  Write-Host "        para que Android DIBUJE a la resolucion nueva (maxima nitidez)" -ForegroundColor Yellow
  Write-Host "        haria falta recrear el AVD desde cero, lo que borra las apps y" -ForegroundColor Yellow
  Write-Host "        sus sesiones. No se hace automaticamente." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 3. Copiar los scripts (lanzador + puente + diagnostico + vbs) a ~/.android
# ---------------------------------------------------------------------------
Write-Host "[3/5] Copiando scripts..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $avdHome | Out-Null
# Se copian TODOS los scripts del paquete, no una lista a mano: asi no se queda
# ninguno fuera al aniadir herramientas nuevas.
$copiados = 0
Get-ChildItem "$pkg\scripts\*.ps1", "$pkg\scripts\*.vbs" -ErrorAction SilentlyContinue | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $avdHome $_.Name) -Force
  $copiados++
}
Write-Host ("  {0} scripts copiados." -f $copiados) -ForegroundColor Green

# --- Reescalador Magpie ----------------------------------------------------
# Magpie hace DOS cosas imprescindibles: amplia la ventana del TV a pantalla
# completa, y su TouchHelper.exe es el que da soporte tactil. Sin el, el TV
# arranca en una ventana pequenia y el tactil no responde.
#
# NO se distribuye con el paquete: Magpie es GPL-3.0 y este proyecto es MIT,
# asi que se descarga de su release oficial igual que el SDK.
#   https://github.com/Blinue/Magpie
if (-not (Test-Path "$pkg\tools\magpie\Magpie.exe")) {
  Write-Host "  Descargando el reescalador Magpie (~11 MB)..." -ForegroundColor Yellow
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("user-agent", "AndroidTV-Portable")
    $rel = $wc.DownloadString("https://api.github.com/repos/Blinue/Magpie/releases/latest") | ConvertFrom-Json

    # Los portatiles con Snapdragon necesitan la build ARM64 o no arranca
    $arq = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'x64' }
    $asset = $rel.assets | Where-Object { $_.name -like "*-$arq.zip" } | Select-Object -First 1
    if (-not $asset) { throw "no hay build $arq en la release $($rel.tag_name)" }

    $zip = Join-Path $env:TEMP $asset.name
    if (-not (Test-Path $zip) -or (Get-Item $zip).Length -ne $asset.size) {
      $wc.DownloadFile($asset.browser_download_url, $zip)
    }
    New-Item -ItemType Directory -Force -Path "$pkg\tools\magpie" | Out-Null
    if (Test-Path $7z) {
      & $7z x $zip -o"$pkg\tools\magpie" -y | Out-Null
    } else {
      Expand-Archive -Path $zip -DestinationPath "$pkg\tools\magpie" -Force
    }
    # Algunas releases traen todo dentro de una subcarpeta; se aplana
    if (-not (Test-Path "$pkg\tools\magpie\Magpie.exe")) {
      $hallado = Get-ChildItem "$pkg\tools\magpie" -Recurse -Filter Magpie.exe |
                 Select-Object -First 1
      if ($hallado) {
        Get-ChildItem $hallado.DirectoryName | Move-Item -Destination "$pkg\tools\magpie" -Force
      }
    }
    if (Test-Path "$pkg\tools\magpie\Magpie.exe") {
      Write-Host "  Magpie $($rel.tag_name) descargado ($arq)." -ForegroundColor Green
    }
  } catch {
    Write-Host "  AVISO: no se pudo descargar Magpie: $_" -ForegroundColor Red
    Write-Host "  El TV funcionara, pero SIN pantalla completa y SIN tactil." -ForegroundColor Red
    Write-Host "  Bajalo a mano de https://github.com/Blinue/Magpie/releases" -ForegroundColor Red
    Write-Host "  y descomprimelo en tools\magpie\, luego ejecuta ACTUALIZAR.bat" -ForegroundColor Red
  }
}

if (Test-Path "$pkg\tools\magpie\Magpie.exe") {
  Write-Host "  Copiando reescalador (Magpie)..." -ForegroundColor Yellow
  robocopy "$pkg\tools\magpie" "$avdHome\magpie" /E /NFL /NDL /NJH /NJS /NP | Out-Null

  $mpDir = "$env:LOCALAPPDATA\Magpie\config\v4"
  New-Item -ItemType Directory -Force -Path $mpDir | Out-Null
  $mpCfg = "$mpDir\config.json"
  $qemuExe = "$sdk\emulator\qemu\windows-x86_64\qemu-system-x86_64.exe"
  try {
    if (Test-Path $mpCfg) {
      # Ya hay config: solo aniadir/actualizar nuestro perfil, sin tocar lo demas
      $j = Get-Content $mpCfg -Raw | ConvertFrom-Json
      $otros = @($j.profiles | Where-Object { $_.name -ne 'Android TV' })
      $base  = $j.profiles[0]
    } else {
      # Sin config previa: Magpie creara la suya al abrirse. Se deja preparada
      # una minima para que el perfil exista desde el primer arranque.
      $j = [pscustomobject]@{ profiles = @() }
      $base = $null
      Copy-Item "$pkg\config\magpie-config.json" $mpCfg -Force -ErrorAction SilentlyContinue
      if (Test-Path $mpCfg) { $j = Get-Content $mpCfg -Raw | ConvertFrom-Json; $base = $j.profiles[0] }
      $otros = @($j.profiles | Where-Object { $_.name -ne 'Android TV' })
    }
    if ($base) {
      $nuevo = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json   # copia
      $nuevo | Add-Member -NotePropertyName name          -NotePropertyValue 'Android TV' -Force
      $nuevo | Add-Member -NotePropertyName packaged      -NotePropertyValue $false       -Force
      $nuevo | Add-Member -NotePropertyName pathRule      -NotePropertyValue $qemuExe     -Force
      $nuevo | Add-Member -NotePropertyName classNameRule -NotePropertyValue 'Qt653QWindowIcon' -Force
      $nuevo | Add-Member -NotePropertyName autoScale     -NotePropertyValue $true        -Force
      # IMPORTANTE: el boton "Iniciar" de Magpie ejecuta launcherPath; si se deja
      # vacio, ejecuta el pathRule (qemu-system-x86_64.exe) SUELTO y falla con
      # errores de "DLL no encontrada", porque ese binario necesita las DLL de la
      # carpeta padre del emulador. Se apunta al acceso directo del TV.
      $nuevo | Add-Member -NotePropertyName launcherPath  -NotePropertyValue "$([Environment]::GetFolderPath('Desktop'))\Android TV.lnk" -Force
      $nuevo | Add-Member -NotePropertyName scalingMode   -NotePropertyValue 3            -Force  # CuNNy
      $j.profiles = @($otros) + @($nuevo)
      $j | ConvertTo-Json -Depth 20 | Set-Content $mpCfg -Encoding UTF8
      Write-Host "  Magpie listo (perfil 'Android TV' con CuNNy)." -ForegroundColor Green
    }
  } catch {
    Write-Host "  Magpie copiado, pero no pude dejarle el perfil: $_" -ForegroundColor Yellow
    Write-Host "  Podras escalar igualmente con su atajo (Win+Shift+A)." -ForegroundColor Yellow
  }
}

# ---------------------------------------------------------------------------
# 4. Arrancar el emulador (arranque en frio) e instalar las apps
# ---------------------------------------------------------------------------
if (-not $SoloScripts) {
  Write-Host "[4/5] Arrancando emulador e instalando apps (1a vez ~1-2 min)..." -ForegroundColor Yellow
  & $adb start-server | Out-Null

  # --- Limpiar bloqueos huerfanos ------------------------------------------
  # Si el emulador no se cerro limpiamente la vez anterior (cierre forzado,
  # cuelgue, apagon), deja bloqueos en el AVD. Al arrancar de nuevo cree que el
  # 5554 sigue ocupado y se abre en el 5556 — y esta funcion esperaba justo al
  # 5554, asi que se quedaba mirando 5 minutos y se rendia sin decir por que.
  if (-not ((& $adb devices) -match 'emulator-')) {
    $avdDirLock = "$avdHome\avd\AndroidTV.avd"
    foreach ($lock in @('hardware-qemu.ini.lock', 'multiinstance.lock', 'hardware-qemu.ini.lock2')) {
      $ruta = Join-Path $avdDirLock $lock
      if (-not (Test-Path $ruta)) { continue }
      # Si el pid del bloqueo sigue vivo, NO se toca: hay un emulador de verdad
      $vivo = $false
      $pidFile = Join-Path $ruta 'pid'
      if (Test-Path $pidFile) {
        $p = (Get-Content $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($p -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) { $vivo = $true }
      }
      if (-not $vivo) {
        Remove-Item $ruta -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Limpiado bloqueo huerfano: $lock" -ForegroundColor DarkGray
      }
    }
  }

  if (-not ((& $adb devices) -match 'emulator-')) {
    Start-Process $emu -ArgumentList '-avd','AndroidTV','-no-snapshot'
  }

  # --- Esperar a que aparezca ----------------------------------------------
  # Se acepta CUALQUIER puerto, no solo el 5554: si otro emulador ya ocupa ese
  # puerto, el nuestro sale en el 5556 y antes se daba por perdido.
  # Y se imprime un punto cada 3 s: cinco minutos de consola muda parecen un
  # cuelgue, y el usuario cierra la ventana antes de que termine.
  Write-Host "  Esperando al emulador" -NoNewline -ForegroundColor DarkGray
  $script:serial = ''
  $deadline = (Get-Date).AddSeconds(300)
  do {
    Start-Sleep -Seconds 3
    Write-Host "." -NoNewline -ForegroundColor DarkGray
    $line = (& $adb devices | Select-String '^emulator-\d+\s+device')
    if ($line) { $serial = ($line -split '\s+')[0] }
  } until ($serial -or ((Get-Date) -gt $deadline))
  Write-Host ""

  if (-not $serial) {
    Write-Host "  El emulador no aparecio en 5 minutos." -ForegroundColor Red
    Write-Host "  Prueba a cerrar cualquier Chrome o emulador abierto y reejecuta." -ForegroundColor Red
    Write-Host "  Si persiste, ejecuta DIAGNOSTICO.bat y revisa la salida." -ForegroundColor Red
  } else {
    Write-Host "  Emulador listo en $serial. Esperando a que arranque Android" -NoNewline -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds(180)
    do {
      Start-Sleep -Seconds 3
      Write-Host "." -NoNewline -ForegroundColor DarkGray
      $boot = & $adb -s $serial shell getprop sys.boot_completed 2>$null
    } until (($boot -match '1') -or ((Get-Date) -gt $deadline))
    Write-Host ""
  }

  if ($boot -match '1') {
    $apks = @(Get-ChildItem "$pkg\apps\*.apk" -ErrorAction SilentlyContinue)
    if ($apks.Count -eq 0) {
      Write-Host "  No hay ningun .apk en apps\, no se instala nada." -ForegroundColor Yellow
      Write-Host "  Deja ahi los que quieras y ejecuta ACTUALIZAR.bat." -ForegroundColor Yellow
    }
    foreach ($a in $apks) {
      Write-Host ("  Instalando {0}..." -f $a.Name)
      & $adb -s $serial install -r $a.FullName | Out-Null
    }
    if ($apks.Count -gt 0) { Write-Host "  Apps instaladas." -ForegroundColor Green }
  } else {
    Write-Host "  El emulador no arranco a tiempo; instala las apps luego con 'adb install'." -ForegroundColor Yellow
  }

  # Cerrar el emulador que abrimos NOSOTROS.
  # Este arranque es solo para poder hacer 'adb install': es el emulador pelado,
  # sin pantalla completa y sin Magpie. Si se deja abierto parece que el TV ya
  # arranco, el usuario lo usa asi, y concluye que la optimizacion no funciona.
  # El TV de verdad lo lanza el acceso directo del escritorio, que es quien
  # coloca la ventana y llama al reescalador.
  if ($serial) {
    Write-Host "  Cerrando el emulador de instalacion..." -ForegroundColor Yellow
    & $adb -s $serial emu kill 2>$null | Out-Null

    # 'emu kill' es un apagado ORDENADO y puede tardar: se le da margen de
    # sobra. Solo si no obedece se mata a la fuerza, y entonces hay que barrer
    # los bloqueos que deja, o la siguiente instalacion arranca el emulador en
    # otro puerto y parece colgada. Esto ultimo ya rompio una instalacion real.
    $espera = (Get-Date).AddSeconds(45)
    do {
      Start-Sleep -Seconds 2
      $sigue = (& $adb devices) -match [regex]::Escape($serial)
    } until ((-not $sigue) -or ((Get-Date) -gt $espera))

    if ($sigue) {
      Write-Host "  No respondio al cierre ordenado, forzando..." -ForegroundColor Yellow
      Get-Process -Name qemu-system-x86_64, emulator -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Kill() } catch {} }
      Start-Sleep -Seconds 3
      $avdDirLock = "$avdHome\avd\AndroidTV.avd"
      foreach ($lock in @('hardware-qemu.ini.lock', 'multiinstance.lock', 'hardware-qemu.ini.lock2')) {
        Remove-Item (Join-Path $avdDirLock $lock) -Recurse -Force -ErrorAction SilentlyContinue
      }
      Write-Host "  Bloqueos del AVD limpiados." -ForegroundColor DarkGray
    }
  }
  Write-Host "  Listo. Abre el TV desde el acceso directo del escritorio." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 5. Crear el acceso directo "Android TV" en el escritorio
# ---------------------------------------------------------------------------
Write-Host "[5/5] Creando acceso directo en el escritorio..." -ForegroundColor Yellow
$desktop = [Environment]::GetFolderPath('Desktop')

# El icono se COPIA a $avdHome: si el .lnk apuntara al icono dentro de la
# carpeta del paquete, se quedaria roto en cuanto la muevas o la borres.
$icono = "$emu, 0"                       # respaldo: el icono del emulador
$icoOrigen  = "$pkg\assets\AndroidTV.ico"
$icoDestino = "$avdHome\AndroidTV.ico"
if (Test-Path $icoOrigen) {
  Copy-Item $icoOrigen $icoDestino -Force
  $icono = "$icoDestino, 0"
} elseif (Test-Path $icoDestino) {
  $icono = "$icoDestino, 0"              # ya estaba de una instalacion previa
}

$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut("$desktop\Android TV.lnk")
$lnk.TargetPath       = "$env:WINDIR\System32\wscript.exe"
$lnk.Arguments        = """$avdHome\android-tv-launch.vbs"""
$lnk.WorkingDirectory = $env:USERPROFILE
$lnk.IconLocation     = $icono
$lnk.Description      = "Arranca el emulador Android TV en pantalla completa"
$lnk.Save()

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host " LISTO. Tienes 'Android TV' en el escritorio." -ForegroundColor Green
Write-Host " Doble clic para arrancar el TV a pantalla completa." -ForegroundColor Green
Write-Host " Mando: cruceta/stick=navegar, A=OK, B=atras," -ForegroundColor Green
Write-Host "        Start=Home, LB/RB=volumen." -ForegroundColor Green
Write-Host ""
Write-Host " Si al navegar el foco SALTA DE DOS EN DOS, ejecuta" -ForegroundColor Green
Write-Host " DIAGNOSTICO.bat y mira la seccion MANDO del LEEME.txt." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Read-Host "Pulsa Enter para cerrar"
