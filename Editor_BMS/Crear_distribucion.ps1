# Crea el zip para distribuir la traduccion completa (instalador + idiomas + editor).
# NO borra ni cambia nada de la carpeta: copia lo necesario a una carpeta temporal y la comprime
# junto al paquete, como Traduccion_BMS_<version>.zip.
# Se deja fuera lo de cada equipo:
#   - Data_ORIGINAL (originales del juego: los crea el instalador en cada equipo), Registro.log
#   - copias de seguridad y trabajo del editor (Respaldo, Editados, Originales, Editor_BMS_ver.txt)
#   - el entorno de voces (venv, venv_cb, ffmpeg, modelos), cachés, audios intermedios (Voces\Idiomas),
#     pruebas, .tlk montados sueltos y los ajustes personales (voces.json)
#   - zips anteriores
# Los Falcon.tlk guardados en el instalador (Idiomas\<COD>\Ficheros) SI van: son la traduccion.

$ErrorActionPreference = 'Stop'
$Editor = Split-Path -Parent $MyInvocation.MyCommand.Path
$Raiz   = Split-Path -Parent $Editor

function Fallo($m) { Write-Host ''; Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# --- comprobaciones ---
if (-not (Test-Path (Join-Path $Raiz 'Instalador\Instalador.ps1'))) { Fallo "no encuentro Instalador\Instalador.ps1 en $Raiz" }
$bat = Join-Path $Raiz 'Instalar.bat'
if (-not (Test-Path $bat)) { Write-Host 'Aviso: no hay Instalar.bat junto al instalador.' -ForegroundColor Yellow }

$version = ''
$fv = Join-Path $Raiz 'version.txt'
if (Test-Path $fv) { $version = ((Get-Content $fv -TotalCount 1) -replace '[^\w\.\-]', '_').Trim('_') }
$nombre = if ($version) { "Traduccion_BMS_$version.zip" } else { 'Traduccion_BMS_' + (Get-Date -Format 'yyyy-MM-dd') + '.zip' }
$Zip = Join-Path (Split-Path -Parent $Raiz) $nombre

Write-Host "Paquete:  $Raiz"
Write-Host "Version:  $(if ($version) { $version } else { '(sin version.txt)' })"
Write-Host ''
Write-Host 'Idiomas incluidos:'
$idiomas = @(Get-ChildItem (Join-Path $Raiz 'Idiomas') -Directory -ErrorAction SilentlyContinue)
if (-not $idiomas.Count) { Fallo 'no hay carpeta Idiomas con ningun idioma' }
foreach ($d in $idiomas) {
    $csv = Join-Path $d.FullName 'Archivos.csv'
    $fic = Join-Path $d.FullName 'Ficheros'
    $n = if (Test-Path $fic) { @(Get-ChildItem $fic -Recurse -File).Count } else { 0 }
    $l = if (Test-Path $csv) { @(Get-Content $csv | Select-Object -Skip 1 | Where-Object { $_.Trim() }).Count } else { 0 }
    $tlk = if (Test-Path $fic) { @(Get-ChildItem $fic -Recurse -File -Filter '*.tlk').Count } else { 0 }
    Write-Host ("  {0,-4} {1} lineas en Archivos.csv, {2} ficheros ({3} Falcon.tlk con voces)" -f $d.Name, $l, $n, $tlk)
    if (-not (Test-Path $csv)) { Write-Host "       Aviso: $($d.Name) no tiene Archivos.csv" -ForegroundColor Yellow }
}
Write-Host ''

# --- copia limpia ---
$Tmp  = Join-Path $env:TEMP 'Traduccion_BMS_paquete'
$Dest = Join-Path $Tmp (Split-Path -Leaf $Raiz)
if (Test-Path $Tmp) { Remove-Item $Tmp -Recurse -Force }
Write-Host 'Copiando (sin lo de este equipo)...'

$xd = @('Data_ORIGINAL', 'Respaldo', 'Editados', 'Originales', 'venv', 'venv_cb', '.venv', 'ffmpeg', 'modelos',
        'cache', 'cache_cb', 'wav_es', 'prueba', 'pruebas', '__pycache__', '.git',
        (Join-Path $Editor 'Voces\Idiomas'))
$xf = @('Registro.log', 'voces.json', 'Editor_BMS_ver.txt', 'Mapa_*.origen.txt', '*.latentes.pt', '*.chatterbox.pt',
        'Falcon_*.tlk', 'montado_*.json', '*.tmp', '*.pyc', '*.bak', '*.zip', (Join-Path $Raiz 'Idiomas\actual.txt'))
$ra = @($Raiz, $Dest, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1', '/XD') + $xd + @('/XF') + $xf
& robocopy.exe @ra | Out-Null
if ($LASTEXITCODE -ge 8) { Fallo "robocopy termino con codigo $LASTEXITCODE" }

$todo = @(Get-ChildItem $Dest -Recurse -File)
$mb = [math]::Round((($todo | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host "  $($todo.Count) ficheros, $mb MB sin comprimir"

# --- zip ---
Write-Host "Comprimiendo en $Zip ..."
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($Dest, $Zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Remove-Item $Tmp -Recurse -Force

$zmb = [math]::Round((Get-Item $Zip).Length / 1MB, 1)
Write-Host ''
Write-Host 'Hecho:' -ForegroundColor Green
Write-Host "  $Zip  ($zmb MB)"
Write-Host ''
Write-Host 'Quien lo reciba: descomprimir, cerrar Falcon BMS y ejecutar Instalar.bat.'
Write-Host 'Para editar o generar voces: Editor_BMS\Editor_BMS.bat (las voces piden "Preparar entorno..." la primera vez).'
