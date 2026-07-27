# Recoge en UN fichero todo lo necesario para diagnosticar el mando desde otro
# equipo. Pensado para ejecutarlo en la Legion Go CON EL TV ABIERTO y mandar el
# .txt resultante.
$ErrorActionPreference = 'SilentlyContinue'
$out = "$([Environment]::GetFolderPath('Desktop'))\informe-androidtv.txt"
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
$adb = "$sdk\platform-tools\adb.exe"
$home_ = "$env:USERPROFILE\.android"
$L = New-Object System.Collections.Generic.List[string]
function W($s) { $script:L.Add($s) }

W "INFORME ANDROID TV  -  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "equipo: $env:COMPUTERNAME   usuario: $env:USERNAME"
W "Windows: $((Get-CimInstance Win32_OperatingSystem).Caption) build $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
W "PowerShell: $($PSVersionTable.PSVersion)"
W ""

W "== VERSION DE LOS SCRIPTS INSTALADOS =="
foreach ($f in 'android-tv-launch.ps1','android-tv-gamepad.ps1','diagnostico.ps1','escalador.ps1','calidad.ps1') {
  $p = Join-Path $home_ $f
  if (Test-Path $p) {
    $i = Get-Item $p
    W ("  {0,-26} {1}  {2} bytes" -f $f, $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $i.Length)
  } else { W ("  {0,-26} NO EXISTE" -f $f) }
}
# Marcadores para saber si tiene las versiones nuevas
$g = Get-Content (Join-Path $home_ 'android-tv-gamepad.ps1') -Raw
W ""
W "  soporte XInput      : $([bool]($g -match 'XInputGetState'))"
W "  respaldo por adb    : $([bool]($g -match "via -eq 'directo'"))"
W "  combos L3+R3        : $([bool]($g -match 'COMBO_CERRAR'))"
W "  registro puente.log : $([bool]($g -match 'puente\.log'))"
W ""

W "== CONFIGURACION =="
foreach ($f in 'tv.ini','gamepad.ini') {
  $p = Join-Path $home_ $f
  if (Test-Path $p) { W "  ${f}: $((Get-Content $p) -join ' | ')" } else { W "  ${f}: no existe (valores por defecto)" }
}
$cfg = Join-Path $home_ 'avd\AndroidTV.avd\config.ini'
if (Test-Path $cfg) {
  W "  AVD:"
  Get-Content $cfg | Where-Object { $_ -match '^(hw\.lcd|hw\.screen|hw\.dPad|hw\.keyboard|hw\.cpu|hw\.ramSize|hw\.gpu)' } | ForEach-Object { W "    $_" }
}
W ""

W "== ESTADO AHORA MISMO =="
$tv = (& $adb devices 2>$null) -match 'emulator-5554'
W "  TV abierto: $([bool]$tv)"
$pu = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*android-tv-gamepad*' -and $_.CommandLine -notlike '*Win32_Process*' })
W "  puente corriendo: $($pu.Count) instancia(s)"
W "  Magpie corriendo: $(@(Get-Process Magpie -ErrorAction SilentlyContinue).Count)"
W ""

W "== MANDO =="
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class INF {
  [StructLayout(LayoutKind.Sequential)] public struct XPAD { public ushort wButtons; public byte bLT,bRT; public short sLX,sLY,sRX,sRY; }
  [StructLayout(LayoutKind.Sequential)] public struct XSTATE { public uint dwPacket; public XPAD Gamepad; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] private static extern uint X14(uint i, ref XSTATE s);
  [DllImport("xinput9_1_0.dll", EntryPoint="XInputGetState")] private static extern uint X910(uint i, ref XSTATE s);
  private static int dll = 0;
  public static string DllName(){ return dll==1?"xinput1_4":(dll==2?"xinput9_1_0":"ninguna"); }
  public static uint XGet(uint i, ref XSTATE s){
    if(dll==0){ try{ X14(0, ref s); dll=1; } catch { try{ X910(0, ref s); dll=2; } catch { dll=-1; } } }
    if(dll==1){ try{ return X14(i, ref s); } catch { return 1; } }
    if(dll==2){ try{ return X910(i, ref s); } catch { return 1; } }
    return 1;
  }
  [StructLayout(LayoutKind.Sequential)] public struct JOY { public uint dwSize,dwFlags,dwX,dwY,dwZ,dwR,dwU,dwV,dwButtons,dwButtonNumber,dwPOV,r1,r2; }
  [DllImport("winmm.dll")] public static extern uint joyGetPosEx(uint id, ref JOY pi);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public static string FgT(){ StringBuilder s=new StringBuilder(256); GetWindowText(GetForegroundWindow(),s,256); return s.ToString(); }
  public static string FgC(){ StringBuilder s=new StringBuilder(256); GetClassName(GetForegroundWindow(),s,256); return s.ToString(); }
}
"@
# OJO: hay que SONDEAR antes de preguntar el nombre de la DLL; si no, siempre
# responde "ninguna" porque aun no ha decidido cual usar.
$hayX = $false
for ($i = 0; $i -lt 4; $i++) {
  $s = New-Object INF+XSTATE
  if ([INF]::XGet($i, [ref]$s) -eq 0) {
    $hayX = $true
    # dwPacket es el dato CLAVE: solo avanza cuando el mando reporta estado.
    # Un slot conectado con paquete=0 es un FANTASMA, no el mando de verdad.
    $nota = if ($s.dwPacket -eq 0) { '  <<< paquete=0: SLOT FANTASMA, no reporta nada' } else { '  (reporta actividad: mando real)' }
    W "  XInput slot ${i}: PRESENTE  paquete=$($s.dwPacket)  botones=0x$('{0:X}' -f $s.Gamepad.wButtons) stick=($($s.Gamepad.sLX),$($s.Gamepad.sLY))$nota"
  }
}
W "  DLL XInput usada: $([INF]::DllName())"
if (-not $hayX) { W "  XInput: NINGUN mando detectado en los 4 slots" }
for ($id = 0; $id -lt 8; $id++) {
  $t = New-Object INF+JOY
  $t.dwSize = [System.Runtime.InteropServices.Marshal]::SizeOf($t); $t.dwFlags = 0xFF
  if ([INF]::joyGetPosEx($id, [ref]$t) -eq 0) { W "  winmm slot ${id}: PRESENTE  X=$($t.dwX) Y=$($t.dwY) POV=$($t.dwPOV) btn=0x$('{0:X}' -f $t.dwButtons)" }
}
W ""

W "== VENTANAS =="
W "  ventana con foco: clase='$([INF]::FgC())' titulo='$([INF]::FgT())'"
if ($tv) {
  W "  --- ventanas del emulador ---"
  Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue | ForEach-Object { W "    proceso qemu PID $($_.Id)" }
}
W ""

W "== puente.log (ultimas 25 lineas) =="
$lg = Join-Path $home_ 'puente.log'
if (Test-Path $lg) { Get-Content $lg -Tail 25 | ForEach-Object { W "  $_" } } else { W "  no existe" }
W ""

if ($tv) {
  W "== ANDROID =="
  W "  foco: $(& $adb -s emulator-5554 shell 'dumpsys window | grep -m1 mCurrentFocus' 2>$null)"
  W "  actividad: $(& $adb -s emulator-5554 shell 'dumpsys activity activities | grep -m1 topResumedActivity' 2>$null)"
  W "  wm size: $(& $adb -s emulator-5554 shell wm size 2>$null)"
  W "  dispositivos de entrada que ve Android:"
  (& $adb -s emulator-5554 shell "dumpsys input | grep -E '^  Device [0-9]+:'" 2>$null) | ForEach-Object { W "    $_" }
}

$L | Set-Content -Path $out -Encoding UTF8
Write-Host ""
Write-Host "  Informe guardado en el ESCRITORIO:" -ForegroundColor Green
Write-Host "    $out" -ForegroundColor Green
Write-Host ""
Write-Host "  Mandame ese fichero." -ForegroundColor Cyan
Write-Host ""
