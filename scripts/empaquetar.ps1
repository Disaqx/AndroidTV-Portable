# ============================================================================
#  Construye un ZIP del paquete para pasarselo a alguien directamente.
#
#  A DIFERENCIA de lo que se publica en GitHub, este ZIP SI incluye lo que
#  tengas en apps\ y, si esta, sdk.7z. Eso es la diferencia entre compartir
#  una copia con un amigo y redistribuir software de terceros a todo internet:
#  lo primero lo decides tu, lo segundo no nos corresponde.
#
#  Por eso este script vive en el repositorio pero su RESULTADO no: el ZIP se
#  genera fuera de la carpeta del proyecto y nunca se sube.
#
#    EMPAQUETAR.bat              -> ZIP con tus apps, sin el SDK   (~50 MB)
#    EMPAQUETAR.bat -ConSdk      -> ZIP con todo, instala sin internet (~1 GB)
#    EMPAQUETAR.bat -SinApps     -> ZIP limpio, como el de GitHub
# ============================================================================
param(
  [switch]$ConSdk,
  [switch]$SinApps,
  [string]$Destino = ""
)
$ErrorActionPreference = 'Stop'

$pkg = Split-Path $PSScriptRoot -Parent
$nombre = "AndroidTV-Portable"
if (-not $Destino) { $Destino = [Environment]::GetFolderPath('Desktop') }

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Empaquetador Android TV" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# --- Que se incluye --------------------------------------------------------
$apks = @(Get-ChildItem "$pkg\apps\*.apk" -ErrorAction SilentlyContinue)
$sdk  = Test-Path "$pkg\sdk.7z"

Write-Host "  Contenido:" -ForegroundColor Yellow
if ($SinApps -or $apks.Count -eq 0) {
  if ($apks.Count -eq 0 -and -not $SinApps) {
    Write-Host "    apps\  : vacia, no se incluye ninguna" -ForegroundColor DarkGray
  } else {
    Write-Host "    apps\  : excluidas (-SinApps)" -ForegroundColor DarkGray
  }
} else {
  foreach ($a in $apks) {
    Write-Host ("    app    : {0} ({1:N1} MB)" -f $a.Name, ($a.Length/1MB)) -ForegroundColor Green
  }
}
if ($ConSdk) {
  if ($sdk) {
    Write-Host ("    sdk.7z : incluido ({0:N0} MB) - instalara SIN internet" -f ((Get-Item "$pkg\sdk.7z").Length/1MB)) -ForegroundColor Green
  } else {
    Write-Host "    sdk.7z : pediste -ConSdk pero no existe; se omite" -ForegroundColor Yellow
    Write-Host "             el instalador lo bajara de Google en destino" -ForegroundColor DarkGray
  }
} else {
  Write-Host "    sdk.7z : excluido - el instalador lo baja de Google (~1,3 GB)" -ForegroundColor DarkGray
}
Write-Host ""

# --- Preparar la copia -----------------------------------------------------
$stage = Join-Path $env:TEMP "atv-pack-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
$raiz  = Join-Path $stage $nombre
New-Item -ItemType Directory -Force -Path $raiz | Out-Null

try {
  # Se excluye siempre lo que no debe viajar: control de versiones, el
  # reescalador (se descarga solo) y restos de ejecucion.
  $xd = @('.git', '.github', 'tools\magpie')
  $xf = @('.gitignore', '.gitattributes', 'puente.log', 'tv.ini')
  if (-not $ConSdk -or -not $sdk) { $xf += 'sdk.7z' }

  $args = @($pkg, $raiz, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
  if ($xd) { $args += '/XD'; $args += $xd }
  if ($xf) { $args += '/XF'; $args += $xf }
  robocopy @args | Out-Null

  if ($SinApps) {
    Get-ChildItem "$raiz\apps\*.apk" -ErrorAction SilentlyContinue | Remove-Item -Force
  }

  # --- Comprimir -----------------------------------------------------------
  $stamp = Get-Date -Format 'yyyy-MM-dd'
  $sufijo = if ($ConSdk -and $sdk) { '-completo' } elseif ($SinApps) { '-limpio' } else { '' }
  $zip = Join-Path $Destino "$nombre$sufijo-$stamp.zip"
  if (Test-Path $zip) { Remove-Item $zip -Force }

  Write-Host "  Comprimiendo..." -ForegroundColor Yellow
  $7z = "$pkg\tools\7z.exe"
  if (Test-Path $7z) {
    # -mx1 porque sdk.7z y los apk ya vienen comprimidos: apretar mas solo
    # gasta minutos sin ahorrar apenas nada.
    & $7z a -tzip -mx1 -bso0 -bsp0 $zip "$stage\$nombre" | Out-Null
  } else {
    Compress-Archive -Path "$stage\$nombre" -DestinationPath $zip -Force
  }

  if (-not (Test-Path $zip)) { throw "no se genero el ZIP" }
  $mb = (Get-Item $zip).Length / 1MB

  Write-Host ""
  Write-Host "=========================================" -ForegroundColor Green
  Write-Host " LISTO" -ForegroundColor Green
  Write-Host "=========================================" -ForegroundColor Green
  Write-Host ""
  Write-Host ("  {0}" -f $zip) -ForegroundColor White
  Write-Host ("  {0:N1} MB" -f $mb) -ForegroundColor White
  Write-Host ""
  Write-Host "  Pasaselo a quien quieras. Quien lo reciba solo tiene que" -ForegroundColor DarkGray
  Write-Host "  descomprimirlo y ejecutar INSTALAR.bat." -ForegroundColor DarkGray
  if (-not $ConSdk) {
    Write-Host "  Necesitara internet la primera vez (el SDK son ~1,3 GB)." -ForegroundColor DarkGray
  }
  Write-Host ""
  Write-Host "  NO subas este ZIP a un repositorio publico: lleva software" -ForegroundColor Yellow
  Write-Host "  de terceros que no es tuyo para redistribuir." -ForegroundColor Yellow
  Write-Host ""
}
finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
