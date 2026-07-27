# Android TV: arranca el emulador y pone SU PROPIA ventana en pantalla completa
# real (sin bordes). Se usa la ventana nativa -no scrcpy- porque algunas apps
# (IPTV, VPN) marcan su pantalla como protegida (FLAG_SECURE) y en scrcpy salen
# NEGRAS; la ventana nativa del emulador si las dibuja.
# Al terminar de ver: Alt+F4 sobre la imagen cierra el emulador.
$ErrorActionPreference = 'SilentlyContinue'

$sdk = "$env:LOCALAPPDATA\Android\Sdk"
$adb = "$sdk\platform-tools\adb.exe"

# 0. Levantar un servidor adb sano ANTES de arrancar el emulador. Si no,
#    el emulador arranca sin poder hablar con adb y el dispositivo se queda
#    en estado "offline" (Android arranca pero no se puede controlar).
& $adb start-server 2>$null | Out-Null

# 1. Arrancar el emulador (con ventana) si no esta corriendo.
#    -no-snapshot: SIEMPRE arranque en frio. Es ~20 s mas lento, pero evita el
#    cuelgue por snapshot corrupto (que dejaba el TV en negro sin arrancar).
#    -audio: el motor de audio del emulador solo trae dos backends en Windows,
#    "dsound" (DirectSound, el de por defecto) y "winaudio". DirectSound es el
#    que suele dar chasquidos. Se puede cambiar en %USERPROFILE%\.android\tv.ini
#    con la linea  audio=winaudio  (o audio=dsound para volver al normal).
$audio = ''
$tvIniPath = "$env:USERPROFILE\.android\tv.ini"
if (Test-Path $tvIniPath) {
  $ma = (Get-Content $tvIniPath | Select-String '^\s*audio\s*=\s*(\S+)')
  if ($ma) { $audio = $ma.Matches[0].Groups[1].Value }
}

#    ARRANQUE: por defecto en frio (-no-snapshot), que es lo seguro. Con
#    "arranque=rapido" en tv.ini se usa la instantanea: arranca en segundos y,
#    sobre todo, Android REANUDA ya asentado, sin el trabajo de post-arranque
#    que hace que el audio vaya mal los primeros minutos.
#    El riesgo del arranque rapido es que la instantanea se corrompa y el TV se
#    quede en negro (nos paso). Por eso aqui NO se deja al azar: si no arranca
#    a tiempo, se borra la instantanea y se reintenta en frio automaticamente.
$arranque = 'seguro'
if (Test-Path $tvIniPath) {
  $mr = (Get-Content $tvIniPath | Select-String '^\s*arranque\s*=\s*(\S+)')
  if ($mr -and $mr.Matches[0].Groups[1].Value -match '^(rapido|rapida|fast)$') { $arranque = 'rapido' }
}

$snapDir = "$env:USERPROFILE\.android\avd\AndroidTV.avd\snapshots"

# CAUSA DE "SE QUEDA EN NEGRO Y NO ARRANCA":
# tras un cierre brusco, el emulador guarda datos de fallo y en el SIGUIENTE
# arranque muestra un dialogo pidiendo permiso para enviarlos a Google. Ese
# dialogo es MODAL y bloquea el arranque: el TV no aparece nunca y adb no ve
# nada, aunque el proceso este vivo. Peor aun: la ventana puede salir fuera de
# pantalla, asi que ni la ves para cerrarla.
# Se borran esos datos antes de arrancar (solo sirven para el informe a Google)
# y ademas se pasa -no-metrics para que no vuelva a preguntarlo.
function Limpiar-DatosDeFallo {
  Remove-Item -Recurse -Force "$env:TEMP\AndroidEmulator" -ErrorAction SilentlyContinue
}

# MODO DE GPU.  Linea  gpu=<modo>  en tv.ini
# Por defecto vacio = 'auto', que elige Vulkan sobre la GPU real y es lo mas
# rapido. Pero hay drivers —vistos en AMD recientes— con los que el emulador
# se cae nada mas inicializar Vulkan, sin mensaje util. El instalador detecta
# ese caso y escribe aqui  gpu=swangle , que renderiza con SwiftShader en vez
# de usar el Vulkan del driver: algo menos eficiente, pero arranca siempre.
$gpuModo = ''
if (Test-Path $tvIniPath) {
  $mg = (Get-Content $tvIniPath | Select-String '^\s*gpu\s*=\s*(\S+)')
  if ($mg) { $gpuModo = $mg.Matches[0].Groups[1].Value }
}

function Start-Emulador($rapido) {
  Limpiar-DatosDeFallo
  $a = @('-avd', 'AndroidTV', '-no-metrics')
  if (-not $rapido) { $a += '-no-snapshot' }
  if ($audio) { $a += @('-audio', $audio) }
  if ($gpuModo) { $a += @('-gpu', $gpuModo) }
  Start-Process "$sdk\emulator\emulator.exe" -ArgumentList $a
}

$avdDir = "$env:USERPROFILE\.android\avd\AndroidTV.avd"

# Cierra el emulador A LA FUERZA y deja el AVD limpio para poder rearrancar.
# Es delicado por dos motivos aprendidos a base de fallar:
#  - Un emulador colgado por una instantanea mala NO responde a "emu kill":
#    adb ni siquiera llega a verlo. Hay que ir al proceso.
#  - No vale esperar unos segundos fijos: hay que esperar a que el proceso
#    DESAPAREZCA de verdad y borrar los cerrojos que deja un cierre brusco.
#    Si no, el siguiente arranque muere con
#    "Running multiple emulators with the same AVD".
function Stop-Emulador-Forzado {
  & $adb -s emulator-5554 emu kill 2>$null | Out-Null
  $lim = (Get-Date).AddSeconds(10)
  while ((Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $lim)) {
    Start-Sleep -Milliseconds 500
  }
  Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue | Stop-Process -Force
  $lim = (Get-Date).AddSeconds(20)
  while ((Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $lim)) {
    Start-Sleep -Milliseconds 500
  }
  Start-Sleep -Seconds 2
  # cerrojos que deja el cierre brusco (el primero es una CARPETA)
  Remove-Item -Recurse -Force "$avdDir\hardware-qemu.ini.lock" -ErrorAction SilentlyContinue
  Remove-Item -Force        "$avdDir\multiinstance.lock"       -ErrorAction SilentlyContinue
}

# Espera a estado "device". Devuelve $true si lo consigue.
function Wait-Device($segundos) {
  $lim = (Get-Date).AddSeconds($segundos)
  do {
    Start-Sleep -Seconds 2
    $l = (& $adb devices 2>$null | Select-String 'emulator-5554')
    $st = if ($l) { ($l -split '\s+')[-1] } else { '' }
    if ($st -eq 'device') { return $true }
  } until ((Get-Date) -gt $lim)
  return $false
}

$running = (& $adb devices 2>$null) -match 'emulator-5554'
if (-not $running) {
  Start-Emulador ($arranque -eq 'rapido')

  if ($arranque -eq 'rapido') {
    # Con instantanea deberia estar listo en pocos segundos. Si a los 90 s no
    # ha levantado, se da por corrupta: se mata, se borra y se arranca en frio.
    if (-not (Wait-Device 90)) {
      Stop-Emulador-Forzado
      Remove-Item -Recurse -Force $snapDir -ErrorAction SilentlyContinue
      Start-Emulador $false      # en frio, ya sin instantanea
    }
  }
}

# 2. Esperar a que el dispositivo este ONLINE (estado "device").
#    Durante el arranque en frio es NORMAL ver "offline" o nada un rato: solo
#    hay que esperar con paciencia hasta que pase a "device" (NO reiniciar adb,
#    eso lo desconecta y lo rompe).
$deadline = (Get-Date).AddSeconds(240)
do {
  Start-Sleep -Seconds 2
  $line  = (& $adb devices 2>$null | Select-String 'emulator-5554')
  $state = if ($line) { ($line -split '\s+')[-1] } else { '' }
} until (($state -eq 'device') -or ((Get-Date) -gt $deadline))
if ($state -ne 'device') { exit 1 }

# 3. Esperar a que Android termine de arrancar del todo
$deadline = (Get-Date).AddSeconds(180)
do {
  Start-Sleep -Seconds 2
  $boot = & $adb -s emulator-5554 shell getprop sys.boot_completed 2>$null
} until (($boot -match '1') -or ((Get-Date) -gt $deadline))
if (-not ($boot -match '1')) { exit 1 }
Start-Sleep -Seconds 2

# 4. Poner la ventana del emulador a pantalla completa sin bordes.
#    OJO con el escalado de Windows (la Legion Go viene al 150%): si el proceso
#    no es "DPI aware", GetSystemMetrics devuelve pixeles LOGICOS (p.ej. 1707x1067
#    en vez de 2560x1600) y la ventana se queda pequenia. Por eso la medida real
#    se saca de EnumDisplaySettings, que SIEMPRE devuelve pixeles fisicos.
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class TV {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

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

  // Resolucion FISICA del monitor principal, inmune al escalado de Windows.
  public static int[] RealSize() {
    DEVMODE dm = new DEVMODE();
    dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (EnumDisplaySettingsRaw(IntPtr.Zero, -1 /*ENUM_CURRENT_SETTINGS*/, ref dm) && dm.dmPelsWidth > 0) {
      return new int[] { dm.dmPelsWidth, dm.dmPelsHeight };
    }
    return new int[] { GetSystemMetrics(0), GetSystemMetrics(1) };
  }

  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);

  // La "barra blanca" cortada del borde derecho es la barra de controles del
  // emulador: una ventana Qt aparte, clase Qt*QWindowToolSaveBits y titulo
  // "Emulator". Con la ventana principal a pantalla completa queda pegada al
  // borde y casi toda fuera de pantalla, asi que no sirve para nada. Se oculta.
  // Devuelve cuantas oculto.
  public static int HideToolbars() {
    int n = 0;
    uint mainPid; GetWindowThreadProcessId(Found, out mainPid);
    if (mainPid == 0) return 0;
    int[] count = new int[1];
    EnumWindows(new EnumProc(delegate(IntPtr h, IntPtr l) {
      if (h == Found || !IsWindowVisible(h)) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != mainPid) return true;
      StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
      if (c.ToString().Contains("QWindowTool")) {
        ShowWindow(h, 0 /*SW_HIDE*/);
        count[0]++;
      }
      return true;
    }), IntPtr.Zero);
    n = count[0];
    return n;
  }

  public static IntPtr Found = IntPtr.Zero;
  public static void Find() {
    Found = IntPtr.Zero;
    EnumWindows(new EnumProc(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder sb = new StringBuilder(256); GetWindowText(h, sb, 256);
      string t = sb.ToString();
      // La ventana principal se llama "Android Emulator - <AVD>:<puerto>".
      // Se descartan las ventanas auxiliares de Qt (barra de herramientas, etc.)
      // exigiendo que el titulo lleve el ":" del puerto.
      if (t.StartsWith("Android Emulator") && t.Contains(":")) { Found = h; return false; }
      return true;
    }), IntPtr.Zero);
  }
}
"@
[TV]::SetProcessDPIAware() | Out-Null
$real = [TV]::RealSize()
$sw = $real[0]
$sh = $real[1]

# MODO ESCALADOR (opcional). Con  escalador=si  en tv.ini, la ventana NO se
# estira a pantalla completa: se deja al tamanio nativo del AVD y centrada,
# para que un reescalador externo (Magpie) la amplie el con su filtro neuronal.
# Si la ventana ya ocupara toda la pantalla, Magpie no tendria nada que ampliar.
$escalador = $false
if (Test-Path $tvIniPath) {
  $me = (Get-Content $tvIniPath | Select-String '^\s*escalador\s*=\s*(\S+)')
  if ($me -and $me.Matches[0].Groups[1].Value -match '^(si|s|1|true)$') { $escalador = $true }
}
if ($escalador) {
  # Tamanio nativo del AVD (lo que Android dibuja de verdad)
  $cfgAvd = "$env:USERPROFILE\.android\avd\AndroidTV.avd\config.ini"
  if (Test-Path $cfgAvd) {
    $lw = (Get-Content $cfgAvd | Select-String '^hw\.lcd\.width=(\d+)')
    $lh = (Get-Content $cfgAvd | Select-String '^hw\.lcd\.height=(\d+)')
    if ($lw -and $lh) {
      $sw = [int]$lw.Matches[0].Groups[1].Value
      $sh = [int]$lh.Matches[0].Groups[1].Value
    }
  }
}

# La ventana puede tardar un poco en existir tras el arranque: reintentar ~20 s
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 20; $i++) {
  [TV]::Find(); $h = [TV]::Found
  if ($h -ne [IntPtr]::Zero) { break }
  Start-Sleep -Milliseconds 1000
}
if ($h -eq [IntPtr]::Zero) { exit 0 }

$GWL_STYLE     = -16
$WS_CAPTION    = 0x00C00000
$WS_THICKFRAME = 0x00040000
$WS_BORDER     = 0x00800000
$WS_DLGFRAME   = 0x00400000
$SW_RESTORE    = 9

# Se aplica varias veces y se VERIFICA: Qt reajusta su ventana despues de
# arrancar (y una ventana maximizada ignora SetWindowPos), asi que un solo
# intento se pierde. Se repite hasta que el rectangulo real cubra la pantalla.
for ($try = 0; $try -lt 12; $try++) {
  # Una ventana maximizada no se deja redimensionar: restaurarla primero.
  [TV]::ShowWindow($h, $SW_RESTORE) | Out-Null

  $st  = [TV]::GetWindowLong($h, $GWL_STYLE)
  $new = ($st -band (-bnot $WS_CAPTION) -band (-bnot $WS_THICKFRAME) `
              -band (-bnot $WS_BORDER)  -band (-bnot $WS_DLGFRAME))
  if ($new -ne $st) { [TV]::SetWindowLong($h, $GWL_STYLE, $new) | Out-Null }

  # HWND_TOPMOST (-1): sin esto Windows deja asomar la BARRA DE TAREAS por
  # encima del TV (en la Legion Go basta un gesto tactil desde el borde para
  # que salga). Marcandola "siempre encima" la barra ya no la tapa.
  # En modo escalador se usa HWND_NOTOPMOST (-2) y la ventana va centrada:
  # el que debe quedar encima es Magpie, no el emulador.
  $zorder = if ($escalador) { [IntPtr](-2) } else { [IntPtr](-1) }
  $px = if ($escalador) { [int](([TV]::GetSystemMetrics(0) - $sw) / 2) } else { 0 }
  $py = if ($escalador) { [int](([TV]::GetSystemMetrics(1) - $sh) / 2) } else { 0 }
  # SWP_FRAMECHANGED(0x20) | SWP_SHOWWINDOW(0x40)
  [TV]::SetWindowPos($h, $zorder, $px, $py, $sw, $sh, (0x20 -bor 0x40)) | Out-Null
  [TV]::SetForegroundWindow($h) | Out-Null

  # Ocultar la barra de controles de Qt (la "barra blanca" del borde derecho)
  [TV]::HideToolbars() | Out-Null

  $r = New-Object TV+RECT
  if ([TV]::GetWindowRect($h, [ref]$r)) {
    # En modo escalador solo importa el TAMANIO (va centrada, no en 0,0).
    $okTam = (($r.Right - $r.Left) -ge $sw) -and (($r.Bottom - $r.Top) -ge $sh)
    $okPos = $escalador -or ($r.Left -le 0 -and $r.Top -le 0)
    if ($okTam -and $okPos) { break }
  }
  Start-Sleep -Milliseconds 500
}

# 4b. Arrancar el reescalador (solo en modo escalador y si esta instalado).
#     Magpie amplia la ventana del TV hasta llenar la pantalla con su filtro
#     neuronal. Si no esta, no pasa nada: el TV se ve igual, solo mas pequenio.
if ($escalador) {
  $magpie = "$env:USERPROFILE\.android\magpie\Magpie.exe"
  if (Test-Path $magpie) {
    if (-not (Get-Process Magpie -ErrorAction SilentlyContinue)) {
      Start-Process $magpie -WorkingDirectory (Split-Path $magpie)
      Start-Sleep -Seconds 4
    }
    # Volver a poner el TV delante para que Magpie lo detecte y lo escale
    [TV]::Find(); $h2 = [TV]::Found
    if ($h2 -ne [IntPtr]::Zero) { [TV]::SetForegroundWindow($h2) | Out-Null }
  }
}

# 5. Arrancar el puente mando->teclado (instancia unica; se cierra con el emulador)
#    Va antes de abrir la app para que el mando responda cuanto antes; el puente
#    ademas sigue vigilando la barra de controles de Qt cada ~2 s.
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
  "$env:USERPROFILE\.android\android-tv-gamepad.ps1"
)

# 6. Abrir directamente la app del TV (en vez de quedarse en el menu de Android).
#    Configurable en  %USERPROFILE%\.android\tv.ini  con la linea:
#       app=com.android.mgstxNF     <- paquete a abrir al arrancar
#       app=ninguno                 <- no abrir nada, quedarse en el menu
#    Se lanza con "monkey -c LAUNCHER", que resuelve la actividad de inicio
#    SOLO (no se fija a fuego, porque cambia si actualizas la app).
$app = 'com.android.mgstxNF'      # XUPER TV NF por defecto
$tvIni = "$env:USERPROFILE\.android\tv.ini"
if (Test-Path $tvIni) {
  $m = (Get-Content $tvIni | Select-String '^\s*app\s*=\s*(\S+)')
  if ($m) { $app = $m.Matches[0].Groups[1].Value }
}

if ($app -and $app -ne 'ninguno') {
  # Solo si esta instalada; si no, se queda en el menu de Android TV.
  $installed = (& $adb -s emulator-5554 shell pm list packages $app 2>$null) -match [regex]::Escape($app)
  if ($installed) {
    for ($i = 0; $i -lt 5; $i++) {
      & $adb -s emulator-5554 shell monkey -p $app -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
      Start-Sleep -Seconds 3
      # Comprobar que de verdad quedo en primer plano dentro de Android
      $top = & $adb -s emulator-5554 shell "dumpsys activity activities | grep -m1 topResumedActivity" 2>$null
      if ($top -match [regex]::Escape($app)) { break }
    }
  }
}

# 7. Refuerzo final por si Qt reactiva la barra de controles al abrir la app
for ($i = 0; $i -lt 6; $i++) {
  Start-Sleep -Milliseconds 700
  [TV]::HideToolbars() | Out-Null
}
