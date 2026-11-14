# Prepara todo lo necesario para generar las voces de radio (pestana Voces del Editor BMS):
#   1. Python 3.11 (si no esta, lo descarga de python.org y lo instala solo para este usuario)
#   2. El motor de voz, cada uno en su entorno virtual (necesitan versiones distintas de PyTorch):
#        chatterbox (por defecto, licencia MIT): Voces\venv_cb con PyTorch 2.6 y chatterbox-tts
#        xtts (XTTS-v2, licencia CPML no comercial): Voces\venv con PyTorch 2.8 y coqui-tts
#   3. ffmpeg con libspeex (build de gyan.dev) en Voces\ffmpeg
#   4. Descarga del modelo, en Voces\modelos
# Se puede volver a ejecutar: lo que ya este bien, lo salta.
#   -Motor chatterbox|xtts|ambos   (por defecto chatterbox)
#   -Restaurar  (boton «Restaurar entorno» del editor): borra la venv del motor y ffmpeg y lo vuelve a instalar;
#               comprueba que el modelo carga (si no, lo vuelve a bajar) y que el kit tiene todos sus ficheros.
# El modelo XTTS va en Voces\modelos (salvo que ya estuviera de antes en %LOCALAPPDATA%\tts, donde se sigue usando).
#   -Tlk <Falcon.tlk en ingles de Corea>: si faltan referencias de voz (ref\vozNN.wav; el paquete puede venir
#               sin ellas), se crean al final con las frases mas largas y limpias de cada voz de ese Falcon.tlk.
param([switch]$Restaurar, [ValidateSet('chatterbox', 'xtts', 'ambos')][string]$Motor = 'chatterbox', [string]$Tlk = '')

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Aqui = $PSScriptRoot
$Venv = Join-Path $Aqui 'venv'; $PyX = Join-Path $Venv 'Scripts\python.exe'          # XTTS
$VenvC = Join-Path $Aqui 'venv_cb'; $PyC = Join-Path $VenvC 'Scripts\python.exe'     # Chatterbox
$Hay = @{ xtts = ($Motor -in 'xtts', 'ambos'); chatterbox = ($Motor -in 'chatterbox', 'ambos') }
$Py = $PyX
$Tmp = Join-Path $env:TEMP 'bms_voces'
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
$TorchVer = '2.8.0'; $CudaIdx = 'https://download.pytorch.org/whl/cu126'
$env:PIP_NO_CACHE_DIR = '1'   # sin cache de pip (PyTorch ocuparia otros 2-3 GB fuera de la carpeta Voces)
$ModeloViejo = Join-Path $env:LOCALAPPDATA 'tts\tts_models--multilingual--multi-dataset--xtts_v2'
$Modelos = Join-Path $Aqui 'modelos'
if ((Test-Path -LiteralPath $ModeloViejo) -and -not (Test-Path -LiteralPath (Join-Path $Modelos 'tts'))) { Remove-Item Env:TTS_HOME -ErrorAction SilentlyContinue }
else { $env:TTS_HOME = $Modelos }
$Modelo = $(if ($env:TTS_HOME) { Join-Path $env:TTS_HOME 'tts\tts_models--multilingual--multi-dataset--xtts_v2' } else { $ModeloViejo })
$env:HF_HOME = Join-Path $Modelos 'hf'          # Chatterbox (Hugging Face) tambien dentro de Voces\modelos
$TorchCb = '2.6.0'

function Paso([string]$t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Bien([string]$t) { Write-Host "    OK  $t" -ForegroundColor Green }
function Mal([string]$t) { Write-Host "    ERROR  $t" -ForegroundColor Red }
function Fin([int]$c) { Write-Host ''; if ($c -eq 0) { Write-Host 'Todo listo. Vuelve al editor y pulsa la rueda (o recarga la pestana Voces).' -ForegroundColor Green } else { Write-Host 'No se ha completado. Revisa el error de arriba.' -ForegroundColor Red }; exit $c }
function Bajar([string]$url, [string]$dst) {
    Write-Host "    Descargando $url"
    try { Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing; return $true } catch { Mal $_.Exception.Message; return $false }
}
function Pip([string[]]$a) { & $Py -m pip @a | Out-Host; return ($LASTEXITCODE -eq 0) }

Write-Host $(if ($Restaurar) { 'Restaurar el entorno de voces de radio - Editor BMS' } else { 'Preparar voces de radio - Editor BMS' }) -ForegroundColor Yellow
Write-Host "Carpeta: $Aqui"
Write-Host ("Motor: " + $(switch ($Motor) { 'chatterbox' { 'Chatterbox (licencia MIT)' } 'xtts' { 'XTTS-v2 (licencia CPML, no comercial)' } default { 'Chatterbox y XTTS-v2' } }))

# ---------- 0. ficheros del kit (y, al restaurar, venv y ffmpeg nuevos) ----------
Paso 'Ficheros del kit'
$RefsFaltan = @()
$faltan = @(foreach ($f in 'generar_voces.py', 'motores.py', 'montar_tlk.py', 'voces_util.py', 'voz_servidor.py', 'lectura.py', 'plantillas_lectura.json') { if (-not (Test-Path -LiteralPath (Join-Path $Aqui $f))) { $f } })
foreach ($v in 0..13) {
    $r = Join-Path $Aqui ('ref\voz{0:D2}.wav' -f $v); $ini = Join-Path $Aqui ('ref\voz{0:D2}_inicial.wav' -f $v)
    if (-not (Test-Path -LiteralPath $r)) {
        if (Test-Path -LiteralPath $ini) { Copy-Item -LiteralPath $ini -Destination $r -Force; Write-Host "    Repuesta ref\voz$('{0:D2}' -f $v).wav desde la de serie" }
        else { $RefsFaltan += $v }
    }
}
if (-not @(Get-ChildItem -LiteralPath (Join-Path $Aqui 'Mapas') -Filter 'Mapa_*.csv' -ErrorAction SilentlyContinue).Count -and -not @(Get-ChildItem -LiteralPath $Aqui -Filter 'Mapa_*.csv' -ErrorAction SilentlyContinue).Count) {
    Write-Host '    No hay mapas de clips (Mapas\Mapa_*.csv): el editor los rehara desde FragFile.xml del juego.' -ForegroundColor Yellow
}
if ($faltan.Count) { Mal ('faltan ficheros del kit: ' + ($faltan -join ', ')); Write-Host '    Vuelve a descomprimir la carpeta Voces del paquete (sin borrar Idiomas, si quieres conservar lo generado).' -ForegroundColor Yellow; Fin 1 }
Bien 'completo'
if ($RefsFaltan.Count) {
    Write-Host "    Faltan $($RefsFaltan.Count) referencias de voz (ref\): se crearan al final desde el Falcon.tlk original." -ForegroundColor Yellow
    if (-not $Tlk -or -not (Test-Path -LiteralPath $Tlk -PathType Leaf)) {
        Mal 'no se encuentra el Falcon.tlk original en ingles (Data\Sounds\Falcon.tlk de Corea, o su copia en Data_ORIGINAL)'
        Write-Host '    Si tienes la traduccion instalada, restaura el ingles de Corea con el instalador (o instala la traduccion una vez para que guarde el original) y vuelve a pulsar Preparar entorno.' -ForegroundColor Yellow
        Fin 1
    }
}
if ($Restaurar) {
    $borrar = @('ffmpeg'); if ($Hay.xtts) { $borrar += 'venv' }; if ($Hay.chatterbox) { $borrar += 'venv_cb' }
    foreach ($d in $borrar) {
        $x = Join-Path $Aqui $d
        if (Test-Path -LiteralPath $x) {
            Write-Host "    Borrando Voces\$d para instalarlo de nuevo..."
            Remove-Item -LiteralPath $x -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $x) { cmd /c rd /s /q "$x" | Out-Null }
            if (Test-Path -LiteralPath $x) { Mal "no se pudo borrar $x (¿esta en uso? cierra el editor de voces y vuelve a intentarlo)"; Fin 1 }
        }
    }
}

# ---------- 1. Python 3.11 ----------
Paso 'Python 3.11'
$Base = $null
if (($Hay.xtts -and -not (Test-Path -LiteralPath $PyX)) -or ($Hay.chatterbox -and -not (Test-Path -LiteralPath $PyC))) {
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
} else { Bien 'ya existen los entornos' }

$nvidia = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' })
if ($nvidia.Count) { Write-Host "    Tarjeta: $($nvidia[0].Name) -> PyTorch con CUDA" } else { Write-Host '    Sin tarjeta NVIDIA -> PyTorch para CPU (funciona, pero MUY lento)' -ForegroundColor Yellow }
function Venv([string]$dir, [string]$py) {
    if (-not (Test-Path -LiteralPath $py)) {
        & $Base -m venv $dir | Out-Host
        if (-not (Test-Path -LiteralPath $py)) { Mal "no se pudo crear $dir"; Fin 1 }
        & $py -m pip install --upgrade pip | Out-Null
    }
    $v = & $py -c "import sys; print('%d.%d' % sys.version_info[:2])"
    if ($v -ne '3.11') { Mal "$dir usa Python $v (hace falta 3.11). Borra esa carpeta y vuelve a ejecutar."; Fin 1 }
    Bien $py
}
function TorchOk([string]$py, [string]$ver) {
    $r = & $py -c "import torch; print(torch.__version__, torch.cuda.is_available())" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $r) { return $false }
    $r = ($r | Select-Object -Last 1)
    if (-not $r.StartsWith($ver)) { return $false }
    if ($nvidia.Count) { return ($r -match '\+cu' -and $r -match 'True') }
    return $true
}
function InstalarTorch([string]$ver, [switch]$Forzar) {
    $a = @('install', "torch==$ver", "torchaudio==$ver")
    if ($nvidia.Count) { $a += @('--index-url', $CudaIdx) }
    if ($Forzar) { $a += @('--force-reinstall', '--no-deps') }
    return (Pip $a)
}
# importa un modulo; si falta alguna dependencia, la instala (hasta 3 veces)
function Importar([string]$imp, [string]$nombre) {
    for ($i = 0; $i -lt 3; $i++) {
        $e = & $Py -c $imp 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { return $true }
        $m = [regex]::Match($e, "No module named '([\w\.]+)'")
        if (-not $m.Success) { Write-Host $e; Mal "$nombre no carga"; return $false }
        $mod = $m.Groups[1].Value.Split('.')[0]
        Write-Host "    Falta el modulo $mod -> se instala"
        Pip @('install', $mod) | Out-Null
    }
    & $Py -c $imp 2>$null; return ($LASTEXITCODE -eq 0)
}

# ---------- 2. Chatterbox (venv_cb) ----------
if ($Hay.chatterbox) {
    Paso 'Chatterbox: entorno virtual (Voces\venv_cb), PyTorch 2.6 y chatterbox-tts'
    Venv $VenvC $PyC; $Py = $PyC
    if (-not (TorchOk $PyC $TorchCb)) { if (-not (InstalarTorch $TorchCb)) { Mal 'fallo al instalar PyTorch'; Fin 1 } }
    & $PyC -c "import chatterbox.mtl_tts, scipy" 2>$null
    if ($LASTEXITCODE -ne 0) { if (-not (Pip @('install', 'chatterbox-tts', 'scipy'))) { Mal 'fallo al instalar chatterbox-tts'; Fin 1 } }
    # chatterbox-tts a veces cambia torch por la version sin CUDA: se vuelve a poner
    if (-not (TorchOk $PyC $TorchCb)) { Write-Host '    Reponiendo PyTorch con CUDA...'; InstalarTorch $TorchCb -Forzar | Out-Null }
    if (-not (TorchOk $PyC $TorchCb)) { Mal 'PyTorch no ve la tarjeta. Actualiza el driver de NVIDIA y vuelve a ejecutar.'; Fin 1 }
    if (-not (Importar 'from chatterbox.mtl_tts import ChatterboxMultilingualTTS' 'Chatterbox')) { Fin 1 }
    $info = & $PyC -c "import torch; print(torch.__version__, '|', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')"
    Bien ($info | Select-Object -Last 1)
}

# ---------- 3. XTTS (venv) ----------
if ($Hay.xtts) {
    Paso 'XTTS-v2: entorno virtual (Voces\venv), PyTorch y coqui-tts'
    Venv $Venv $PyX; $Py = $PyX
    if (-not (TorchOk $PyX $TorchVer)) { if (-not (InstalarTorch $TorchVer)) { Mal 'fallo al instalar PyTorch'; Fin 1 } }
    & $PyX -c "import TTS, scipy, six" 2>$null
    if ($LASTEXITCODE -ne 0) { if (-not (Pip @('install', 'coqui-tts', 'scipy', 'six'))) { Mal 'fallo al instalar coqui-tts'; Fin 1 } }
    if (-not (TorchOk $PyX $TorchVer)) { Write-Host '    Reponiendo PyTorch con CUDA...'; InstalarTorch $TorchVer -Forzar | Out-Null }
    if (-not (TorchOk $PyX $TorchVer)) { Mal 'PyTorch no ve la tarjeta. Actualiza el driver de NVIDIA y vuelve a ejecutar.'; Fin 1 }
    if (-not (Importar 'import TTS.api' 'XTTS')) { Fin 1 }
    $info = & $PyX -c "import torch; print(torch.__version__, '|', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')"
    Bien ($info | Select-Object -Last 1)
}

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

# ---------- 5. modelos ----------
if ($Hay.chatterbox) {
    Paso 'Modelo Chatterbox Multilingual (unos 3 GB la primera vez)'
    Write-Host "    Carpeta: $env:HF_HOME"
    $Py = $PyC
    $carga = "import torch, inspect; from chatterbox.mtl_tts import ChatterboxMultilingualTTS as M; d = 'cuda' if torch.cuda.is_available() else 'cpu'; k = {'t3_model': 'v3'} if 't3_model' in inspect.signature(M.from_pretrained).parameters else {}; M.from_pretrained(device=d, **k); print('modelo listo')"
    & $PyC -c $carga | Out-Host
    if ($LASTEXITCODE -ne 0) {
        $hub = Join-Path $env:HF_HOME 'hub\models--ResembleAI--chatterbox'
        if (Test-Path -LiteralPath $hub) {
            Write-Host '    El modelo no carga: se borra y se vuelve a descargar.' -ForegroundColor Yellow
            Remove-Item -LiteralPath $hub -Recurse -Force -ErrorAction SilentlyContinue
            & $PyC -c $carga | Out-Host
        }
    }
    if ($LASTEXITCODE -ne 0) { Mal 'no se pudo descargar/cargar el modelo de Chatterbox'; Fin 1 }
    # el afinado para espanol de Espana (opcional: si no se baja, se usa el multilingue)
    & $PyC -c "from huggingface_hub import hf_hub_download as h; h('ResembleAI/Chatterbox-Multilingual-es-es', 't3_es_es.safetensors'); print('afinado es-es listo')" 2>$null | Out-Host
    Bien 'Chatterbox descargado'
}
if ($Hay.xtts) {
    $Py = $PyX
    Paso 'Modelo XTTS-v2 (unos 2 GB la primera vez)'
    Write-Host '    Coqui pedira aceptar la licencia CPML (uso NO comercial): escribe  y  y pulsa Enter.' -ForegroundColor Yellow
    Write-Host "    Carpeta: $Modelo"
    & $Py -c "from TTS.api import TTS; TTS('tts_models/multilingual/multi-dataset/xtts_v2'); print('modelo listo')" | Out-Host
    if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $Modelo)) {
        # modelo a medio bajar o estropeado: se borra y se vuelve a bajar
        Write-Host '    El modelo no carga: se borra y se vuelve a descargar.' -ForegroundColor Yellow
        Remove-Item -LiteralPath $Modelo -Recurse -Force -ErrorAction SilentlyContinue
        & $Py -c "from TTS.api import TTS; TTS('tts_models/multilingual/multi-dataset/xtts_v2'); print('modelo listo')" | Out-Host
    }
    if ($LASTEXITCODE -ne 0) { Mal 'no se pudo descargar/cargar el modelo'; Fin 1 }
    Bien 'XTTS-v2 descargado'
}

if ($RefsFaltan.Count) {
    Paso "Referencias de voz (ref\): $($RefsFaltan.Count) desde el Falcon.tlk original"
    Write-Host "    $Tlk"
    $PyR = $(if ($Hay.chatterbox -and (Test-Path -LiteralPath $PyC)) { $PyC } else { $PyX })
    $env:PYTHONIOENCODING = 'utf-8'
    $malR = 0
    foreach ($v in $RefsFaltan) {
        Write-Host ("    voz {0:D2}... " -f $v) -NoNewline
        $o = & $PyR (Join-Path $Aqui 'voces_util.py') referencia --voz $v --tlk $Tlk --auto --limpiar --ffmpeg $Ff 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Host 'OK' -ForegroundColor Green }
        else { Write-Host 'ERROR' -ForegroundColor Red; Write-Host ('      ' + (($o | Select-Object -Last 3) -join ' ')); $malR++ }
    }
    if ($malR) { Mal "no se pudieron crear $malR referencias"; Fin 1 }
    Bien 'referencias creadas y limpiadas (se pueden cambiar en Ajuste de voces -> Referencia...)'
}

# configuracion para el editor (voces.json, junto a Editor_BMS.ps1): se conservan los ajustes que ya tuviera
$cfg = Join-Path (Split-Path $Aqui -Parent) 'voces.json'
if (Test-Path -LiteralPath (Join-Path (Split-Path $Aqui -Parent) 'Editor_BMS.ps1')) {
    $j = [ordered]@{}
    if (Test-Path -LiteralPath $cfg) { try { $o = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $o.PSObject.Properties) { $j[$p.Name] = $p.Value } } catch { } }
    $j['kit'] = $Aqui; $j['ffmpeg'] = $Ff
    if (Test-Path -LiteralPath $PyX) { $j['python'] = $PyX }
    if (Test-Path -LiteralPath $PyC) { $j['pythonCb'] = $PyC }
    if (-not $j.Contains('motor')) { $j['motor'] = $(if ($Hay.chatterbox) { 'chatterbox' } else { 'xtts' }) }
    [IO.File]::WriteAllText($cfg, (ConvertTo-Json -InputObject $j -Depth 6), (New-Object Text.UTF8Encoding($false)))
}
Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Fin 0
