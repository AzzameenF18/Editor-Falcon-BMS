# Prepara todo lo necesario para generar las voces de radio en espanol (pestana Voces del Editor BMS):
#   1. Python 3.11 (si no esta, lo descarga de python.org y lo instala solo para este usuario)
#   2. venv en Voces\venv
#   3. PyTorch (con CUDA si hay tarjeta NVIDIA), coqui-tts (XTTS-v2) y scipy
#   4. ffmpeg con libspeex (build de gyan.dev) en Voces\ffmpeg
#   5. Descarga del modelo XTTS-v2 (pide aceptar su licencia CPML, no comercial)
# Se puede volver a ejecutar: lo que ya este bien, lo salta.

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Aqui = $PSScriptRoot
$Venv = Join-Path $Aqui 'venv'
$Py = Join-Path $Venv 'Scripts\python.exe'
$Tmp = Join-Path $env:TEMP 'bms_voces'
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
$TorchVer = '2.8.0'; $CudaIdx = 'https://download.pytorch.org/whl/cu126'

function Paso([string]$t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Bien([string]$t) { Write-Host "    OK  $t" -ForegroundColor Green }
function Mal([string]$t) { Write-Host "    ERROR  $t" -ForegroundColor Red }
function Fin([int]$c) { Write-Host ''; if ($c -eq 0) { Write-Host 'Todo listo. Vuelve al editor y pulsa la rueda (o recarga la pestana Voces).' -ForegroundColor Green } else { Write-Host 'No se ha completado. Revisa el error de arriba.' -ForegroundColor Red }; exit $c }
function Bajar([string]$url, [string]$dst) {
    Write-Host "    Descargando $url"
    try { Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing; return $true } catch { Mal $_.Exception.Message; return $false }
}
function Pip([string[]]$a) { & $Py -m pip @a | Out-Host; return ($LASTEXITCODE -eq 0) }

Write-Host 'Preparar voces de radio - Editor BMS' -ForegroundColor Yellow
Write-Host "Carpeta: $Aqui"

# ---------- 1. Python 3.11 ----------
Paso 'Python 3.11'
$Base = $null
if (-not (Test-Path -LiteralPath $Py)) {
    $r = & py -3.11 -c "import sys; print(sys.executable)" 2>$null
    if ($LASTEXITCODE -eq 0 -and $r) { $Base = ($r | Select-Object -Last 1).Trim() }
    if (-not $Base) {
        $c = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'
        if (Test-Path -LiteralPath $c) { $Base = $c }
    }
    if (-not $Base) {
        Write-Host '    No esta instalado: se instala Python 3.11.9 solo para este usuario.'
        $inst = Join-Path $Tmp 'python-3.11.9-amd64.exe'
        if (-not (Bajar 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe' $inst)) { Fin 1 }
        $p = Start-Process -FilePath $inst -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=0', 'Include_launcher=1', 'Include_test=0', 'Include_doc=0' -Wait -PassThru
        if ($p.ExitCode -ne 0) { Mal "el instalador de Python devolvio $($p.ExitCode)"; Fin 1 }
        $c = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'
        if (Test-Path -LiteralPath $c) { $Base = $c } else { Mal 'no se encuentra Python tras instalarlo'; Fin 1 }
    }
    Bien $Base
} else { Bien 'ya existe la venv' }

# ---------- 2. venv ----------
Paso 'Entorno virtual (Voces\venv)'
if (-not (Test-Path -LiteralPath $Py)) {
    & $Base -m venv $Venv | Out-Host
    if (-not (Test-Path -LiteralPath $Py)) { Mal 'no se pudo crear la venv'; Fin 1 }
    Pip @('install', '--upgrade', 'pip') | Out-Null
}
$v = & $Py -c "import sys; print('%d.%d' % sys.version_info[:2])"
if ($v -ne '3.11') { Mal "la venv usa Python $v (hace falta 3.11). Borra la carpeta Voces\venv y vuelve a ejecutar."; Fin 1 }
Bien $Py

# ---------- 3. PyTorch, coqui-tts, scipy ----------
Paso 'PyTorch, XTTS (coqui-tts) y scipy'
$nvidia = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' })
if ($nvidia.Count) { Write-Host "    Tarjeta: $($nvidia[0].Name) -> PyTorch con CUDA" } else { Write-Host '    Sin tarjeta NVIDIA -> PyTorch para CPU (funciona, pero MUY lento)' -ForegroundColor Yellow }
function TorchOk {
    $r = & $Py -c "import torch; print(torch.__version__, torch.cuda.is_available())" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $r) { return $false }
    $r = ($r | Select-Object -Last 1)
    if ($nvidia.Count) { return ($r -match '\+cu' -and $r -match 'True') }
    return $true
}
function InstalarTorch([switch]$Forzar) {
    $a = @('install', "torch==$TorchVer", "torchaudio==$TorchVer")
    if ($nvidia.Count) { $a += @('--index-url', $CudaIdx) }
    if ($Forzar) { $a += @('--force-reinstall', '--no-deps') }
    return (Pip $a)
}
if (-not (TorchOk)) { if (-not (InstalarTorch)) { Mal 'fallo al instalar PyTorch'; Fin 1 } }
& $Py -c "import TTS, scipy, six" 2>$null
if ($LASTEXITCODE -ne 0) { if (-not (Pip @('install', 'coqui-tts', 'scipy', 'six'))) { Mal 'fallo al instalar coqui-tts'; Fin 1 } }
# coqui-tts a veces cambia torch por la version sin CUDA: se vuelve a poner
if (-not (TorchOk)) { Write-Host '    Reponiendo PyTorch con CUDA...'; InstalarTorch -Forzar | Out-Null }
if (-not (TorchOk)) { Mal 'PyTorch no ve la tarjeta. Actualiza el driver de NVIDIA y vuelve a ejecutar.'; Fin 1 }
# prueba real: cargar XTTS (asi salen dependencias que falten, como six)
for ($i = 0; $i -lt 3; $i++) {
    $e = & $Py -c "import TTS.api" 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { break }
    $m = [regex]::Match($e, "No module named '([\w\.]+)'")
    if (-not $m.Success) { Write-Host $e; Mal 'XTTS no carga'; Fin 1 }
    $mod = $m.Groups[1].Value.Split('.')[0]
    Write-Host "    Falta el modulo $mod -> se instala"
    Pip @('install', $mod) | Out-Null
}
& $Py -c "import TTS.api" 2>$null
if ($LASTEXITCODE -ne 0) { Mal 'XTTS no carga'; Fin 1 }
$info = & $Py -c "import torch; print(torch.__version__, '|', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')"
Bien ($info | Select-Object -Last 1)

# ---------- 4. ffmpeg ----------
Paso 'ffmpeg con libspeex'
function FfOk([string]$f) { if (-not $f -or -not (Test-Path -LiteralPath $f)) { return $false }; $e = & $f -hide_banner -encoders 2>$null; return [bool](($e -join "`n") -match 'libspeex') }
$Ff = Join-Path $Aqui 'ffmpeg\bin\ffmpeg.exe'
if (-not (FfOk $Ff)) {
    $zip = Join-Path $Tmp 'ffmpeg.zip'
    if (-not (Bajar 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $zip)) { Fin 1 }
    $ext = Join-Path $Tmp 'ffmpeg_ext'
    if (Test-Path -LiteralPath $ext) { Remove-Item -LiteralPath $ext -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $ext -Force
    $raiz = Get-ChildItem -LiteralPath $ext -Directory | Select-Object -First 1
    $dst = Join-Path $Aqui 'ffmpeg'
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Move-Item -LiteralPath $raiz.FullName -Destination $dst
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
}
if (-not (FfOk $Ff)) { Mal 'ffmpeg sin libspeex'; Fin 1 }
Bien $Ff

# ---------- 5. modelo XTTS-v2 ----------
Paso 'Modelo XTTS-v2 (unos 2 GB la primera vez)'
Write-Host '    Coqui pedira aceptar la licencia CPML (uso NO comercial): escribe  y  y pulsa Enter.' -ForegroundColor Yellow
& $Py -c "from TTS.api import TTS; TTS('tts_models/multilingual/multi-dataset/xtts_v2'); print('modelo listo')" | Out-Host
if ($LASTEXITCODE -ne 0) { Mal 'no se pudo descargar/cargar el modelo'; Fin 1 }
Bien 'XTTS-v2 descargado'

# configuracion para el editor (voces.json, junto a Editor_BMS.ps1)
$cfg = Join-Path (Split-Path $Aqui -Parent) 'voces.json'
if (Test-Path -LiteralPath (Join-Path (Split-Path $Aqui -Parent) 'Editor_BMS.ps1')) {
    $j = [ordered]@{ kit = $Aqui; python = $Py; ffmpeg = $Ff }
    [IO.File]::WriteAllText($cfg, (ConvertTo-Json -InputObject $j), (New-Object Text.UTF8Encoding($false)))
}
Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Fin 0
