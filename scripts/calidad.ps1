# Mide la calidad REAL del ultimo video reproducido en el Android TV:
# resolucion, codec, bitrate y cortes. Sirve para comparar canales, listas o
# servidores con datos en vez de "a ojo".
$ErrorActionPreference = 'SilentlyContinue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Calidad del video que se esta viendo" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

if (-not ((& $adb devices) -match 'emulator-5554')) {
  Write-Host "  El TV no esta abierto. Abrelo, pon un canal 20-30 segundos y vuelve." -ForegroundColor Red
  Read-Host "Enter para salir"; exit
}

$raw = & $adb -s emulator-5554 shell dumpsys media.metrics 2>$null
# Quedarse con las entradas de VIDEO que ademas tengan datos de REPRODUCCION.
# Android registra tambien codecs efimeros (miniaturas, vistas previas del
# sistema) que no traen bitrate ni duracion: si se cogen, salen datos vacios.
$todos  = @($raw -split '\r?\n' | Where-Object { $_ -match 'mediacodec\.mode=video' -and $_ -match 'mediacodec\.width=' })
$videos = @($todos | Where-Object { $_ -match 'playback-duration-sec=([1-9]\d*)' })
if ($videos.Count -eq 0) {
  Write-Host ""
  if ($todos.Count -gt 0) {
    Write-Host "  Hay video, pero aun sin datos suficientes para medir el bitrate." -ForegroundColor Yellow
    Write-Host "  Deja el canal reproduciendo al menos 20-30 segundos SEGUIDOS y" -ForegroundColor Yellow
    Write-Host "  vuelve a ejecutar esto sin cerrar el TV." -ForegroundColor Yellow
  } else {
    Write-Host "  Todavia no hay video medido." -ForegroundColor Yellow
    Write-Host "  Reproduce un canal o pelicula 20-30 segundos y vuelve a ejecutar esto." -ForegroundColor Yellow
  }
  Read-Host "Enter para salir"; exit
}

function Val($txt, $clave) {
  $m = [regex]::Match($txt, [regex]::Escape($clave) + '=([^,\)]+)')
  if ($m.Success) { return $m.Groups[1].Value.Trim() } else { return $null }
}

# El ultimo de la lista es el mas reciente
$v = $videos[-1]
$w    = Val $v 'android.media.mediacodec.width'
$h    = Val $v 'android.media.mediacodec.height'
$mime = Val $v 'android.media.mediacodec.mime'
$cod  = Val $v 'android.media.mediacodec.codec'
$byt  = Val $v 'android.media.mediacodec.video.input.bytes'
$secs = Val $v 'android.media.mediacodec.playback-duration-sec'
$fps  = Val $v 'android.media.mediacodec.framerate-actual'
$drop = Val $v 'android.media.mediacodec.frames-dropped'
$frz  = Val $v 'android.media.mediacodec.freeze-count'
$jud  = Val $v 'android.media.mediacodec.judder-count'

Write-Host ""
Write-Host ("  Resolucion : {0}x{1}" -f $w, $h) -ForegroundColor White
Write-Host ("  Codec      : {0}  ({1})" -f $mime, $cod) -ForegroundColor White
if ($cod -like '*goldfish*') {
  Write-Host "               ^ decodificado por SOFTWARE (cuesta CPU)" -ForegroundColor DarkYellow
}
if ($fps) { Write-Host ("  Fotogramas : {0:N1} por segundo" -f [double]$fps) -ForegroundColor White }

$mbps = $null
if ($byt -and $secs -and [double]$secs -gt 0) {
  $mbps = [math]::Round(([double]$byt * 8) / ([double]$secs * 1000000), 2)
  Write-Host ""
  Write-Host ("  BITRATE    : {0} Mbps   <<< ESTE ES EL DATO CLAVE" -f $mbps) -ForegroundColor Cyan
}

# Referencia de lo que hace falta segun resolucion y codec
if ($mbps -and $h) {
  $alto = [int]$h
  $esHevc = ($mime -like '*hevc*') -or ($mime -like '*265*')
  $minimo = if ($alto -ge 1080) { if ($esHevc) { 4.0 } else { 6.0 } }
            elseif ($alto -ge 720) { if ($esHevc) { 2.5 } else { 4.0 } }
            else { if ($esHevc) { 1.2 } else { 2.0 } }
  Write-Host ("  Recomendado para {0}p en este codec: ~{1} Mbps" -f $alto, $minimo) -ForegroundColor DarkGray
  Write-Host ""
  if ($mbps -lt ($minimo * 0.6)) {
    Write-Host "  VEREDICTO: bitrate MUY BAJO. De aqui vienen los bloques grandes." -ForegroundColor Red
    Write-Host "  Ningun filtro ni reescalador arregla esto: busca otro servidor" -ForegroundColor Red
    Write-Host "  o version del canal (FHD/HD) y vuelve a medir para comparar." -ForegroundColor Red
  } elseif ($mbps -lt $minimo) {
    Write-Host "  VEREDICTO: bitrate justo. Se notaran bloques en escenas con movimiento." -ForegroundColor Yellow
  } else {
    Write-Host "  VEREDICTO: bitrate correcto para esa resolucion." -ForegroundColor Green
  }
}

Write-Host ""
Write-Host "  --- fluidez ---" -ForegroundColor White
Write-Host ("  Fotogramas perdidos : {0}" -f $drop)
Write-Host ("  Congelaciones       : {0}" -f $frz)
Write-Host ("  Tirones (judder)    : {0}" -f $jud)
if (([int]$frz -gt 3) -or ([int]$drop -gt 5)) {
  Write-Host "  La reproduccion va JUSTA. Esto tambien provoca los chasquidos de audio." -ForegroundColor Yellow
  Write-Host "  Ayuda: cerrar programas pesados, modo Rendimiento, o subir el buffer" -ForegroundColor Yellow
  Write-Host "  en los ajustes de la app si los tiene." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  CONSEJO: mide varios canales y servidores y compara los Mbps." -ForegroundColor Cyan
Write-Host "  Es la forma objetiva de saber cual te da mejor imagen." -ForegroundColor Cyan
Write-Host ""
Read-Host "Enter para salir"
