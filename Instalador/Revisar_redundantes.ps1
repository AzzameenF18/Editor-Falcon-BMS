# Revisa el Archivos.csv del idioma elegido (Idiomas\<CÓDIGO>, el mismo que el instalador; o -Idioma PT)
# y saca una LISTA de los ficheros del instalador que son idénticos al original
# en inglés (no hace falta instalarlos: no cambian nada). NO borra ni modifica nada.
# Resultado: Revision_redundantes_<CÓDIGO>.txt junto a este script.
#
# Para cada línea de Archivos.csv compara el fichero de Ficheros con:
#   1. su copia en Data_ORIGINAL (lo fiable), o
#   2. si no hay copia, el fichero del juego (solo si el juego no tiene instalada esa traducción,
#      según los Traduccion_<CÓDIGO>_instalado.txt de cualquier idioma).
# Las líneas "base + cambios" (LckTxtRc) se combinan al instalar y no se revisan.

param([switch]$Retirar, [string]$Idioma)
# Con -Retirar (Retirar_redundantes.bat), después de la lista retira los de «SE PUEDEN QUITAR»
# (idénticos a Data_ORIGINAL): mueve cada fichero a Ficheros\_retirados\ (no lo borra) y quita su
# línea de Archivos.csv, guardando antes una copia del csv. Los «probables» no se tocan.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$Aqui = $PSScriptRoot
. (Join-Path $Aqui 'Idiomas.ps1')
function Buscar-Carpeta([string]$nombre) {
    $dentro = Join-Path $Aqui $nombre
    if (Test-Path $dentro) { return $dentro }
    return (Join-Path (Split-Path $Aqui -Parent) $nombre)
}
$Idiomas = @(Idiomas-Lista $Aqui)
if ($Idioma) { $Idi = @($Idiomas | Where-Object { $_.codigo -eq $Idioma.ToUpper() }) | Select-Object -First 1 }
else { $Idi = Idioma-Actual $Aqui $Idiomas }
if (-not $Idi) { Write-Host ('No se encuentra el idioma ' + $(if ($Idioma) { $Idioma } else { '(no hay carpeta Idiomas ni Archivos.csv)' })) -ForegroundColor Red; exit 1 }
$Csv = $Idi.csv
$DirFicheros = $Idi.ficheros
$DirOriginal = Buscar-Carpeta 'Data_ORIGINAL'
$Salida = Join-Path $Aqui ('Revision_redundantes' + $(if ($Idi.legado) { '' } else { '_' + $Idi.codigo }) + '.txt')
Write-Host ("Idioma: $($Idi.nombre) ($($Idi.codigo))   ·   $Csv") -ForegroundColor Cyan

function Buscar-BMS {
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Benchmark Sims\Falcon BMS 4.38', 'HKLM:\SOFTWARE\Benchmark Sims\Falcon BMS 4.38') {
        try { $v = (Get-ItemProperty -Path $k -Name baseDir -ErrorAction Stop).baseDir; if ($v -and (Test-Path (Join-Path $v 'Data'))) { return $v.TrimEnd('\') } } catch { }
    }
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Carpeta de Falcon BMS 4.38 (la que contiene Data)'
    if ($d.ShowDialog() -eq 'OK') {
        $r = $d.SelectedPath.TrimEnd('\')
        if ((Split-Path $r -Leaf) -eq 'Data') { $r = Split-Path $r -Parent }
        if (Test-Path (Join-Path $r 'Data')) { return $r }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $Csv)) { Write-Host "No se encuentra $Csv" -ForegroundColor Red; exit 1 }
$BMS = Buscar-BMS
if (-not $BMS) { Write-Host 'Sin carpeta de Falcon BMS: solo se compara con Data_ORIGINAL.' -ForegroundColor Yellow }

# registro de lo instalado, de todos los idiomas (rel -> md5 de las traducciones instaladas)
$Reg = @{}
if ($BMS) {
    foreach ($fr in @(Get-ChildItem -LiteralPath $BMS -Filter 'Traduccion_*_instalado.txt' -File -ErrorAction SilentlyContinue)) {
        foreach ($l in [IO.File]::ReadAllLines($fr.FullName, [Text.Encoding]::UTF8)) {
            $i = $l.LastIndexOf('|')
            if ($i -gt 0) { $kk = $l.Substring(0, $i).ToLower(); if (-not $Reg.ContainsKey($kk)) { $Reg[$kk] = @() }; $Reg[$kk] += $l.Substring($i + 1) }
        }
    }
}
$Hash = @{}
function Md5([string]$p) {
    if (-not $Hash.ContainsKey($p)) { $Hash[$p] = (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash }
    return $Hash[$p]
}
function Iguales([string]$a, [string]$b) {
    if ((Get-Item -LiteralPath $a).Length -ne (Get-Item -LiteralPath $b).Length) { return $false }
    return (Md5 $a) -eq (Md5 $b)
}

$texto = [IO.File]::ReadAllText($Csv, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
$lineas = $texto -split "`r?`n"
$res = [ordered]@{}
$cuenta = @{ quitar = 0; traducido = 0; sinorig = 0; dudoso = 0; noexiste = 0; combinado = 0; duplicado = 0 }
$vistos = @{}
$total = 0
Write-Host 'Revisando Archivos.csv...' -ForegroundColor Cyan
for ($n = 0; $n -lt $lineas.Count; $n++) {
    $l = $lineas[$n]
    $c = $l.Split(';')
    if ($c.Count -lt 3 -or -not $c[1].Trim() -or -not $c[2].Trim() -or $c[0].Trim() -ieq 'Teatro' -or $l.TrimStart().StartsWith('#')) { continue }
    $total++
    $teatro = $c[0].Trim(); $fich = $c[1].Trim(); $data = $c[2].Trim()
    if (-not $res.Contains($teatro)) { $res[$teatro] = @{ quitar = New-Object Collections.ArrayList; sinorig = New-Object Collections.ArrayList; dudoso = New-Object Collections.ArrayList; noexiste = New-Object Collections.ArrayList; duplicado = New-Object Collections.ArrayList; traducido = 0; combinado = 0 } }
    $R = $res[$teatro]
    $item = [pscustomobject]@{ linea = $n + 1; texto = $l; fich = $fich; data = $data; nota = '' }
    $k = ($teatro + '|' + $data).ToLower()
    if ($vistos.ContainsKey($k)) { $item.nota = "repite la línea $($vistos[$k])"; [void]$R.duplicado.Add($item); $cuenta.duplicado++; continue }
    $vistos[$k] = $n + 1
    if ($fich -match '\+') { $R.combinado++; $cuenta.combinado++; continue }
    $src = Join-Path $DirFicheros $fich
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { [void]$R.noexiste.Add($item); $cuenta.noexiste++; continue }
    if ($data -match '^\.\.[\\/]') { $rel = $data.Substring(3); $juego = $(if ($BMS) { Join-Path $BMS $rel }) }
    else { $rel = $data; $juego = $(if ($BMS) { Join-Path (Join-Path $BMS 'Data') $rel }) }
    $orig = Join-Path $DirOriginal $rel
    $ref = $null
    if (Test-Path -LiteralPath $orig -PathType Leaf) { $ref = $orig; $item.nota = 'comparado con Data_ORIGINAL' }
    elseif ($juego -and (Test-Path -LiteralPath $juego -PathType Leaf)) {
        if ($Reg.ContainsKey($rel.ToLower()) -and ($Reg[$rel.ToLower()] -contains (Md5 $juego))) {
            # el del juego es el que puso el instalador (la traducción): no sirve para comparar
            $item.nota = 'sin Data_ORIGINAL y el juego tiene instalada la traducción'; [void]$R.sinorig.Add($item); $cuenta.sinorig++; continue
        }
        $ref = $juego; $item.nota = 'comparado con el fichero del juego (sin copia en Data_ORIGINAL)'
    }
    else { $item.nota = 'no hay original ni fichero en el juego'; [void]$R.sinorig.Add($item); $cuenta.sinorig++; continue }
    if (Iguales $src $ref) {
        if ($ref -eq $orig) { [void]$R.quitar.Add($item); $cuenta.quitar++ } else { [void]$R.dudoso.Add($item); $cuenta.dudoso++ }
    } else { $R.traducido++; $cuenta.traducido++ }
    if ($total % 50 -eq 0) { Write-Host "  $total líneas..." }
}

$o = New-Object Collections.ArrayList
[void]$o.Add("Revisión de ficheros redundantes  ·  $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$o.Add("Archivos.csv:   $Csv")
[void]$o.Add("Ficheros:       $DirFicheros")
[void]$o.Add("Data_ORIGINAL:  $DirOriginal")
[void]$o.Add("Falcon BMS:     $BMS")
[void]$o.Add('')
[void]$o.Add('RESUMEN')
[void]$o.Add("  Líneas revisadas ............................. $total")
[void]$o.Add("  Traducidos (distintos del original, se quedan)  $($cuenta.traducido)")
[void]$o.Add("  SE PUEDEN QUITAR (iguales a Data_ORIGINAL) .... $($cuenta.quitar)")
[void]$o.Add("  Probablemente se pueden quitar (iguales al juego, sin Data_ORIGINAL)  $($cuenta.dudoso)")
[void]$o.Add("  Sin original para comparar .................. $($cuenta.sinorig)")
[void]$o.Add("  No existen en Ficheros ...................... $($cuenta.noexiste)")
[void]$o.Add("  Líneas repetidas ............................ $($cuenta.duplicado)")
[void]$o.Add("  'base + cambios' (no se revisan) ............ $($cuenta.combinado)")
[void]$o.Add('')
[void]$o.Add('Para retirar uno: borra (o aparta) el fichero de Ficheros y su línea de Archivos.csv.')
[void]$o.Add('Retirar un .idx idéntico no da problemas: al instalar se queda el original, que es igual.')
foreach ($t in $res.Keys) {
    $R = $res[$t]
    $hay = $R.quitar.Count + $R.dudoso.Count + $R.sinorig.Count + $R.noexiste.Count + $R.duplicado.Count
    [void]$o.Add(''); [void]$o.Add('=' * 78)
    [void]$o.Add("$t   ·   traducidos: $($R.traducido)   ·   se pueden quitar: $($R.quitar.Count)$(if ($R.dudoso.Count) { "   ·   probables: $($R.dudoso.Count)" })")
    [void]$o.Add('=' * 78)
    if (-not $hay) { [void]$o.Add('  Nada que retirar.'); continue }
    foreach ($g in @(@('SE PUEDEN QUITAR (idénticos a Data_ORIGINAL)', $R.quitar), @('PROBABLEMENTE SE PUEDEN QUITAR (idénticos al fichero del juego; no hay copia en Data_ORIGINAL)', $R.dudoso),
                     @('NO EXISTEN EN Ficheros (la línea sobra o falta el fichero)', $R.noexiste), @('LÍNEAS REPETIDAS', $R.duplicado), @('SIN ORIGINAL PARA COMPARAR (no se puede decidir)', $R.sinorig))) {
        if (-not $g[1].Count) { continue }
        [void]$o.Add(''); [void]$o.Add("  $($g[0]):")
        foreach ($x in $g[1]) {
            [void]$o.Add("    línea $($x.linea):  $($x.texto)")
            [void]$o.Add("        Ficheros\$($x.fich)$(if ($x.nota) { "   ($($x.nota))" })")
        }
    }
}
[IO.File]::WriteAllLines($Salida, [string[]]$o, (New-Object Text.UTF8Encoding($true)))
Write-Host ''
Write-Host "Se pueden quitar: $($cuenta.quitar)   ·   probables: $($cuenta.dudoso)   ·   sin original: $($cuenta.sinorig)   ·   no existen: $($cuenta.noexiste)   ·   repetidas: $($cuenta.duplicado)" -ForegroundColor Green
Write-Host "Lista completa en: $Salida"
if (-not $Retirar) { Start-Process notepad.exe -ArgumentList ('"' + $Salida + '"'); exit 0 }

# ---------------- retirar ----------------
$quitar = @(foreach ($t in $res.Keys) { $res[$t].quitar })
Write-Host ''
if (-not $quitar.Count) { Write-Host 'No hay nada que retirar.' -ForegroundColor Green; exit 0 }
Write-Host "Se van a retirar $($quitar.Count) ficheros (idénticos a su original en Data_ORIGINAL):" -ForegroundColor Yellow
foreach ($x in $quitar) { Write-Host ("  línea {0,4}:  Ficheros\{1}" -f $x.linea, $x.fich) }
Write-Host ''
Write-Host 'Cada fichero se MUEVE a Ficheros\_retirados (no se borra) y su línea se quita de Archivos.csv.'
Write-Host 'Antes se guarda una copia de Archivos.csv.'
$r = Read-Host '¿Continuar? (S/N)'
if ($r -notmatch '^[sS]') { Write-Host 'Cancelado: no se ha tocado nada.'; exit 0 }

$sello = Get-Date -Format 'yyyyMMdd_HHmmss'
$copia = Join-Path (Split-Path $Csv -Parent) ("Archivos.csv.antes_de_retirar_" + $sello)
Copy-Item -LiteralPath $Csv -Destination $copia
$dirRet = Join-Path $DirFicheros '_retirados'
$movidos = 0; $fallos = 0
$lineasQuitar = @{}
foreach ($x in $quitar) {
    $src = Join-Path $DirFicheros $x.fich
    $dst = Join-Path $dirRet $x.fich
    try {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
        if (Test-Path -LiteralPath $dst) { $dst = $dst + '.' + $sello }
        Move-Item -LiteralPath $src -Destination $dst
        $lineasQuitar[$x.linea - 1] = $true; $movidos++
    } catch { Write-Host ("  ERROR al mover {0}: {1}  (su línea se queda)" -f $x.fich, $_.Exception.Message) -ForegroundColor Red; $fallos++ }
}
# Archivos.csv sin esas líneas, con la misma codificación y saltos de línea
$bytes = [IO.File]::ReadAllBytes($Csv)
$bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$orig = [IO.File]::ReadAllText($Csv, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
$nl = if ($orig.Contains("`r`n")) { "`r`n" } else { "`n" }
$todas = $orig -split "`r?`n"
$nuevas = for ($i = 0; $i -lt $todas.Count; $i++) { if (-not $lineasQuitar.ContainsKey($i)) { $todas[$i] } }
[IO.File]::WriteAllText($Csv, ($nuevas -join $nl), (New-Object Text.UTF8Encoding($bom)))

$log = New-Object Collections.ArrayList
[void]$log.Add('')
[void]$log.Add("RETIRADOS  ·  $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$log.Add("  Movidos a $dirRet")
[void]$log.Add("  Copia del csv anterior: $copia")
foreach ($x in $quitar) { if ($lineasQuitar.ContainsKey($x.linea - 1)) { [void]$log.Add("  - $($x.texto)") } }
[IO.File]::AppendAllLines($Salida, [string[]]$log, (New-Object Text.UTF8Encoding($true)))

Write-Host ''
Write-Host "Retirados: $movidos$(if ($fallos) { "   ·   errores: $fallos" })" -ForegroundColor Green
Write-Host "Ficheros movidos a:     $dirRet"
Write-Host "Copia de Archivos.csv:  $copia"
Write-Host 'Para deshacerlo: devuelve los ficheros de _retirados a su sitio y restaura esa copia del csv.'
Start-Process notepad.exe -ArgumentList ('"' + $Salida + '"')
