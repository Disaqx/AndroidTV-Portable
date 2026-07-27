# Diagnostico del Android TV portatil: resolucion detectada + lectura del mando.
# Se ejecuta con el .bat "DIAGNOSTICO.bat". Pulsa Ctrl+C para salir.
$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DG {
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
  // Declarado como IntPtr porque desde PowerShell un $null en un parametro
  // string puede acabar llegando como cadena vacia, y la llamada falla.
  [DllImport("user32.dll", CharSet=CharSet.Ansi, EntryPoint="EnumDisplaySettingsA")]
  private static extern bool EnumDisplaySettingsRaw(IntPtr dev, int mode, ref DEVMODE dm);
  public static bool CurrentMode(ref DEVMODE dm) {
    dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    return EnumDisplaySettingsRaw(IntPtr.Zero, -1 /*ENUM_CURRENT_SETTINGS*/, ref dm);
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct JOYINFOEX {
    public uint dwSize, dwFlags, dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos, dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2;
  }
  [DllImport("winmm.dll")] public static extern uint joyGetPosEx(uint id, ref JOYINFOEX pi);

  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public static string FgTitle() {
    StringBuilder s = new StringBuilder(256); GetWindowText(GetForegroundWindow(), s, 256); return s.ToString();
  }
  public static string FgClass() {
    StringBuilder s = new StringBuilder(256); GetClassName(GetForegroundWindow(), s, 256); return s.ToString();
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct XPAD { public ushort wButtons; public byte bLT, bRT; public short sLX, sLY, sRX, sRY; }
  [StructLayout(LayoutKind.Sequential)]
  public struct XSTATE { public uint dwPacket; public XPAD Gamepad; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] private static extern uint XGet14(uint i, ref XSTATE s);
  [DllImport("xinput9_1_0.dll", EntryPoint="XInputGetState")] private static extern uint XGet910(uint i, ref XSTATE s);
  private static int xDll = 0;
  public static string XDllName() { return xDll == 1 ? "xinput1_4" : (xDll == 2 ? "xinput9_1_0" : "ninguna"); }
  public static uint XGet(uint i, ref XSTATE s) {
    if (xDll == 0) {
      try { XGet14(0, ref s); xDll = 1; }
      catch { try { XGet910(0, ref s); xDll = 2; } catch { xDll = -1; } }
    }
    if (xDll == 1) { try { return XGet14(i, ref s); } catch { return 1; } }
    if (xDll == 2) { try { return XGet910(i, ref s); } catch { return 1; } }
    return 1;
  }
}
"@

Write-Host ""
Write-Host "=== PANTALLA ===" -ForegroundColor Cyan
$logW = [DG]::GetSystemMetrics(0); $logH = [DG]::GetSystemMetrics(1)
[DG]::SetProcessDPIAware() | Out-Null
$awW = [DG]::GetSystemMetrics(0); $awH = [DG]::GetSystemMetrics(1)
$dm = New-Object DG+DEVMODE
$ok = [DG]::CurrentMode([ref]$dm)
Write-Host ("  GetSystemMetrics antes de DPI-aware : {0}x{1}" -f $logW,$logH)
Write-Host ("  GetSystemMetrics despues           : {0}x{1}" -f $awW,$awH)
if ($ok) {
  Write-Host ("  EnumDisplaySettings (FISICA, la buena): {0}x{1} @ {2} Hz" -f $dm.dmPelsWidth,$dm.dmPelsHeight,$dm.dmDisplayFrequency) -ForegroundColor Green
  if ($dm.dmPelsWidth -ne $logW) {
    Write-Host "  -> Hay ESCALADO de Windows activo. Por eso el metodo antiguo se quedaba corto." -ForegroundColor Yellow
  }
} else {
  Write-Host "  EnumDisplaySettings fallo (raro). Se usara GetSystemMetrics." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== AVD INSTALADO ===" -ForegroundColor Cyan
$cfg = "$env:USERPROFILE\.android\avd\AndroidTV.avd\config.ini"
if (Test-Path $cfg) {
  Get-Content $cfg | Select-String '^hw\.lcd\.(width|height|density)=' | ForEach-Object { Write-Host ("  " + $_.Line) }
} else {
  Write-Host "  No existe el AVD (todavia no has instalado)." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== MANDO ===" -ForegroundColor Cyan
$xFound = @()
for ($i = 0; $i -lt 4; $i++) {
  $s = New-Object DG+XSTATE
  if ([DG]::XGet($i, [ref]$s) -eq 0) { $xFound += $i }
}
Write-Host ("  DLL de XInput: {0}" -f [DG]::XDllName())
if ($xFound.Count -gt 0) {
  Write-Host ("  XInput: mando(s) en slot(s) {0}  <- se usara este" -f ($xFound -join ', ')) -ForegroundColor Green
} else {
  Write-Host "  XInput: ningun mando." -ForegroundColor Yellow
}
$jFound = @()
for ($id = 0; $id -lt 8; $id++) {
  $t = New-Object DG+JOYINFOEX
  $t.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf($t); $t.dwFlags = 0xFF
  if ([DG]::joyGetPosEx($id, [ref]$t) -eq 0) { $jFound += ("{0}(X={1})" -f $id,$t.dwXpos) }
}
if ($jFound.Count -gt 0) { Write-Host ("  winmm/DirectInput: slots {0}" -f ($jFound -join ', ')) }
else { Write-Host "  winmm/DirectInput: ninguno." }

if ($xFound.Count -eq 0 -and $jFound.Count -eq 0) {
  Write-Host ""
  Write-Host "  No se detecta ningun mando. Conectalo y vuelve a ejecutar." -ForegroundColor Red
  Read-Host "Pulsa Enter para salir"; exit
}

Write-Host ""
Write-Host "=== PUENTE DEL MANDO ===" -ForegroundColor Cyan
# El puente SOLO corre mientras el TV esta abierto: nace con el y muere con el.
# Por eso lo primero es mirar si el TV esta abierto, o el aviso confunde.
$adbExe = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$tvAbierto = $false
if (Test-Path $adbExe) { $tvAbierto = ((& $adbExe devices 2>$null) -match 'emulator-5554') }

$puente = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.CommandLine -like '*android-tv-gamepad*' -and $_.CommandLine -notlike '*Win32_Process*' })

if (-not $tvAbierto) {
  Write-Host "  El TV NO esta abierto ahora mismo." -ForegroundColor Yellow
  Write-Host "  El puente solo funciona con el TV abierto, asi que es NORMAL que" -ForegroundColor Yellow
  Write-Host "  no aparezca. Para probar el mando de verdad: abre el TV con su" -ForegroundColor Yellow
  Write-Host "  acceso directo, espera a que cargue, y ejecuta esto otra vez." -ForegroundColor Yellow
} elseif ($puente.Count -gt 0) {
  Write-Host ("  TV abierto y puente corriendo ({0} instancia/s). CORRECTO." -f $puente.Count) -ForegroundColor Green
} else {
  Write-Host "  El TV esta abierto pero el puente NO esta corriendo." -ForegroundColor Red
  Write-Host "  Esto SI es un problema: sin el puente el mando no hace nada." -ForegroundColor Red
  Write-Host "  Ejecuta PUENTE-MANUAL.bat para verlo arrancar y leer el error." -ForegroundColor Red
  $log = "$env:USERPROFILE\.android\puente.log"
  if (Test-Path $log) {
    Write-Host "  --- ultimas lineas de puente.log ---" -ForegroundColor DarkGray
    Get-Content $log -Tail 8 | ForEach-Object { Write-Host ("   " + $_) -ForegroundColor DarkGray }
  }
}
$tvIni = "$env:USERPROFILE\.android\gamepad.ini"
if (Test-Path $tvIni) { Write-Host ("  gamepad.ini: " + ((Get-Content $tvIni) -join ' ')) -ForegroundColor DarkGray }

Write-Host ""
Write-Host "=== PRUEBA EN VIVO: pulsa botones del mando ===" -ForegroundColor Cyan
Write-Host "  Comprueba sobre todo que salen L3 y R3 al pulsar los joysticks" -ForegroundColor DarkGray
Write-Host "  (son los que cierran el TV) y BACK/View (reinicia junto a START)." -ForegroundColor DarkGray
Write-Host "  Abajo se ve QUE VENTANA tiene el foco. Si el mando se lee bien aqui" -ForegroundColor DarkGray
Write-Host "  pero el TV no responde, el problema esta en el foco." -ForegroundColor DarkGray
Write-Host "  (Ctrl+C para salir)" -ForegroundColor DarkGray
Write-Host ""
# Se muestran TODOS los slots a la vez, no solo el primero: algunos equipos
# (la Legion Go entre ellos) exponen slots FANTASMA que dicen estar conectados
# pero nunca reportan nada. Asi se ve de un vistazo cual es el mando de verdad.
Write-Host "  Se muestran TODOS los slots. El tuyo es el que CAMBIE al pulsar." -ForegroundColor DarkGray
Write-Host ""
$last = ''
while ($true) {
  $lineas = @()
  for ($i = 0; $i -lt 4; $i++) {
    $s = New-Object DG+XSTATE
    if ([DG]::XGet($i, [ref]$s) -eq 0) {
      $w = [int]$s.Gamepad.wButtons
      $n = @()
      if (($w -band 0x1000) -ne 0) { $n += 'A' }
      if (($w -band 0x2000) -ne 0) { $n += 'B' }
      if (($w -band 0x4000) -ne 0) { $n += 'X' }
      if (($w -band 0x8000) -ne 0) { $n += 'Y' }
      if (($w -band 0x100)  -ne 0) { $n += 'LB' }
      if (($w -band 0x200)  -ne 0) { $n += 'RB' }
      if (($w -band 0x10)   -ne 0) { $n += 'START' }
      if (($w -band 0x20)   -ne 0) { $n += 'BACK' }
      if (($w -band 0x40)   -ne 0) { $n += 'L3' }
      if (($w -band 0x80)   -ne 0) { $n += 'R3' }
      if (($w -band 0x1)    -ne 0) { $n += 'ARRIBA' }
      if (($w -band 0x2)    -ne 0) { $n += 'ABAJO' }
      if (($w -band 0x4)    -ne 0) { $n += 'IZQ' }
      if (($w -band 0x8)    -ne 0) { $n += 'DER' }
      $lineas += ("  XInput[{0}] paq={1,-6} stick=({2},{3})  {4}" -f $i, $s.dwPacket, $s.Gamepad.sLX, $s.Gamepad.sLY, $(if ($n.Count) { $n -join '+' } else { '-' }))
    }
  }
  for ($id = 0; $id -lt 8; $id++) {
    $t = New-Object DG+JOYINFOEX
    $t.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf($t); $t.dwFlags = 0xFF
    if ([DG]::joyGetPosEx($id, [ref]$t) -eq 0) {
      $fant = if ($t.dwXpos -le 4000) { ' <- fantasma (ejes a 0)' } else { '' }
      $lineas += ("  winmm[{0}]  X={1,-6} Y={2,-6} POV={3,-6} btn=0x{4:X}{5}" -f $id, $t.dwXpos, $t.dwYpos, $t.dwPOV, $t.dwButtons, $fant)
    }
  }
  $txt = $lineas -join "`n"
  if ($txt -ne $last) { Clear-Host; Write-Host "PULSA BOTONES - el mando real es el que cambie:`n" -ForegroundColor Cyan; Write-Host $txt; $last = $txt }
  Start-Sleep -Milliseconds 80
}
