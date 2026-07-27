# Puente MANDO -> TECLADO/ADB para el Android TV.
#
# Lee el mando por DOS vias y usa la que encuentre:
#   1) XInput  (mandos tipo Xbox: Legion Go, Steam Deck, Xbox, DS4 con DS4Windows)
#   2) winmm / joyGetPosEx (DirectInput / HID clasico)
# Solo actua cuando la ventana del emulador esta en primer plano.
#
# Mapeo:
#   Cruceta / stick izquierdo -> flechas (navegar, con auto-repeticion)
#   A     -> Enter (OK)
#   B     -> KEYCODE_BACK por adb (en Android ESCAPE != BACK; el reproductor
#            solo obedece BACK de verdad)
#   Start -> KEYCODE_HOME
#   LB/RB -> bajar/subir volumen (mantener repite)
#
# MODO DE NAVEGACION  (fichero  %USERPROFILE%\.android\gamepad.ini )
#   nav=teclado    -> el puente inyecta las flechas y el Enter  (por defecto)
#   nav=emulador   -> el puente NO toca la navegacion; deja que el emulador
#                     reenvie el mando el solo, y el puente solo aniade
#                     volumen (LB/RB) y HOME. Usa esto si al navegar el foco
#                     SALTA DE DOS EN DOS: significa que el emulador ya esta
#                     reenviando el mando y se estaba duplicando la entrada.
#
# Se cierra solo cuando el emulador ya no existe. Instancia unica (mutex).
$ErrorActionPreference = 'SilentlyContinue'

# --- registro ---------------------------------------------------------------
# El puente arranca OCULTO, asi que si algo falla no se ve nada por pantalla.
# Se deja rastro en puente.log para poder diagnosticarlo despues (sobre todo en
# equipos a los que no se tiene acceso directo, como la Legion Go).
$logFile = "$env:USERPROFILE\.android\puente.log"
function Log($msg) {
  try {
    $linea = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $script:logFile -Value $linea -Encoding UTF8
  } catch { }
}
# Que no crezca sin limite
try {
  if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 200KB)) {
    Set-Content -Path $logFile -Value (Get-Content $logFile -Tail 100) -Encoding UTF8
  }
} catch { }
Log "--- arranque del puente (PS $($PSVersionTable.PSVersion)) ---"

# --- instancia unica ---
$mutex = New-Object System.Threading.Mutex($true, 'AndroidTV_GamepadBridge', [ref]$null)
if (-not $mutex.WaitOne(0)) { Log "ya habia otra instancia; salgo"; exit }

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

# --- configuracion (opcional) ---
$navMode = 'teclado'
$cfgFile = "$env:USERPROFILE\.android\gamepad.ini"
if (Test-Path $cfgFile) {
  $m = (Get-Content $cfgFile | Select-String '^\s*nav\s*=\s*(\w+)')
  if ($m) { $navMode = $m.Matches[0].Groups[1].Value.ToLower() }
}

# En modo escalador NO se debe poner el TV "siempre encima": el que tiene que
# quedar delante es Magpie, que es quien muestra la imagen ampliada. Si el
# emulador se pusiera encima, taparia al reescalador con su ventana pequenia.
$escalador = $false
$tvIniFile = "$env:USERPROFILE\.android\tv.ini"
if (Test-Path $tvIniFile) {
  $me = (Get-Content $tvIniFile | Select-String '^\s*escalador\s*=\s*(\S+)')
  if ($me -and $me.Matches[0].Groups[1].Value -match '^(si|s|1|true)$') { $escalador = $true }
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class GP {
  // ---------- winmm (DirectInput / HID) ----------
  [StructLayout(LayoutKind.Sequential)]
  public struct JOYINFOEX {
    public uint dwSize, dwFlags, dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos, dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2;
  }
  [DllImport("winmm.dll")] public static extern uint joyGetPosEx(uint id, ref JOYINFOEX pi);

  // ---------- XInput (mandos tipo Xbox) ----------
  [StructLayout(LayoutKind.Sequential)]
  public struct XPAD { public ushort wButtons; public byte bLT, bRT; public short sLX, sLY, sRX, sRY; }
  [StructLayout(LayoutKind.Sequential)]
  public struct XSTATE { public uint dwPacket; public XPAD Gamepad; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")]
  private static extern uint XGet14(uint i, ref XSTATE s);
  [DllImport("xinput9_1_0.dll", EntryPoint="XInputGetState")]
  private static extern uint XGet910(uint i, ref XSTATE s);

  // xinput1_4 existe en Win8+; xinput9_1_0 esta en todas. Se prueba y se
  // recuerda cual funciona para no pagar la excepcion en cada lectura.
  private static int xDll = 0;   // 0=sin probar, 1=1_4, 2=9_1_0, -1=ninguna
  public static uint XGet(uint i, ref XSTATE s) {
    if (xDll == 0) {
      try { XGet14(0, ref s); xDll = 1; }
      catch { try { XGet910(0, ref s); xDll = 2; } catch { xDll = -1; } }
    }
    if (xDll == 1) { try { return XGet14(i, ref s); } catch { return 1; } }
    if (xDll == 2) { try { return XGet910(i, ref s); } catch { return 1; } }
    return 1;
  }

  // ---------- teclado / ventana ----------
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

  // Mantiene oculta la barra de controles de Qt (la "barra blanca" cortada del
  // borde derecho). Qt puede volver a mostrarla al reactivar la ventana, asi
  // que se revisa periodicamente durante toda la sesion.
  public static void HideToolbars() {
    IntPtr fg = GetForegroundWindow();
    uint mainPid; GetWindowThreadProcessId(fg, out mainPid);
    if (mainPid == 0) return;
    EnumWindows(new EnumProc(delegate(IntPtr h, IntPtr l) {
      if (h == fg || !IsWindowVisible(h)) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != mainPid) return true;
      StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
      if (c.ToString().Contains("QWindowTool")) { ShowWindow(h, 0 /*SW_HIDE*/); }
      return true;
    }), IntPtr.Zero);
  }
  public static void Tap(byte vk) { keybd_event(vk,0,0,IntPtr.Zero); keybd_event(vk,0,2,IntPtr.Zero); }
  public static bool EmuFocused() {
    IntPtr h = GetForegroundWindow();
    StringBuilder sb = new StringBuilder(256); GetWindowText(h, sb, 256);
    string t = sb.ToString();
    return t.StartsWith("Android Emulator") && t.Contains(":");
  }

  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

  // Ventana principal del TV (o IntPtr.Zero si ya no existe).
  public static IntPtr FindEmu() {
    IntPtr found = IntPtr.Zero;
    EnumWindows(new EnumProc(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder sb = new StringBuilder(256); GetWindowText(h, sb, 256);
      string t = sb.ToString();
      if (t.StartsWith("Android Emulator") && t.Contains(":")) { found = h; return false; }
      return true;
    }), IntPtr.Zero);
    return found;
  }

  // OJO con la diferencia entre estos dos casos:
  //
  // 1) BARRA DE TAREAS / teclado tactil: se ponen delante por un gesto tactil
  //    sin que el usuario quiera cambiar de programa. Aqui SI hay que seguir
  //    manejando el TV y devolverle el foco.
  public static bool IsTaskbarClass(string k) {
    return k == "Shell_TrayWnd" || k == "Shell_SecondaryTrayWnd" ||
           k == "IPTip_Main_Window";
  }
  // 2) CONMUTADOR DE TAREAS (Alt+Tab), vista de tareas, escritorio: aqui el
  //    usuario SI esta cambiando de aplicacion a proposito. Si el puente
  //    reclamara el foco aqui, haria imposible el Alt+Tab (era justo el fallo
  //    que hacia que el TV se quedase pegado en primer plano).
  public static bool IsSwitcherClass(string k) {
    return k == "XamlExplorerHostIslandWindow" || k == "MultitaskingViewFrame" ||
           k == "TaskListThumbnailWnd" || k == "Windows.UI.Core.CoreWindow" ||
           k == "ForegroundStaging" || k == "WorkerW" || k == "Progman";
  }
  public static string ClassOf(IntPtr h) {
    StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
    return c.ToString();
  }
  public static bool IsTaskbarWindow(IntPtr h)  { return IsTaskbarClass(ClassOf(h)); }
  public static bool IsSwitcherWindow(IntPtr h) { return IsSwitcherClass(ClassOf(h)); }

  [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint p, IntPtr v, uint f);

  // Windows bloquea SetForegroundWindow desde un proceso en segundo plano.
  // NO se usa el truco de AttachThreadInput sobre el hilo del shell: probado,
  // y hace que Windows abra el conmutador de tareas (Alt+Tab) en vez de dar el
  // foco. Lo correcto es poner a 0 el tiempo de bloqueo de primer plano de
  // ESTE proceso y luego pedir el foco a secas.
  public static void AllowFocusChanges() {
    // SPI_SETFOREGROUNDLOCKTIMEOUT(0x2001), valor 0, SPIF_SENDCHANGE(2)
    SystemParametersInfo(0x2001, 0, IntPtr.Zero, 2);
  }
  public static void ReclaimFocus(IntPtr h) {
    BringWindowToTop(h);
    SetForegroundWindow(h);
  }

  // Marcar (o desmarcar) la ventana como "siempre encima".
  // SWP_NOMOVE(0x2)|SWP_NOSIZE(0x1)|SWP_NOACTIVATE(0x10)
  public static void SetTopmost(IntPtr h, bool on) {
    SetWindowPos(h, (IntPtr)(on ? -1 : -2), 0, 0, 0, 0, 0x1 | 0x2 | 0x10);
  }
}
"@

$VK_LEFT=0x25; $VK_UP=0x26; $VK_RIGHT=0x27; $VK_DOWN=0x28; $VK_RET=0x0D

# --- Botones logicos (bits propios, independientes de la via de lectura) ---
$BTN_A=1; $BTN_B=2; $BTN_START=4; $BTN_LB=8; $BTN_RB=16
$BTN_BACK=32; $BTN_L3=64; $BTN_R3=128

# --- Combinaciones (hay que MANTENERLAS pulsadas, para no dispararlas sin querer) ---
$COMBO_MS = 1200
# Cerrar el TV: pulsar los DOS joysticks a la vez. Se eligieron los joysticks
# porque no hacen nada mas por si solos: es casi imposible darle sin querer.
$COMBO_CERRAR    = ($BTN_L3 -bor $BTN_R3)
# Reiniciar el TV: Back(View) + Start. Sirve sobre todo para RECUPERAR EL AUDIO
# cuando conectas unos auriculares Bluetooth con el TV ya abierto (el emulador
# agarra la salida de audio al arrancar y no la suelta; ver LEEME).
$COMBO_REINICIAR = ($BTN_BACK -bor $BTN_START)

# --- Estructuras reutilizadas en el bucle ---
$xs = New-Object GP+XSTATE
$ex = New-Object GP+JOYINFOEX
$ex.dwSize  = [System.Runtime.InteropServices.Marshal]::SizeOf($ex)
$ex.dwFlags = 0xFF   # JOY_RETURNALL

# ---------------------------------------------------------------------------
# Deteccion de la via de lectura y del slot del mando
# ---------------------------------------------------------------------------
# XInput tiene prioridad: es lo que usan la Legion Go y los mandos modernos, y
# ahi el indice de los botones es fijo (no hay que adivinar el mapeo).
# OJO: no vale quedarse con el primer slot que diga "conectado". Algunos equipos
# (la Legion Go entre ellos) exponen slots FANTASMA que responden que si, pero
# no reportan nunca nada. Si el puente se ancla ahi, el mando parece muerto.
# XInput lleva un contador de paquete que solo avanza cuando el mando manda
# algo: un slot con paquete != 0 YA ha reportado estado, asi que ese es el bueno.
function Find-XPad {
  $primero = -1
  for ($i = 0; $i -lt 4; $i++) {
    $s = New-Object GP+XSTATE
    if ([GP]::XGet($i, [ref]$s) -eq 0) {
      if ($primero -lt 0) { $primero = $i }
      if ($s.dwPacket -ne 0) { return $i }
    }
  }
  return $primero   # ninguno con actividad: se prueba con el primero
}
# winmm: el primero que responda con ejes NO pegados a 0 (un gamepad en reposo
# tiene los ejes centrados ~32767; los slots fantasma devuelven X=0).
function Find-JPad {
  for ($id = 0; $id -lt 8; $id++) {
    $t = New-Object GP+JOYINFOEX
    $t.dwSize  = [System.Runtime.InteropServices.Marshal]::SizeOf($t)
    $t.dwFlags = 0xFF
    if ([GP]::joyGetPosEx($id, [ref]$t) -eq 0 -and $t.dwXpos -gt 4000) { return $id }
  }
  return -1
}

# Permitir que este proceso pueda devolverle el foco al TV (ver AllowFocusChanges)
[GP]::AllowFocusChanges() | Out-Null

$src = ''      # 'x' = XInput, 'j' = winmm
$padId = -1
Log "config: nav=$navMode escalador=$escalador"
function Detect-Pad {
  $i = Find-XPad
  if ($i -ge 0) { $script:src = 'x'; $script:padId = $i; return $true }
  $i = Find-JPad
  if ($i -ge 0) { $script:src = 'j'; $script:padId = $i; return $true }
  return $false
}
Detect-Pad | Out-Null
Log ("mando: fuente={0} slot={1}" -f $(switch ($src) { 'x' {'XInput'} 'j' {'winmm'} default {'NINGUNO detectado'} }), $padId)

# ---------------------------------------------------------------------------
# Lectura normalizada: devuelve @{ dir = 'UL'/'D'/...; btns = mascara logica }
# ---------------------------------------------------------------------------
$XDEAD = 12000    # zona muerta del stick XInput (rango -32768..32767)
$JLO = 12000; $JHI = 53000   # umbrales winmm (rango 0..65535, centro 32767)

function Read-Pad {
  # Sin mando detectado no se lee nada. (Si no se corta aqui, la rama winmm
  # leeria un slot invalido, veria los ejes a 0 y lo interpretaria como
  # "arriba+izquierda" mantenido: el menu se moveria solo.)
  if ($script:src -eq '' -or $script:padId -lt 0) { return $null }

  if ($script:src -eq 'x') {
    if ([GP]::XGet($script:padId, [ref]$script:xs) -ne 0) { return $null }
    $w = [int]$script:xs.Gamepad.wButtons
    $v = ''; $h = ''
    # Cruceta XInput: UP=0x1 DOWN=0x2 LEFT=0x4 RIGHT=0x8
    if     (($w -band 0x1) -ne 0) { $v = 'U' }
    elseif (($w -band 0x2) -ne 0) { $v = 'D' }
    if     (($w -band 0x4) -ne 0) { $h = 'L' }
    elseif (($w -band 0x8) -ne 0) { $h = 'R' }
    if ($v -eq '' -and $h -eq '') {   # sin cruceta: mirar el stick izquierdo
      $lx = [int]$script:xs.Gamepad.sLX; $ly = [int]$script:xs.Gamepad.sLY
      if     ($ly -gt  $script:XDEAD) { $v = 'U' }   # en XInput, +Y es ARRIBA
      elseif ($ly -lt -$script:XDEAD) { $v = 'D' }
      if     ($lx -lt -$script:XDEAD) { $h = 'L' }
      elseif ($lx -gt  $script:XDEAD) { $h = 'R' }
    }
    $b = 0
    if (($w -band 0x1000) -ne 0) { $b = $b -bor $script:BTN_A }      # A
    if (($w -band 0x2000) -ne 0) { $b = $b -bor $script:BTN_B }      # B
    if (($w -band 0x10)   -ne 0) { $b = $b -bor $script:BTN_START }  # Start
    if (($w -band 0x100)  -ne 0) { $b = $b -bor $script:BTN_LB }     # LB
    if (($w -band 0x200)  -ne 0) { $b = $b -bor $script:BTN_RB }     # RB
    if (($w -band 0x20)   -ne 0) { $b = $b -bor $script:BTN_BACK }   # Back / View
    if (($w -band 0x40)   -ne 0) { $b = $b -bor $script:BTN_L3 }     # joystick izq.
    if (($w -band 0x80)   -ne 0) { $b = $b -bor $script:BTN_R3 }     # joystick der.
    return @{ dir = ($v + $h); btns = $b }
  }
  else {
    if ([GP]::joyGetPosEx($script:padId, [ref]$script:ex) -ne 0) { return $null }
    $pov = [int]$script:ex.dwPOV
    $v = ''; $h = ''
    if ($pov -ne 65535 -and $pov -le 36000) {
      switch ($pov) {
        0     { $v='U' }
        4500  { $v='U'; $h='R' }
        9000  { $h='R' }
        13500 { $v='D'; $h='R' }
        18000 { $v='D' }
        22500 { $v='D'; $h='L' }
        27000 { $h='L' }
        31500 { $v='U'; $h='L' }
      }
    }
    if ($v -eq '' -and $h -eq '') {
      $x = [int]$script:ex.dwXpos; $y = [int]$script:ex.dwYpos
      if     ($x -lt $script:JLO) { $h='L' } elseif ($x -gt $script:JHI) { $h='R' }
      if     ($y -lt $script:JLO) { $v='U' } elseif ($y -gt $script:JHI) { $v='D' }
    }
    $w = [int]$script:ex.dwButtons
    $b = 0
    if (($w -band 0x1)   -ne 0) { $b = $b -bor $script:BTN_A }
    if (($w -band 0x2)   -ne 0) { $b = $b -bor $script:BTN_B }
    if (($w -band 0x80)  -ne 0) { $b = $b -bor $script:BTN_START }
    if (($w -band 0x10)  -ne 0) { $b = $b -bor $script:BTN_LB }
    if (($w -band 0x20)  -ne 0) { $b = $b -bor $script:BTN_RB }
    if (($w -band 0x40)  -ne 0) { $b = $b -bor $script:BTN_BACK }   # Back / View
    if (($w -band 0x100) -ne 0) { $b = $b -bor $script:BTN_L3 }     # joystick izq.
    if (($w -band 0x200) -ne 0) { $b = $b -bor $script:BTN_R3 }     # joystick der.
    return @{ dir = ($v + $h); btns = $b }
  }
}

# Enviar direccion. Hay DOS vias:
#  - 'directo': teclas al vuelo con keybd_event. Es instantaneo, pero solo
#    llega si el TV tiene el foco de Windows.
#  - 'adb': se manda el KEYCODE a Android por adb. Tarda un poco mas, pero
#    NO necesita el foco. Es la red de seguridad para cuando la barra de
#    tareas roba el foco (tipico al usar la pantalla tactil de la Legion Go).
function Send-Dir($dir, $via) {
  if ($via -eq 'directo') {
    if ($dir -match 'U') { [GP]::Tap($script:VK_UP) }
    if ($dir -match 'D') { [GP]::Tap($script:VK_DOWN) }
    if ($dir -match 'L') { [GP]::Tap($script:VK_LEFT) }
    if ($dir -match 'R') { [GP]::Tap($script:VK_RIGHT) }
  } else {
    if ($dir -match 'U') { Send-Key 'KEYCODE_DPAD_UP' }
    if ($dir -match 'D') { Send-Key 'KEYCODE_DPAD_DOWN' }
    if ($dir -match 'L') { Send-Key 'KEYCODE_DPAD_LEFT' }
    if ($dir -match 'R') { Send-Key 'KEYCODE_DPAD_RIGHT' }
  }
}

function Send-Key($code) {
  Start-Process -WindowStyle Hidden $script:adb -ArgumentList '-s','emulator-5554','shell','input','keyevent',$code
}

# --- Deteccion de combinaciones mantenidas -------------------------------
# Devuelve $true UNA sola vez, cuando el combo lleva $COMBO_MS pulsado sin
# soltarse. Al soltar se rearma. Asi un roce no cierra el TV.
$comboState = @{}
function Test-Combo([int]$btns, [int]$combo, [DateTime]$now) {
  if (-not $script:comboState.ContainsKey($combo)) {
    $script:comboState[$combo] = @{ desde = [DateTime]::MinValue; disparado = $false }
  }
  $st = $script:comboState[$combo]
  if (($btns -band $combo) -eq $combo) {
    if ($st.desde -eq [DateTime]::MinValue) { $st.desde = $now; $st.disparado = $false }
    if (-not $st.disparado -and ($now - $st.desde).TotalMilliseconds -ge $script:COMBO_MS) {
      $st.disparado = $true
      return $true
    }
  } else {
    $st.desde = [DateTime]::MinValue
    $st.disparado = $false
  }
  return $false
}

function Stop-TV {
  Start-Process -WindowStyle Hidden $script:adb -ArgumentList '-s','emulator-5554','emu','kill' -Wait
}

function Restart-TV {
  # Cerrar y volver a lanzar el TV entero. Reabrir el emulador es lo que hace
  # que vuelva a coger la salida de audio actual (p.ej. tus auriculares BT).
  Stop-TV
  # Esperar a que desaparezca de verdad antes de relanzar, o el lanzador creera
  # que sigue vivo y no arrancara uno nuevo.
  $limite = (Get-Date).AddSeconds(30)
  do {
    Start-Sleep -Milliseconds 500
    $sigue = (& $script:adb devices 2>$null) -match 'emulator-5554'
  } until ((-not $sigue) -or ((Get-Date) -gt $limite))
  Start-Process "$env:WINDIR\System32\wscript.exe" `
    -ArgumentList """$env:USERPROFILE\.android\android-tv-launch.vbs"""
}

# --- Estado previo para detectar flancos ---
$prevDir    = ''
$nextRepeat = [DateTime]::MinValue
$prevBtns   = 0
$volDir     = 0
$nextVol    = [DateTime]::MinValue
$loopCount  = 0
$emuGone    = 0
$nextHide     = [DateTime]::MinValue   # proxima revision de la barra de Qt
$nextWinCheck = [DateTime]::MinValue   # proxima revision de foco/siempre-encima
$fgCacheH     = [IntPtr]::Zero         # ultima ventana con foco clasificada
$fgCacheVia   = 'nada'
$ultimaActividad = Get-Date            # ultima vez que el mando reporto algo
$nextRedetect    = (Get-Date).AddSeconds(10)
$vistoAlgunaVez  = $false              # para registrar la primera pulsacion
$REPEAT_FIRST = 320   # ms hasta la primera repeticion
$REPEAT_RATE  = 150   # ms entre repeticiones

while ($true) {
  $loopCount++

  # Cada ~1 s comprobar si el emulador sigue vivo; si no, salir
  if (($loopCount % 60) -eq 0) {
    $alive = (& $adb devices 2>$null) -match 'emulator-5554'
    if (-not $alive) { $emuGone++ } else { $emuGone = 0 }
    if ($emuGone -ge 2) { break }
  }

  # Cada ~2 s, volver a esconder la barra de controles de Qt si reaparecio.
  # Va antes de leer el mando a proposito: asi sigue vigilando aunque no haya
  # ningun mando conectado.
  # OJO: por TIEMPO, no por numero de vueltas. Sin mando conectado cada vuelta
  # tarda ~300 ms (reintenta detectarlo) y contar vueltas retrasaba esto varios
  # segundos.
  $ahoraTick = Get-Date
  if ($ahoraTick -ge $nextHide -and [GP]::EmuFocused()) {
    [GP]::HideToolbars()
    $nextHide = $ahoraTick.AddMilliseconds(2000)
  }

  # --- En que estado esta el foco ------------------------------------------
  # 'directo' -> el TV tiene el foco: teclas al vuelo (rapido) y "siempre
  #              encima", de modo que la barra de tareas no lo tape.
  # 'adb'     -> se puso delante la BARRA DE TAREAS (tipico al tocar la
  #              pantalla). No es un cambio de programa: se sigue manejando el
  #              TV por adb (no necesita foco) y se intenta recuperarlo.
  # 'nada'    -> Alt+Tab, vista de tareas u otro programa: manda el usuario.
  #              Se QUITA el "siempre encima" y el puente no toca nada, para
  #              que puedas trabajar con normalidad y ver la barra de tareas.
  if ([GP]::EmuFocused()) {
    $via = 'directo'
  } else {
    $fgw = [GP]::GetForegroundWindow()
    # Clasificar una ventana cuesta (hay que mirar su proceso), asi que se
    # recuerda el resultado: mientras no cambie la ventana con el foco, se
    # reutiliza. Si no, esto se haria 60 veces por segundo.
    if ($fgw -eq $fgCacheH) {
      $via = $fgCacheVia
    } else {
      if ([GP]::IsTaskbarWindow($fgw)) {
        $via = 'adb'
      } else {
        # Si el que tiene el foco es Magpie (el reescalador), el TV SIGUE en
        # pantalla: es su ventana la que lo esta mostrando ampliado. Asi que el
        # mando debe seguir funcionando, por adb (que no depende del foco).
        $via = 'nada'
        $fgPid = 0
        [void][GP]::GetWindowThreadProcessId($fgw, [ref]$fgPid)
        if ($fgPid -ne 0) {
          $pr = Get-Process -Id $fgPid -ErrorAction SilentlyContinue
          if ($pr -and $pr.ProcessName -eq 'Magpie') { $via = 'magpie' }
        }
      }
      $fgCacheH = $fgw
      $fgCacheVia = $via
    }
  }

  # Mantenimiento de la ventana (cada ~0,5 s reales)
  if ($ahoraTick -ge $nextWinCheck) {
    $nextWinCheck = $ahoraTick.AddMilliseconds(500)
    $emuWin = [GP]::FindEmu()
    if ($emuWin -ne [IntPtr]::Zero) {
      if ($via -eq 'magpie') {
        # Magpie esta mostrando el TV ampliado: NO tocar la ventana. Si le
        # pusieramos "siempre encima" al emulador, taparia a Magpie.
      } elseif ($via -eq 'nada') {
        # Alt+Tab u otra aplicacion: quitar el "siempre encima" y NO pelear por
        # el foco. Asi el TV se queda detras como una ventana normal.
        [GP]::SetTopmost($emuWin, $false)
      } else {
        # En modo escalador se QUITA el "siempre encima" (no basta con no
        # ponerlo: puede venir puesto de un arranque anterior y taparia a
        # Magpie). Fuera de ese modo, se pone para que no asome la barra.
        [GP]::SetTopmost($emuWin, (-not $escalador))
        # Intento de recuperar el foco SOLO cuando lo tiene la barra de tareas.
        # Windows puede negarselo a un proceso en segundo plano; por eso NO se
        # depende de esto: si falla, el mando sigue yendo por la via 'adb'.
        if ($via -eq 'adb') { [GP]::ReclaimFocus($emuWin) }
      }
    }
  }

  $p = Read-Pad
  if ($null -eq $p) {              # mando desconectado: reintentar deteccion
    Start-Sleep -Milliseconds 300
    Detect-Pad | Out-Null
    continue
  }

  # --- Vigilancia de "mando mudo" ------------------------------------------
  # Si el slot elegido resulta ser un fantasma, la lectura NUNCA falla (contesta
  # ceros siempre), asi que el reintento de arriba no salta nunca. Por eso: si
  # pasan 10 s sin ver NADA, se vuelve a buscar; Find-XPad ya prefiere el slot
  # que tenga actividad, asi que en cuanto pulses algo se enganchara al bueno.
  if ($p.dir -ne '' -or $p.btns -ne 0) {
    $ultimaActividad = Get-Date
    if (-not $vistoAlgunaVez) {
      $vistoAlgunaVez = $true
      Log ("primera actividad del mando: fuente={0} slot={1} dir='{2}' btns={3}" -f $src, $padId, $p.dir, $p.btns)
    }
  }
  if ((Get-Date) -ge $nextRedetect) {
    $nextRedetect = (Get-Date).AddSeconds(10)
    if (((Get-Date) - $ultimaActividad).TotalSeconds -ge 10) {
      $antes = "$src$padId"
      Detect-Pad | Out-Null
      if ("$src$padId" -ne $antes) { Log "sin actividad: cambio de mando $antes -> $src$padId" }
    }
  }

  if ($via -eq 'nada') {
    $prevDir = ''; $prevBtns = $p.btns
    Start-Sleep -Milliseconds 40; continue
  }

  # --- Direccion (cruceta/stick) con auto-repeticion ---
  # En modo 'emulador' no se toca: el propio emulador ya reenvia el mando y
  # duplicar la entrada hacia que el foco saltase de dos en dos.
  if ($navMode -ne 'emulador') {
    if ($p.dir -ne '') {
      if ($p.dir -ne $prevDir) {
        Send-Dir $p.dir $via
        $prevDir = $p.dir
        $nextRepeat = (Get-Date).AddMilliseconds($REPEAT_FIRST)
      } elseif ((Get-Date) -ge $nextRepeat) {
        Send-Dir $p.dir $via
        $nextRepeat = (Get-Date).AddMilliseconds($REPEAT_RATE)
      }
    } else {
      $prevDir = ''
    }
  }

  $btns = [int]$p.btns
  $pressed = $btns -band (-bnot $prevBtns)
  $ahora = Get-Date

  # --- Combinaciones mantenidas (se comprueban ANTES que los botones sueltos) ---
  if (Test-Combo $btns $COMBO_CERRAR $ahora) {
    Stop-TV
    break                      # el puente se cierra con el TV
  }
  if (Test-Combo $btns $COMBO_REINICIAR $ahora) {
    Restart-TV
    break                      # el TV nuevo arrancara su propio puente
  }

  # --- Botones (flanco de pulsacion) ---
  if ($navMode -ne 'emulador') {
    if (($pressed -band $BTN_A) -ne 0) {                             # A -> OK
      if ($via -eq 'directo') { [GP]::Tap($VK_RET) } else { Send-Key 'KEYCODE_DPAD_CENTER' }
    }
    if (($pressed -band $BTN_B) -ne 0) { Send-Key 'KEYCODE_BACK' }   # B -> atras
  }
  # Start -> Home, pero NO si Back esta pulsado: esa es la combinacion de
  # reinicio y no queremos que ademas salte al menu de Android.
  if (($pressed -band $BTN_START) -ne 0 -and ($btns -band $BTN_BACK) -eq 0) {
    Send-Key 'KEYCODE_HOME'
  }
  $prevBtns = $btns

  # --- Volumen (LB baja / RB sube) con repeticion al mantener ---
  # Esto se envia SIEMPRE, tambien en modo 'emulador': el emulador no reenvia
  # los bumpers como volumen.
  $volNow = 0
  if     (($btns -band $BTN_LB) -ne 0) { $volNow = -1 }
  elseif (($btns -band $BTN_RB) -ne 0) { $volNow =  1 }
  if ($volNow -ne 0) {
    $fire = $false
    if ($volNow -ne $volDir) { $fire = $true; $nextVol = (Get-Date).AddMilliseconds(400) }
    elseif ((Get-Date) -ge $nextVol) { $fire = $true; $nextVol = (Get-Date).AddMilliseconds(250) }
    if ($fire) {
      Send-Key $(if ($volNow -gt 0) { 'KEYCODE_VOLUME_UP' } else { 'KEYCODE_VOLUME_DOWN' })
    }
    $volDir = $volNow
  } else { $volDir = 0 }

  Start-Sleep -Milliseconds 16
}

Log "el puente termina (el TV ya no esta)"
$mutex.ReleaseMutex()
