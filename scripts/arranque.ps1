# Cambia el modo de arranque del Android TV.
#   -Modo rapido -> usa instantanea: arranca en segundos y Android reanuda ya
#                   asentado (mejor audio desde el principio). Si la instantanea
#                   falla, el lanzador la borra y arranca en frio solo.
#   -Modo seguro -> arranque en frio siempre (lo de antes): ~30 s, sin riesgo.
param([ValidateSet('rapido','seguro')][string]$Modo = 'rapido')
$ErrorActionPreference = 'Stop'
$tvIni = "$env:USERPROFILE\.android\tv.ini"
$lineas = @()
if (Test-Path $tvIni) { $lineas = @(Get-Content $tvIni | Where-Object { $_ -notmatch '^\s*arranque\s*=' }) }
$lineas += "arranque=$Modo"
Set-Content -Path $tvIni -Value $lineas -Encoding ASCII
Write-Host ""
if ($Modo -eq 'rapido') {
  Write-Host "  ARRANQUE RAPIDO activado." -ForegroundColor Green
  Write-Host "  El TV abrira en segundos y Android reanudara ya asentado," -ForegroundColor Green
  Write-Host "  que es lo que deberia quitar el mal audio de los primeros minutos." -ForegroundColor Green
  Write-Host ""
  Write-Host "  Si alguna vez se quedara en negro, NO hay que hacer nada: el" -ForegroundColor Cyan
  Write-Host "  lanzador lo detecta a los 90 s, borra la instantanea y arranca" -ForegroundColor Cyan
  Write-Host "  en frio solo. Esa vez tardara mas, las siguientes no." -ForegroundColor Cyan
} else {
  Write-Host "  ARRANQUE SEGURO (en frio siempre)." -ForegroundColor Green
  Write-Host "  ~30 s cada vez, sin instantaneas." -ForegroundColor Green
}
Write-Host ""
Write-Host ("  tv.ini: " + ((Get-Content $tvIni) -join '  |  ')) -ForegroundColor DarkGray
Write-Host ""
