# Editor de Falcon BMS: SCF (menus), RSC (imagenes, textos y sonidos) y Campanas (.cam/.tac/.trn/.run)
# en una sola ventana con pestanas. Servidor local minimo (solo escucha en este equipo).
# - Busca Falcon BMS 4.38 en el registro y muestra sus ficheros (sin modificarlos nunca).
# - Busca el instalador de la traduccion (Instalador\Archivos.csv) en esta carpeta o hasta 3 por encima.
# - SCF y RSC, al guardar:
#     1. si Data_ORIGINAL no tiene aun el original, lo copia del juego (misma ruta que en Data);
#     2. guarda el modificado en el fichero de Ficheros que indica Archivos.csv; si no hay linea
#        para ese fichero, en Ficheros\SCF\<ruta> o Ficheros\RSC\<ruta> y anade la linea a
#        Archivos.csv (asi «Instalar español» lo copia y «Restaurar inglés» devuelve el original).
#   Sin instalador, se guarda en Editados / Originales junto a este script.
# - El SCF edita ademas los textos del LckTxtRc.irc de la traduccion ("base + cambios" por teatro).
# - Campanas: edita directamente los .cam/.tac/.trn/.run de Ficheros que indica Archivos.csv
#   (antes de modificar uno por primera vez, guarda una copia en "Respaldo").
# - Voces: genera con XTTS las voces de radio en espanol y monta el Falcon.tlk de cada teatro
#   (kit en la carpeta Voces); lo guarda en el instalador igual que SCF y RSC.
# - Se cierra solo unos minutos despues de cerrar la pestana del navegador.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

# ---------- una sola instancia ----------
# Si el editor ya está abierto, no se abre otro: se ofrece abrir otra pestaña del que ya funciona.
$UrlFich = Join-Path $env:LOCALAPPDATA 'Editor_BMS_url.txt'
$creado = $false
$Mutex = New-Object System.Threading.Mutex($true, 'Local\Editor_BMS_Traduccion', [ref]$creado)
if (-not $creado) {
    $url = $null
    try { $url = ([IO.File]::ReadAllText($UrlFich)).Trim() } catch { }
    $vivo = $false
    if ($url) {
        try {
            $u = [Uri]$url; $k = [Web.HttpUtility]::ParseQueryString($u.Query)['k']
        } catch { $k = ($url -replace '^.*[?&]k=', '') }
        try {
            $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri ($url.Split('?')[0].TrimEnd('/') + '/scf/api/ping?k=' + $k)
            $vivo = $r.StatusCode -eq 200
        } catch { }
    }
    if ($vivo) {
        $resp = [System.Windows.Forms.MessageBox]::Show("El Editor de Falcon BMS ya está abierto.`n`n¿Abrir otra pestaña suya en el navegador?", 'Editor de Falcon BMS', 'YesNo', 'Information')
        if ($resp -eq 'Yes') { Start-Process $url }
    } else {
        [void][System.Windows.Forms.MessageBox]::Show("El Editor de Falcon BMS ya está abierto (o terminando de cerrarse).`nBusca su ventana minimizada en la barra de tareas.", 'Editor de Falcon BMS', 'OK', 'Information')
    }
    exit 0
}

$Aqui       = $PSScriptRoot
$HtmlShell  = Join-Path $Aqui 'Editor_BMS.html'
$Paginas    = @{ 'scf' = (Join-Path $Aqui 'scf.html'); 'rsc' = (Join-Path $Aqui 'rsc.html'); 'camp' = (Join-Path $Aqui 'campana.html'); 'voz' = (Join-Path $Aqui 'voces.html'); 'vaj' = (Join-Path $Aqui 'voces_ajuste.html') }
$Editados   = Join-Path $Aqui 'Editados'
$Originales = Join-Path $Aqui 'Originales'
$Respaldo   = Join-Path $Aqui 'Respaldo'

function Aviso([string]$t, [string]$icono = 'Information') {
    [void][System.Windows.Forms.MessageBox]::Show($t, 'Editor de Falcon BMS', 'OK', $icono)
}
foreach ($h in @($HtmlShell) + @($Paginas.Values)) {
    if (-not (Test-Path -LiteralPath $h)) { Aviso "No se encuentra $(Split-Path $h -Leaf) junto a este script." 'Error'; exit 1 }
}

# ---------- instalador de la traduccion (opcional; el editor de campanas lo necesita) ----------
$InstCsv = $null; $InstFicheros = $null; $InstOriginal = $null
$d = $Aqui
for ($i = 0; $i -lt 4 -and $d; $i++) {
    foreach ($cand in @((Join-Path $d 'Instalador'), $d)) {
        $c = Join-Path $cand 'Archivos.csv'
        if ((Test-Path -LiteralPath $c) -and (Test-Path -LiteralPath (Join-Path $cand 'Instalador.ps1'))) {
            $InstCsv = $c
            foreach ($n in 'Ficheros', 'Data_ORIGINAL') {
                $dentro = Join-Path $cand $n
                $ruta = if (Test-Path -LiteralPath $dentro) { $dentro } else { Join-Path (Split-Path $cand -Parent) $n }
                if ($n -eq 'Ficheros') { $InstFicheros = $ruta } else { $InstOriginal = $ruta }
            }
            break
        }
    }
    if ($InstCsv) { break }
    $d = Split-Path $d -Parent
}

# ---------- localizar Falcon BMS ----------
$Bms = $null
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Benchmark Sims\Falcon BMS 4.38', 'HKLM:\SOFTWARE\Benchmark Sims\Falcon BMS 4.38') {
    try {
        $v = (Get-ItemProperty -Path $k -Name baseDir -ErrorAction Stop).baseDir
        if ($v -and (Test-Path -LiteralPath (Join-Path $v 'Data'))) { $Bms = $v.TrimEnd('\'); break }
    } catch { }
}
if (-not $Bms) {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'No se encontró Falcon BMS 4.38 en el registro. Selecciona su carpeta de instalación (la que contiene Data).'
    if ($dlg.ShowDialog() -ne 'OK') { exit 0 }
    $Bms = $dlg.SelectedPath.TrimEnd('\')
    if ((Split-Path $Bms -Leaf) -eq 'Data') { $Bms = Split-Path $Bms -Parent }
    if (-not (Test-Path -LiteralPath (Join-Path $Bms 'Data'))) { Aviso "En esa carpeta no hay una carpeta Data." 'Error'; exit 1 }
}
$Data = (Join-Path $Bms 'Data').TrimEnd('\')

# ---------- utilidades comunes ----------
function RutaSegura([string]$base, [string]$rel) {
    # evita salir de la carpeta base con ".." o rutas absolutas
    if ([string]::IsNullOrEmpty($rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)' -or $rel -match '^[\\/]' -or $rel -match ':') { return $null }
    $full = [IO.Path]::GetFullPath((Join-Path $base $rel))
    $b = [IO.Path]::GetFullPath($base).TrimEnd('\') + '\'
    if (-not $full.StartsWith($b, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $full
}

function Responder($ctx, [int]$codigo, [byte[]]$cuerpo, [string]$tipo) {
    $r = $ctx.Response
    $r.StatusCode = $codigo
    $r.ContentType = $tipo
    $r.Headers['Cache-Control'] = 'no-store'
    if ($cuerpo) { $r.ContentLength64 = $cuerpo.Length; $r.OutputStream.Write($cuerpo, 0, $cuerpo.Length) }
    $r.OutputStream.Close()
}
function Json($ctx, $obj) {
    $txt = ConvertTo-Json -InputObject $obj -Depth 6 -Compress
    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($txt)) 'application/json; charset=utf-8'
}
function Error404($ctx) { Responder $ctx 404 $null 'text/plain' }


# ---------- guardar: en el instalador (Ficheros + Data_ORIGINAL + Archivos.csv) ----------
# Sin instalador, en Editados / Originales junto a este script.
function Leer-Csv {
    if (-not $InstCsv) { return @() }
    $t = [IO.File]::ReadAllText($InstCsv, [Text.Encoding]::UTF8)
    $o = New-Object System.Collections.ArrayList
    foreach ($l in ($t -split "`r?`n")) {
        $c = $l.TrimStart([char]0xFEFF).Split(';')
        if ($c.Count -ge 3 -and $c[1].Trim() -and $c[2].Trim()) {
            [void]$o.Add([pscustomobject]@{ clave = $c[0].Trim(); fich = ($c[1] -split '\+')[0].Trim(); data = $c[2].Trim() })
        }
    }
    return $o
}
function Clave-De([string]$rel) {
    $p = $rel.Split('\')[0]
    if ($p -like 'Add-On *') { return $ClaveTeatro[$p] }
    return 'COREA'
}
# Version modificada de rel (ruta dentro de Data): la de Ficheros que indica Archivos.csv
# ($null si aun no esta en el instalador). Sin instalador: Editados\rel
function Ruta-Editado([string]$rel) {
    if ($InstCsv) {
        foreach ($f in (Leer-Csv)) { if ($f.data -ieq $rel) { return (RutaSegura $InstFicheros $f.fich) } }
        return $null
    }
    return (RutaSegura $Editados $rel)
}
# Copia del original en ingles: Data_ORIGINAL\rel (sin instalador: Originales\rel)
function Ruta-Original([string]$rel) {
    if ($InstCsv) { return (RutaSegura $InstOriginal $rel) }
    return (RutaSegura $Originales $rel)
}
# Guarda $bytes como version modificada de $rel.
# 1. Si Data_ORIGINAL no tiene aun el original, lo copia del juego ($origen; por defecto Data\rel).
# 2. Escribe el modificado en el fichero de Ficheros que indica Archivos.csv; si no hay linea,
#    en Ficheros\<carpeta>\<rel> y anade la linea a Archivos.csv.
function Iguales-Bytes([byte[]]$a, [string]$fichero) {
    if (-not $fichero -or -not (Test-Path -LiteralPath $fichero -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $fichero).Length -ne $a.Length) { return $false }
    $b = [IO.File]::ReadAllBytes($fichero)
    return [Linq.Enumerable]::SequenceEqual([byte[]]$a, [byte[]]$b)
}
function Guardar-Editado([string]$rel, [byte[]]$bytes, [string]$carpeta, [string]$origen) {
    $r = [ordered]@{ ruta = $null; original = $null; csv = $null; igual = $false; retirable = $false }
    if (-not $origen) { $origen = RutaSegura $Data $rel }
    $o = Ruta-Original $rel
    $dst = Ruta-Editado $rel
    # identico al original en ingles: no hace falta en el instalador (sobre todo .idx que no cambian)
    $ref = if ($o -and (Test-Path -LiteralPath $o -PathType Leaf)) { $o } else { $origen }
    if (Iguales-Bytes $bytes $ref) {
        $r.igual = $true
        if (-not $dst -or -not (Test-Path -LiteralPath $dst -PathType Leaf)) {
            $r.csv = 'igual al original'
            Write-Host ("Sin cambios: " + $rel + " es igual al original, no se copia al instalador")
            return $r
        }
        # ya estaba en el instalador: se actualiza, pero se avisa de que se puede retirar
        $r.retirable = [bool]$InstCsv
    }
    if ($o -and -not (Test-Path -LiteralPath $o -PathType Leaf) -and $origen -and (Test-Path -LiteralPath $origen -PathType Leaf)) {
        Copiar-A $origen $o; $r.original = $o; Write-Host ("Original:  " + $o)
    }
    if (-not $dst) {
        $fich = $carpeta + '\' + $rel
        $dst = RutaSegura $InstFicheros $fich
        if (-not $dst) { throw "Ruta no valida: $rel" }
        $r.csv = Anadir-Csv $rel $fich
        Write-Host ("Archivos.csv: " + $r.csv + "  ($fich)")
    } elseif ($InstCsv) { $r.csv = 'ya estaba' }
    Escribir $dst $bytes
    $r.ruta = $dst
    Write-Host ("Guardado:  " + $dst)
    return $r
}

# =====================================================================
# Editor SCF
# =====================================================================
$ClaveTeatro = @{ 'Art' = 'COREA'; 'Add-On Korea TvT' = 'TVT'; 'Add-On Balkans' = 'BALCANES'; 'Add-On Hellas' = 'GRECIA'; 'Add-On Israel' = 'ISRAEL' }

# LckTxtRc.irc traducido del teatro, segun Archivos.csv (columna Ficheros, la base);
# con -Original, su copia en ingles en Data_ORIGINAL (columna Data);
# con -Cambios, el fichero de cambios del teatro ("base + cambios"), si lo hay
function Irc-De([string]$prefijo, [switch]$Original, [switch]$Cambios) {
    if (-not $InstCsv) { return $null }
    $clave = $ClaveTeatro[$prefijo.Split('\')[0]]
    if (-not $clave) { return $null }
    $texto = [IO.File]::ReadAllText($InstCsv, [Text.Encoding]::UTF8)
    foreach ($l in ($texto -split "`r?`n")) {
        $c = $l.TrimStart([char]0xFEFF).Split(';')
        if ($c.Count -ge 3 -and $c[0].Trim() -ieq $clave -and $c[2].Trim() -match '(^|\\)LckTxtRc\.irc$') {
            $partes = @($c[1] -split '\+')
            if ($Original) { $f = Join-Path $InstOriginal $c[2].Trim() }
            elseif ($Cambios) { if ($partes.Count -lt 2) { return $null }; $f = Join-Path $InstFicheros $partes[1].Trim() }
            else { $f = Join-Path $InstFicheros $partes[0].Trim() }
            if (Test-Path -LiteralPath $f) { return $f }
        }
    }
    return $null
}
$Ansi = [Text.Encoding]::GetEncoding(1252)

# Cambia el texto de un ID en un .irc (ANSI). Devuelve $false si el ID no esta.
function Cambiar-Texto([string]$irc, [string]$id, [string]$nuevo) {
    $txt = $Ansi.GetString([IO.File]::ReadAllBytes($irc))
    $re = New-Object Text.RegularExpressions.Regex(('(?im)^(\s*\[ADDTEXT\]\s+' + [regex]::Escape($id) + '\s+")([^"\r\n]*)(")'))
    if (-not $re.IsMatch($txt)) { return $false }
    $m = $re.Match($txt)
    $txt = $txt.Substring(0, $m.Index) + $m.Groups[1].Value + $nuevo + $m.Groups[3].Value + $txt.Substring($m.Index + $m.Length)
    [IO.File]::WriteAllBytes($irc, $Ansi.GetBytes($txt))
    return $true
}

function Copiar-A([string]$src, [string]$dst) {
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}

function Anadir-Csv([string]$rel, [string]$fich) {
    # rel = ruta dentro de Data (p. ej. Add-On Balkans\Art\_FHD\Campaign\Cp_Tool.scf); fich = ruta dentro de Ficheros
    $clave = Clave-De $rel
    if (-not $clave) { return 'sin teatro' }
    $bytes = [IO.File]::ReadAllBytes($InstCsv)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $texto = [Text.Encoding]::UTF8.GetString($bytes)
    if ($bom) { $texto = $texto.Substring(1) }
    $nl = if ($texto.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lineas = New-Object System.Collections.ArrayList
    foreach ($l in ($texto -split "`r?`n")) { [void]$lineas.Add($l) }
    while ($lineas.Count -gt 0 -and $lineas[$lineas.Count - 1] -eq '') { $lineas.RemoveAt($lineas.Count - 1) }
    foreach ($l in $lineas) {
        $c = $l.Split(';')
        if ($c.Count -ge 3 -and $c[2].Trim() -ieq $rel) { return 'ya estaba' }
    }
    $nueva = "$clave;$fich;$rel"
    # se coloca tras la ultima linea del mismo teatro (o al final)
    $pos = -1
    for ($i = 0; $i -lt $lineas.Count; $i++) { if ($lineas[$i].StartsWith("$clave;")) { $pos = $i } }
    if ($pos -ge 0) { $lineas.Insert($pos + 1, $nueva) } else { [void]$lineas.Add($nueva) }
    $salida = ($lineas -join $nl) + $nl
    [IO.File]::WriteAllText($InstCsv, $salida, (New-Object Text.UTF8Encoding($bom)))
    return 'añadida'
}


# ---------- teatros instalados (segun sus .tdf: nombre y artdir) ----------
$STeatros = New-Object System.Collections.ArrayList
$vistos = @{}
function Anadir-Teatro([string]$nombre, [string]$artdir) {
    # artdir "Art" -> Data\Art ; artdir "Add-On Balkans" -> Data\Add-On Balkans\Art
    foreach ($cand in @((Join-Path $artdir 'Art'), $artdir)) {
        $cand = $cand.Trim('\').Trim()
        if ($cand -and (Test-Path -LiteralPath (Join-Path (Join-Path $Data $cand) '_FHD'))) {
            if (-not $vistos.ContainsKey($cand.ToLower())) {
                $vistos[$cand.ToLower()] = $true
                [void]$STeatros.Add([ordered]@{ nombre = $nombre; prefijo = $cand })
            }
            return
        }
    }
}
$tdfs = @()
$td = Join-Path $Data 'TerrData\theaterdefinition'
if (Test-Path $td) { $tdfs += @(Get-ChildItem -Path $td -Filter *.tdf -ErrorAction SilentlyContinue) }
foreach ($d in Get-ChildItem -Path $Data -Directory -Filter 'Add-On *' -ErrorAction SilentlyContinue) {
    $tdfs += @(Get-ChildItem -Path $d.FullName -Recurse -Depth 3 -Filter *.tdf -ErrorAction SilentlyContinue)
}
$lista = @()
foreach ($f in $tdfs) {
    $nombre = $null; $artdir = $null
    foreach ($l in (Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue)) {
        $l = ($l -replace '#.*$', '').Trim()
        if ($l -match '^name\s+(.+)$') { $nombre = $Matches[1].Trim() }
        elseif ($l -match '^artdir\s+(.+)$') { $artdir = $Matches[1].Trim() }
    }
    if (-not $nombre) { $nombre = $f.BaseName }
    if (-not $artdir) { $artdir = 'Art' }
    $lista += [pscustomobject]@{ nombre = $nombre; artdir = $artdir }
}
# Corea (artdir Art) primero
foreach ($t in ($lista | Sort-Object @{ e = { if ($_.artdir -ieq 'Art') { 0 } else { 1 } } }, nombre)) { Anadir-Teatro $t.nombre $t.artdir }
# por si algun teatro no tiene .tdf: estructura estandar
if (-not $vistos.ContainsKey('art')) { Anadir-Teatro 'Corea' 'Art' }
foreach ($d in Get-ChildItem -Path $Data -Directory -Filter 'Add-On *' -ErrorAction SilentlyContinue | Sort-Object Name) {
    Anadir-Teatro ($d.Name -replace '^Add-On ', '') $d.Name
}
$SValidos = @{}; foreach ($t in $STeatros) { $SValidos[$t.prefijo] = $true }


function FhdDe([string]$prefijo) {
    if (-not $SValidos.ContainsKey($prefijo)) { return $null }
    return (Join-Path (Join-Path $Data $prefijo) '_FHD')
}

# =====================================================================
# Editor RSC
# =====================================================================
# ---------- teatros instalados ----------
# Corea = Data sin las carpetas Add-On ; cada Add-On = su carpeta
$Nombres = @{ 'Add-On Korea TvT' = 'Corea Equipo vs Equipo'; 'Add-On Balkans' = 'Balcanes'; 'Add-On Hellas' = 'Grecia'; 'Add-On Israel' = 'Israel' }
$RTeatros = New-Object System.Collections.ArrayList
[void]$RTeatros.Add([ordered]@{ nombre = 'Corea'; prefijo = '' })
foreach ($d in Get-ChildItem -LiteralPath $Data -Directory -Filter 'Add-On *' -ErrorAction SilentlyContinue | Sort-Object Name) {
    $n = $Nombres[$d.Name]; if (-not $n) { $n = $d.Name -replace '^Add-On ', '' }
    [void]$RTeatros.Add([ordered]@{ nombre = $n; prefijo = $d.Name })
}
$RValidos = @{}; foreach ($t in $RTeatros) { $RValidos[$t.prefijo] = $true }


function Copiar([string]$src, [string]$dst) {
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
function Escribir([string]$dst, [byte[]]$bytes) {
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllBytes($dst, $bytes)
}

# Lista de pares .idx/.rsc de un teatro (rutas relativas a Data)
$Cache = @{}
function Listar([string]$prefijo) {
    if ($Cache.ContainsKey($prefijo)) { return $Cache[$prefijo] }
    if ($prefijo -eq '') {
        $raices = @(Get-ChildItem -LiteralPath $Data -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'Add-On *' })
        $sueltos = @(Get-ChildItem -LiteralPath $Data -File -Filter '*.idx' -ErrorAction SilentlyContinue)
    } else {
        $raices = @(Get-Item -LiteralPath (Join-Path $Data $prefijo))
        $sueltos = @()
    }
    $idxs = @($sueltos) + @($raices | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter '*.idx' -ErrorAction SilentlyContinue })
    $lista = New-Object System.Collections.ArrayList
    foreach ($f in $idxs) {
        if ($f.Extension -ne '.idx') { continue }
        $rsc = Get-ChildItem -LiteralPath $f.DirectoryName -File -Filter ($f.BaseName + '.rsc') -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $rsc) { continue }
        $ri = $f.FullName.Substring($Data.Length + 1)
        $rr = $rsc.FullName.Substring($Data.Length + 1)
        [void]$lista.Add([ordered]@{
            idx = $ri; rsc = $rr; n = $f.BaseName; s = $rsc.Length
            ed = $(($er = Ruta-Editado $rr) -and (Test-Path -LiteralPath $er))   # el .idx puede no estar (si no cambia)
        })
    }
    $res = @($lista | Sort-Object { $_.idx })
    $Cache[$prefijo] = $res
    return $res
}

# ---------- uso de los recursos: .scf, .irc y listas .lst de la carpeta Art ----------
# Para un Add-On se mira su Art y, detras, el de Corea (el juego usa el de Corea si el Add-On no lo tiene).
$W1252 = [Text.Encoding]::GetEncoding(1252)
function ArtDe([string]$prefijo) {
    if ($prefijo -eq '') { return (Join-Path $Data 'Art') }
    return (Join-Path (Join-Path $Data $prefijo) 'Art')
}
$CacheArt = @{}
function Art-Ficheros([string]$prefijo) {
    if ($CacheArt.ContainsKey($prefijo)) { return $CacheArt[$prefijo] }
    $raices = @(ArtDe $prefijo); if ($prefijo -ne '') { $raices += (ArtDe '') }
    $res = [ordered]@{}
    for ($n = 0; $n -lt $raices.Count; $n++) {
        $raiz = $raices[$n]
        if (-not (Test-Path -LiteralPath $raiz)) { continue }
        $base = [IO.Path]::GetFullPath($raiz).TrimEnd('\')
        foreach ($f in Get-ChildItem -LiteralPath $raiz -Recurse -File -ErrorAction SilentlyContinue) {
            if ($f.Extension -notmatch '^\.(scf|irc|lst)$') { continue }
            $rel = $f.FullName.Substring($base.Length + 1)
            $k = $rel.ToLower()
            if ($res.Contains($k)) { continue }      # el del Add-On manda
            $res[$k] = [pscustomobject]@{ rel = $rel; ext = $f.Extension.ToLower(); general = ($n -gt 0); txt = $W1252.GetString([IO.File]::ReadAllBytes($f.FullName)) }
        }
    }
    # pantallas: listas <Pantalla>_Scf(_fhd).lst y <Pantalla>_Res(_fhd).lst
    $scfPant = @{}; $resPant = @{}
    foreach ($e in @($res.Values)) {
        if ($e.ext -ne '.lst') { continue }
        $m = [regex]::Match((Split-Path $e.rel -Leaf), '^(.+?)_(Scf|Res)(_fhd)?\.lst$', 'IgnoreCase')
        if (-not $m.Success) { continue }
        if ($m.Groups[2].Value -ieq 'Scf') { $dest = $scfPant } else { $dest = $resPant }
        foreach ($l in ($e.txt -split "`r?`n")) {
            $l = $l.Trim().Replace('/', '\')
            if (-not $l) { continue }
            $k = ($l -replace '^(?i)art\\', '').ToLower()
            if (-not $dest.ContainsKey($k)) { $dest[$k] = New-Object System.Collections.ArrayList }
            if (-not $dest[$k].Contains($m.Groups[1].Value)) { [void]$dest[$k].Add($m.Groups[1].Value) }
        }
    }
    $obj = [pscustomobject]@{ f = $res; scf = $scfPant; res = $resPant }
    $CacheArt[$prefijo] = $obj
    return $obj
}


# =====================================================================
# Editor de campanas
# =====================================================================
$Filas = New-Object System.Collections.ArrayList
if ($InstCsv) {
# ---------- filas de Archivos.csv: .cam / .tac ----------
$Filas = New-Object System.Collections.ArrayList
$texto = [IO.File]::ReadAllText($InstCsv, [Text.Encoding]::UTF8)
foreach ($l in ($texto -split "`r?`n")) {
    $c = $l.TrimStart([char]0xFEFF).Split(';')
    if ($c.Count -lt 3) { continue }
    $fich = $c[1].Trim(); $dat = $c[2].Trim()
    if ($fich -notmatch '\.(cam|tac|trn|run)$') { continue }
    [void]$Filas.Add([ordered]@{ i = $Filas.Count; teatro = $c[0].Trim(); fich = $fich; data = $dat })
}

}
function RutaCamp([string]$base, [string]$rel) {
    if (-not $base -or [string]::IsNullOrEmpty($rel) -or $rel -match '^[a-zA-Z]:' -or $rel.StartsWith('\') -or $rel.StartsWith('/')) { return $null }
    return [IO.Path]::GetFullPath((Join-Path $base $rel))
}
function Ruta-De($fila, [string]$src) {
    switch ($src) {
        'fich' { return RutaCamp $InstFicheros $fila.fich }
        'orig' { return RutaCamp $InstOriginal $fila.data }
        'game' { return RutaCamp $Data $fila.data }
    }
    return $null
}

function Fila-De($q) {
    $n = 0
    if (-not [int]::TryParse([string]$q['i'], [ref]$n)) { return $null }
    if ($n -lt 0 -or $n -ge $Filas.Count) { return $null }
    return $Filas[$n]
}


# =====================================================================
# Voces de radio (Falcon.tlk)
# =====================================================================
# Kit de voces (generar_voces.py, montar_tlk.py, voces_util.py, Lista_<Teatro>.csv, ref\) en la
# carpeta Voces junto a este script (o la que elijas). Python = el de la venv con coqui-tts.
$VozCfgFich = Join-Path $Aqui 'voces.json'
$VozCfg = [ordered]@{ kit = ''; python = ''; ffmpeg = '' }
# ajustes de generacion (se guardan tambien en voces.json)
$VozAj = [ordered]@{ temperatura = 0.65; velocidad = 1.0; rms = 6000; radio = 1; pausaInicio = 50; pausaFin = 100; suavizado = 0; limpieza = 0; procesos = 2 }
$VozAjRango = @{ temperatura = @(0.1, 1.0); velocidad = @(0.8, 1.3); rms = @(1000, 12000); radio = @(0, 2); pausaInicio = @(0, 500); pausaFin = @(0, 1000); suavizado = @(0, 1); limpieza = @(0, 1); procesos = @(1, 4) }
if (Test-Path -LiteralPath $VozCfgFich) {
    try {
        $j = Get-Content -LiteralPath $VozCfgFich -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in 'kit', 'python', 'ffmpeg') { if ($j.$k) { $VozCfg[$k] = [string]$j.$k } }
        if ($j.ajustes) { foreach ($k in @($VozAj.Keys)) { if ($null -ne $j.ajustes.$k) { $VozAj[$k] = [double]$j.ajustes.$k } } }
    } catch { }
}
$Inv = [Globalization.CultureInfo]::InvariantCulture
function Voz-Num($v) { return ([double]$v).ToString($Inv) }
function Voz-Args-Ajustes {
    return @('--temperatura', (Voz-Num $VozAj.temperatura), '--velocidad', (Voz-Num $VozAj.velocidad), '--rms', (Voz-Num $VozAj.rms),
             '--radio', ([string][int]$VozAj.radio), '--pausa-inicio', ([string][int]$VozAj.pausaInicio), '--pausa-fin', ([string][int]$VozAj.pausaFin),
             '--suavizado', (Voz-Num $VozAj.suavizado), '--limpieza', (Voz-Num $VozAj.limpieza), '--procesos', ([string][int]$VozAj.procesos))
}
function Voz-Guardar-Cfg {
    $o = [ordered]@{ kit = $VozCfg.kit; python = $VozCfg.python; ffmpeg = $VozCfg.ffmpeg; ajustes = $VozAj }
    [IO.File]::WriteAllText($VozCfgFich, (ConvertTo-Json -InputObject $o), (New-Object Text.UTF8Encoding($false)))
}
function Voz-Autodetectar {
    if (-not $VozCfg.kit -or -not (Test-Path -LiteralPath (Join-Path $VozCfg.kit 'generar_voces.py'))) {
        $VozCfg.kit = ''
        $cands = @((Join-Path $Aqui 'Voces'))
        if ($InstCsv) { $cands += (Join-Path (Split-Path (Split-Path $InstCsv -Parent) -Parent) 'Voces') }
        foreach ($c in $cands) { if (Test-Path -LiteralPath (Join-Path $c 'generar_voces.py')) { $VozCfg.kit = $c; break } }
    }
    # lo que instala Preparar_voces.ps1 (Voces\venv y Voces\ffmpeg) tiene preferencia
    if ($VozCfg.kit) {
        $c = Join-Path $VozCfg.kit 'venv\Scripts\python.exe'; if (Test-Path -LiteralPath $c) { $VozCfg.python = $c }
        $c = Join-Path $VozCfg.kit 'ffmpeg\bin\ffmpeg.exe'; if (Test-Path -LiteralPath $c) { $VozCfg.ffmpeg = $c }
    }
    if (-not $VozCfg.python -or -not (Test-Path -LiteralPath $VozCfg.python)) {
        $VozCfg.python = ''
        $cands = @()
        if ($VozCfg.kit) { $cands += @((Join-Path $VozCfg.kit 'venv\Scripts\python.exe'), (Join-Path $VozCfg.kit '.venv\Scripts\python.exe'), (Join-Path (Split-Path $VozCfg.kit -Parent) 'venv\Scripts\python.exe')) }
        $cands += @((Join-Path $env:USERPROFILE 'xtts\venv\Scripts\python.exe'), (Join-Path $env:USERPROFILE 'xtts\.venv\Scripts\python.exe'))
        foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $VozCfg.python = $c; break } }
        if (-not $VozCfg.python) { $g = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if ($g) { $VozCfg.python = $g.Source } }
    }
    if (-not $VozCfg.ffmpeg -or -not (Test-Path -LiteralPath $VozCfg.ffmpeg)) {
        $VozCfg.ffmpeg = ''
        $cands = @()
        if ($VozCfg.kit) { $cands += (Join-Path $VozCfg.kit 'ffmpeg\bin\ffmpeg.exe') }
        $cands += @('C:\ffmpeg\bin\ffmpeg.exe', (Join-Path $env:USERPROFILE 'ffmpeg\bin\ffmpeg.exe'))
        foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $VozCfg.ffmpeg = $c; break } }
        if (-not $VozCfg.ffmpeg) { $g = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if ($g) { $VozCfg.ffmpeg = $g.Source } }
    }
}
Voz-Autodetectar

# Falcon.tlk de cada teatro (ruta dentro de Data)
$VozNombres = @{ 'Add-On Balkans' = 'Balcanes'; 'Add-On Hellas' = 'Grecia'; 'Add-On Israel' = 'Israel' }
$VozTeatros = New-Object System.Collections.ArrayList
function Voz-Buscar-Tlk {
    $VozTeatros.Clear()
    foreach ($base in @(@{ n = 'Corea'; d = $Data; filtro = 'Sounds' }) + @(foreach ($d in Get-ChildItem -LiteralPath $Data -Directory -Filter 'Add-On *' -ErrorAction SilentlyContinue) { if ($VozNombres[$d.Name]) { @{ n = $VozNombres[$d.Name]; d = $d.FullName; filtro = '' } } })) {
        $f = $null
        if ($base.filtro) { $c = Join-Path $base.d 'Sounds\Falcon.tlk'; if (Test-Path -LiteralPath $c) { $f = Get-Item -LiteralPath $c } }
        else { $f = Get-ChildItem -LiteralPath $base.d -Recurse -Depth 4 -Filter 'Falcon.tlk' -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if (-not $f) {
            # sin el del juego, quiza ya este en Data_ORIGINAL
            continue
        }
        $rel = $f.FullName.Substring($Data.Length).TrimStart('\')
        [void]$VozTeatros.Add([ordered]@{ nombre = $base.n; rel = $rel })
    }
}
Voz-Buscar-Tlk
function Voz-Teatro([string]$n) { foreach ($t in $VozTeatros) { if ($t.nombre -eq $n) { return $t } }; return $null }

function Voz-Espanol-Instalado([string]$rel) {
    $p = Join-Path $Bms 'Traduccion_ES_instalado.txt'
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    foreach ($l in [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)) {
        $i = $l.LastIndexOf('|'); if ($i -gt 0 -and $l.Substring(0, $i) -ieq $rel) { return $true }
    }
    return $false
}
# Falcon.tlk en ingles: Data_ORIGINAL si esta; si no, el del juego (si no tiene instalada la traduccion)
function Voz-Tlk-Ingles($t) {
    $o = Ruta-Original $t.rel
    if ($o -and (Test-Path -LiteralPath $o -PathType Leaf)) { return @{ ruta = $o; seguro = $true } }
    $j = RutaSegura $Data $t.rel
    return @{ ruta = $j; seguro = -not (Voz-Espanol-Instalado $t.rel) }
}

function Voz-Python([string[]]$argumentos) {
    $env:PYTHONIOENCODING = 'utf-8'
    $ErrorActionPreference = 'Continue'   # en PowerShell 5.1, con 'Stop' cualquier linea de stderr seria un error
    $sal = & $VozCfg.python @argumentos 2>&1
    return @{ codigo = $LASTEXITCODE; texto = (($sal | ForEach-Object { "$_" }) -join "`n") }
}

function Voz-Xtts-Ok {
    if (-not $VozCfg.python -or -not (Test-Path -LiteralPath $VozCfg.python)) { return $false }
    $ErrorActionPreference = 'Continue'
    $r = & $VozCfg.python -c "import importlib.util as u; print(all(u.find_spec(m) for m in ('torch','TTS','scipy')))" 2>$null
    return (($r | Select-Object -Last 1) -eq 'True')
}
function Voz-Ffmpeg-Ok {
    $ErrorActionPreference = 'Continue'
    try { $e = & $VozCfg.ffmpeg -hide_banner -encoders 2>&1; return [bool]((($e | ForEach-Object { "$_" }) -join "`n") -match 'libspeex') } catch { return $false }
}

$VozTrabajos = New-Object System.Collections.ArrayList
function Voz-Lanzar([string]$tipo, [string]$teatro, [string]$titulo, [string[]]$argumentos, [string]$exe) {
    if (-not $exe) { $exe = $VozCfg.python }
    foreach ($w in $VozTrabajos) { if (-not $w.proc.HasExited) { throw "Ya hay un proceso en marcha ($($w.titulo)). Espera a que termine." } }
    # consola visible: se ve el progreso y se puede cortar con Ctrl+C; queda abierta al terminar
    $linea = '"' + $exe + '" ' + (($argumentos | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $cmd = '/c title ' + $titulo + ' & ' + $linea + ' & echo. & call echo Codigo de salida: %^errorlevel% & pause'
    $p = Start-Process -FilePath $env:ComSpec -ArgumentList $cmd -WorkingDirectory $VozCfg.kit -PassThru
    $w = [ordered]@{ id = [Guid]::NewGuid().ToString('N').Substring(0, 8); tipo = $tipo; teatro = $teatro; titulo = $titulo; inicio = (Get-Date); proc = $p }
    [void]$VozTrabajos.Add($w)
    Write-Host ("Voces: " + $titulo)
    return $w.id
}
function Voz-Estado-Trabajos {
    return @(foreach ($w in $VozTrabajos) {
        [ordered]@{ id = $w.id; tipo = $w.tipo; teatro = $w.teatro; teatros = @($w.teatros); titulo = $w.titulo; inicio = $w.inicio.ToString('HH:mm:ss'); inicioMs = [DateTimeOffset]::new($w.inicio).ToUnixTimeMilliseconds(); enCurso = -not $w.proc.HasExited }
    })
}
function Voz-Cita([string[]]$argumentos) { return (($argumentos | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ') }
# varios pasos seguidos en la misma consola (si uno falla, no se hacen los siguientes)
function Voz-Lanzar-Cadena([string]$tipo, [string[]]$teatros, [string]$titulo, $pasos) {
    foreach ($w in $VozTrabajos) { if (-not $w.proc.HasExited) { throw "Ya hay un proceso en marcha ($($w.titulo)). Espera a que termine." } }
    $lineas = @(foreach ($p in $pasos) { '"' + $VozCfg.python + '" ' + (Voz-Cita $p) })
    $cmd = '/c title ' + $titulo + ' & (' + ($lineas -join ' && ') + ') & echo. & call echo Codigo de salida: %^errorlevel% & pause'
    $pr = Start-Process -FilePath $env:ComSpec -ArgumentList $cmd -WorkingDirectory $VozCfg.kit -PassThru
    $w = [ordered]@{ id = [Guid]::NewGuid().ToString('N').Substring(0, 8); tipo = $tipo; teatro = ($teatros -join ','); teatros = $teatros; titulo = $titulo; inicio = (Get-Date); proc = $pr }
    [void]$VozTrabajos.Add($w)
    Write-Host ("Voces: " + $titulo)
    return $w.id
}
# argumentos de montar_tlk.py para un teatro (con el Falcon.tlk del instalador como base)
function Voz-Args-Montar($t) {
    $ing = Voz-Tlk-Ingles $t
    if (-not $ing.seguro) { throw "No hay copia del Falcon.tlk de $($t.nombre) en inglés en Data_ORIGINAL y el del juego es el de la traducción. Restaura el inglés con el instalador y vuelve a intentarlo." }
    $o = Ruta-Original $t.rel
    if ($o -and -not (Test-Path -LiteralPath $o)) { Copiar-A $ing.ruta $o; Write-Host ("Original:  " + $o); $ing.ruta = $o }
    $a = @((Join-Path $VozCfg.kit 'montar_tlk.py'), '--teatro', $t.nombre, '--tlk', $ing.ruta, '--ffmpeg', $VozCfg.ffmpeg,
           '--pausa-inicio', ([string][int]$VozAj.pausaInicio), '--pausa-fin', ([string][int]$VozAj.pausaFin))
    $ed = Ruta-Editado $t.rel
    if ($ed -and (Test-Path -LiteralPath $ed -PathType Leaf)) { $a += @('--base', $ed) }
    return ,$a
}
# servidor de pruebas de voz (voz_servidor.py): XTTS cargado para probar al momento
$VozSrv = @{ proc = $null; puerto = 0; token = '' }
function Voz-Srv-Vivo { return ($VozSrv.proc -and -not $VozSrv.proc.HasExited) }
function Voz-Srv-Arrancar {
    if (Voz-Srv-Vivo) { return }
    $py = Join-Path $VozCfg.kit 'voz_servidor.py'
    if (-not (Test-Path -LiteralPath $py)) { throw 'No está voz_servidor.py en el kit de voces.' }
    $puerto = 0
    foreach ($p in 8899..8960) {
        try { $l = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p); $l.Start(); $l.Stop(); $puerto = $p; break } catch { }
    }
    if (-not $puerto) { throw 'No hay ningún puerto libre para el servidor de voz.' }
    $VozSrv.token = [Guid]::NewGuid().ToString('N'); $VozSrv.puerto = $puerto
    $arg = '"' + $py + '" --puerto ' + $puerto + ' --token ' + $VozSrv.token
    $VozSrv.proc = Start-Process -FilePath $VozCfg.python -ArgumentList $arg -WorkingDirectory $VozCfg.kit -WindowStyle Minimized -PassThru
    Write-Host ("Voces: servidor de pruebas en el puerto " + $puerto)
}
$VozAjFich = $null
function Voz-Aj-Fich { return (Join-Path $VozCfg.kit 'ajustes_voces.json') }
function Voz-Aj-Leer {
    $f = Voz-Aj-Fich; $h = [ordered]@{}
    if (Test-Path -LiteralPath $f) {
        try { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = $p.Value } } catch { }
    }
    return $h
}

function Voz-Leer-Cuerpo($req) {
    $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
    $t = $sr.ReadToEnd(); $sr.Close()
    if (-not $t) { return $null }
    return ($t | ConvertFrom-Json)
}
function Voz-Elegir([string]$que) {
    $f = New-Object System.Windows.Forms.Form
    $f.TopMost = $true; $f.ShowInTaskbar = $false; $f.StartPosition = 'CenterScreen'; $f.Size = '1,1'; $f.Opacity = 0
    $f.Show(); $f.Activate()
    try {
        if ($que -eq 'kit') {
            $d = New-Object System.Windows.Forms.FolderBrowserDialog
            $d.Description = 'Carpeta del kit de voces (la que contiene generar_voces.py)'
            if ($VozCfg.kit) { $d.SelectedPath = $VozCfg.kit }
            if ($d.ShowDialog($f) -eq 'OK') { return $d.SelectedPath }
        } else {
            $d = New-Object System.Windows.Forms.OpenFileDialog
            $d.Filter = if ($que -eq 'python') { 'python.exe|python.exe|Programas (*.exe)|*.exe' } else { 'ffmpeg.exe|ffmpeg.exe|Programas (*.exe)|*.exe' }
            $d.Title = if ($que -eq 'python') { 'python.exe de la venv con coqui-tts (venv\Scripts\python.exe)' } else { 'ffmpeg.exe (build "full" con libspeex)' }
            if ($d.ShowDialog($f) -eq 'OK') { return $d.FileName }
        }
    } finally { $f.Close() }
    return $null
}


# ---------- servidor ----------
$Token = [Guid]::NewGuid().ToString('N')
$Listener = $null
foreach ($p in 8790..8870) {
    try {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://localhost:$p/")
        $l.Start(); $Listener = $l; $Puerto = $p; break
    } catch { }
}
if (-not $Listener) { Aviso 'No se pudo abrir ningún puerto local (8790-8870).' 'Error'; exit 1 }

$Url = "http://localhost:$Puerto/?k=$Token"
Write-Host 'Editor de Falcon BMS (SCF, RSC, campañas y voces)'
Write-Host "Falcon BMS: $Bms"
Write-Host "Editados:   $Editados"
Write-Host "Originales: $Originales"
Write-Host "Respaldo:   $Respaldo  (campañas)"
if ($InstCsv) { Write-Host "Instalador: $InstCsv" } else { Write-Host 'Instalador: no encontrado (el editor de campañas no estará disponible)' }
if ($InstCsv) { Write-Host "Ficheros .cam/.tac/.trn/.run en Archivos.csv: $($Filas.Count)" }
Write-Host ("Voces:      " + $(if ($VozCfg.kit) { $VozCfg.kit } else { 'kit no encontrado (carpeta Voces)' }))
Write-Host "Abierto en: $Url"
Write-Host 'Cierra esta ventana para terminar.'
try { [IO.File]::WriteAllText($UrlFich, $Url) } catch { }
Start-Process $Url

$ultimo = Get-Date
$LimiteInactivo = [TimeSpan]::FromMinutes(5)
try {
    while ($Listener.IsListening) {
        $tarea = $Listener.GetContextAsync()
        while (-not $tarea.Wait(1000)) {
            if (((Get-Date) - $ultimo) -gt $LimiteInactivo) { return }
        }
        $ctx = $tarea.Result
        $ultimo = Get-Date
        try {
            $req = $ctx.Request
            $q = $req.QueryString
            $abs = $req.Url.AbsolutePath
            if ($abs -eq '/' -or $abs -eq '/index.html') {
                Responder $ctx 200 ([IO.File]::ReadAllBytes($HtmlShell)) 'text/html; charset=utf-8'; continue
            }
            $mm = [regex]::Match($abs, '^/(scf|rsc|camp|voz|vaj)(/.*)?$')
            if (-not $mm.Success) { Error404 $ctx; continue }
            $modulo = $mm.Groups[1].Value
            $ruta = $mm.Groups[2].Value
            if ($ruta -eq '' -or $ruta -eq '/' -or $ruta -eq '/index.html') {
                Responder $ctx 200 ([IO.File]::ReadAllBytes($Paginas[$modulo])) 'text/html; charset=utf-8'; continue
            }
            if ($q['k'] -ne $Token) { Responder $ctx 403 $null 'text/plain'; continue }

            if ($modulo -eq 'scf') {
            switch ($ruta) {
                '/api/info' {
                    $dest = $Editados; if ($InstCsv) { $dest = $InstFicheros }
                    Json $ctx ([ordered]@{ bms = $Bms; editados = $dest; original = $(if ($InstCsv) { $InstOriginal } else { $Originales }); teatros = @($STeatros); instalador = $InstCsv })
                }
                '/api/ping' { Json $ctx 'ok' }
                '/api/list' {
                    # toda la carpeta Art del teatro (_FHD y las demas); rutas relativas a Art
                    if (-not (FhdDe $q['t'])) { Error404 $ctx; break }
                    $art = Join-Path $Data $q['t']
                    $base = [IO.Path]::GetFullPath($art).TrimEnd('\')
                    $lista = @(Get-ChildItem -Path $art -Recurse -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -match '^\.(idx|rsc|scf|irc|bft|lst)$' } |
                        ForEach-Object { [ordered]@{ p = $_.FullName.Substring($base.Length + 1); n = $_.Name; s = $_.Length } })
                    Json $ctx $lista
                }
                '/api/file' {
                    # p = ruta relativa a la carpeta Art del teatro (_FHD\... o Main\...); off/len opcionales
                    if (-not (FhdDe $q['t'])) { Error404 $ctx; break }
                    $full = $null
                    # .rsc/.idx: si hay versión editada (en el instalador), la vista previa usa esa
                    if ([string]$q['p'] -match '\.(rsc|idx)$') {
                        $ed = Ruta-Editado (([string]$q['t']).TrimEnd('\') + '\' + [string]$q['p'])
                        if ($ed -and (Test-Path -LiteralPath $ed -PathType Leaf)) { $full = $ed }
                    }
                    if (-not $full) { $full = RutaSegura (Join-Path $Data $q['t']) $q['p'] }
                    if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { Error404 $ctx; break }
                    $fs = [IO.File]::Open($full, 'Open', 'Read', 'ReadWrite')
                    try {
                        $off = 0L; $len = $fs.Length
                        if ($q['off']) { $off = [long]$q['off'] }
                        if ($q['len']) { $len = [long]$q['len'] }
                        if ($off -lt 0) { $off = 0 }
                        if ($off -gt $fs.Length) { $off = $fs.Length }
                        if ($off + $len -gt $fs.Length) { $len = $fs.Length - $off }
                        $buf = New-Object byte[] $len
                        [void]$fs.Seek($off, 'Begin')
                        $leido = 0
                        while ($leido -lt $len) { $n = $fs.Read($buf, $leido, $len - $leido); if ($n -le 0) { break }; $leido += $n }
                    } finally { $fs.Close() }
                    Responder $ctx 200 $buf 'application/octet-stream'
                }
                '/api/irc' {
                    if (-not (FhdDe $q['t'])) { Error404 $ctx; break }
                    $irc = Irc-De $q['t']
                    if (-not $irc) { Error404 $ctx; break }
                    $cam = Irc-De $q['t'] -Cambios
                    if ($req.HttpMethod -ne 'POST') {
                        # base y, detras, las lineas del fichero de cambios del teatro (mandan las ultimas)
                        $bytes = [IO.File]::ReadAllBytes($irc)
                        $nombre = $irc
                        if ($cam) {
                            $extra = @(($Ansi.GetString([IO.File]::ReadAllBytes($cam)) -split "`r?`n") | Where-Object { $_ -match '^\s*\[ADDTEXT\]' })
                            $bytes = $Ansi.GetBytes($Ansi.GetString($bytes) + "`r`n" + ($extra -join "`r`n") + "`r`n")
                            $nombre = "$irc + $cam"
                        }
                        $r = $ctx.Response; $r.Headers['X-Irc'] = [Uri]::EscapeDataString($nombre)
                        Responder $ctx 200 $bytes 'application/octet-stream'; break
                    }
                    # cambia el texto de un ID: [ADDTEXT] ID "texto"
                    $id = $q['id']
                    $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
                    $nuevo = $sr.ReadToEnd(); $sr.Close()
                    if ($nuevo -match '["\r\n]') { Json $ctx ([ordered]@{ ok = $false; error = 'El texto no puede llevar comillas ni saltos de linea' }); break }
                    if ($Ansi.GetString($Ansi.GetBytes($nuevo)) -cne $nuevo) { Json $ctx ([ordered]@{ ok = $false; error = 'El texto lleva caracteres que no admite el juego (ANSI)' }); break }
                    # si el texto es propio del teatro (esta en su fichero de cambios) se guarda alli
                    $dest = $irc
                    if ($cam -and (Cambiar-Texto $cam $id $nuevo)) { $dest = $cam }
                    elseif (-not (Cambiar-Texto $irc $id $nuevo)) { Json $ctx ([ordered]@{ ok = $false; error = "$id no esta en $(Split-Path $irc -Leaf)" }); break }
                    $irc = $dest
                    Write-Host ("Texto:     $id = `"$nuevo`"  ($irc)")
                    Json $ctx ([ordered]@{ ok = $true; ruta = $irc })
                }
                '/api/irc-orig' {
                    if (-not (FhdDe $q['t'])) { Error404 $ctx; break }
                    $irc = Irc-De $q['t'] -Original
                    if (-not $irc) { Error404 $ctx; break }
                    Responder $ctx 200 ([IO.File]::ReadAllBytes($irc)) 'application/octet-stream'
                }
                '/api/irc-dup' {
                    # anade [ADDTEXT] NUEVO "texto" justo debajo de la linea del ID original
                    if ($req.HttpMethod -ne 'POST' -or -not (FhdDe $q['t'])) { Error404 $ctx; break }
                    $irc = Irc-De $q['t']
                    if (-not $irc) { Json $ctx ([ordered]@{ ok = $false; error = 'No se encuentra el LckTxtRc.irc de la traduccion' }); break }
                    $id = $q['id']; $nuevoId = $q['new']
                    if ($nuevoId -notmatch '^[A-Za-z0-9_]+$') { Json $ctx ([ordered]@{ ok = $false; error = 'ID no valido' }); break }
                    $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
                    $nuevo = $sr.ReadToEnd(); $sr.Close()
                    if ($nuevo -match '["\r\n]') { Json $ctx ([ordered]@{ ok = $false; error = 'El texto no puede llevar comillas ni saltos de linea' }); break }
                    if ($Ansi.GetString($Ansi.GetBytes($nuevo)) -cne $nuevo) { Json $ctx ([ordered]@{ ok = $false; error = 'El texto lleva caracteres que no admite el juego (ANSI)' }); break }
                    $txt = $Ansi.GetString([IO.File]::ReadAllBytes($irc))
                    if ([regex]::IsMatch($txt, '(?im)^\s*\[ADDTEXT\]\s+' + [regex]::Escape($nuevoId) + '\s')) { Json $ctx ([ordered]@{ ok = $false; error = "$nuevoId ya existe" }); break }
                    $nl = if ($txt.Contains("`r`n")) { "`r`n" } else { "`n" }
                    $linea = '[ADDTEXT] ' + $nuevoId + ' "' + $nuevo + '"'
                    $m = [regex]::Match($txt, '(?im)^[ \t]*\[ADDTEXT\][ \t]+' + [regex]::Escape($id) + '[ \t][^\r\n]*')
                    if ($m.Success) { $pos = $m.Index + $m.Length; $txt = $txt.Substring(0, $pos) + $nl + $linea + $txt.Substring($pos) }
                    else { if (-not $txt.EndsWith("`n")) { $txt += $nl }; $txt += $linea + $nl }
                    [IO.File]::WriteAllBytes($irc, $Ansi.GetBytes($txt))
                    Write-Host ("Texto nuevo: $linea  ($irc)")
                    Json $ctx ([ordered]@{ ok = $true; ruta = $irc })
                }
                '/api/original' {
                    # copia del original en ingles (Data_ORIGINAL), por si en el juego ya esta instalado el editado
                    $full = Ruta-Original $q['rel']
                    if ($full -and (Test-Path -LiteralPath $full -PathType Leaf)) { Responder $ctx 200 ([IO.File]::ReadAllBytes($full)) 'application/octet-stream' }
                    else { Error404 $ctx }
                }
                '/api/edited' {
                    $full = Ruta-Editado $q['rel']
                    if ($full -and (Test-Path -LiteralPath $full -PathType Leaf)) { Responder $ctx 200 ([IO.File]::ReadAllBytes($full)) 'application/octet-stream' }
                    else { Error404 $ctx }
                }
                '/api/save' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $rel = [string]$q['rel']
                    if (-not (RutaSegura $Data $rel) -or $rel -notmatch '\.scf$') { Responder $ctx 400 $null 'text/plain'; break }
                    $ms = New-Object IO.MemoryStream
                    $req.InputStream.CopyTo($ms)
                    $origen = RutaSegura $Data $rel
                    if ($origen -and -not (Test-Path -LiteralPath $origen -PathType Leaf) -and $q['gen']) {
                        # .scf general editado para un Add-On: su original es el general
                        $origen = RutaSegura $Data $q['gen']
                    }
                    $g = Guardar-Editado $rel $ms.ToArray() 'SCF' $origen
                    Json $ctx ([ordered]@{ ok = $true; ruta = $g.ruta; original = $g.original; csv = $g.csv; instalador = [bool]$InstCsv; igual = $g.igual; retirable = $g.retirable })
                }
                default { Error404 $ctx }
            }
            }
            elseif ($modulo -eq 'rsc') {
            switch ($ruta) {
                '/api/ping' { Json $ctx 'ok' }
                '/api/info' {
                    Json $ctx ([ordered]@{ bms = $Bms; editados = $(if ($InstCsv) { $InstFicheros } else { $Editados }); originales = $(if ($InstCsv) { $InstOriginal } else { $Originales }); instalador = $InstCsv; teatros = @($RTeatros) })
                }
                '/api/list' {
                    $t = [string]$q['t']; if ($null -eq $t) { $t = '' }
                    if (-not $RValidos.ContainsKey($t)) { Error404 $ctx; break }
                    if ($q['r'] -eq '1') { $Cache.Remove($t) }
                    Json $ctx @(Listar $t)
                }
                '/api/file' {
                    # p = ruta relativa a Data ; src = juego | editado
                    if ($q['src'] -eq 'editado') { $full = Ruta-Editado $q['p'] }
                    if ($q['src'] -ne 'editado' -or -not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
                        # (un .idx que no cambia no se guarda en el instalador: se usa el original)
                        # el original en ingles: Data_ORIGINAL si ya esta ahi; si no, el del juego
                        $full = Ruta-Original $q['p']
                        if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { $full = RutaSegura $Data $q['p'] }
                    }
                    if (-not $full -or $full -notmatch '\.(idx|rsc)$' -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { Error404 $ctx; break }
                    Responder $ctx 200 ([IO.File]::ReadAllBytes($full)) 'application/octet-stream'
                }
                '/api/save' {
                    if ($req.HttpMethod -ne 'POST') { Error404 $ctx; break }
                    $ri = $q['idx']; $rr = $q['rsc']
                    if ($ri -notmatch '\.idx$' -or $rr -notmatch '\.rsc$') { Error404 $ctx; break }
                    $jIdx = RutaSegura $Data $ri; $jRsc = RutaSegura $Data $rr
                    if (-not ($jIdx -and $jRsc)) { Error404 $ctx; break }
                    if (-not ((Test-Path -LiteralPath $jIdx) -and (Test-Path -LiteralPath $jRsc))) { Error404 $ctx; break }

                    # cuerpo: [uint32 longitud idx][idx][rsc]
                    $ms = New-Object IO.MemoryStream
                    $req.InputStream.CopyTo($ms); $req.InputStream.Close()
                    $b = $ms.ToArray()
                    if ($b.Length -lt 4) { Json $ctx ([ordered]@{ ok = $false; error = 'Datos vacíos' }); break }
                    $li = [BitConverter]::ToUInt32($b, 0)
                    if ($li -lt 8 -or 4 + $li + 8 -gt $b.Length) { Json $ctx ([ordered]@{ ok = $false; error = 'Datos incorrectos' }); break }
                    $bIdx = New-Object byte[] $li; [Array]::Copy($b, 4, $bIdx, 0, $li)
                    $lr = $b.Length - 4 - $li
                    $bRsc = New-Object byte[] $lr; [Array]::Copy($b, 4 + $li, $bRsc, 0, $lr)

                    $gi = Guardar-Editado $ri $bIdx 'RSC' $jIdx
                    $gr = Guardar-Editado $rr $bRsc 'RSC' $jRsc
                    $Cache.Clear()
                    Json $ctx ([ordered]@{ ok = $true; editados = @(@($gi.ruta, $gr.ruta) | Where-Object { $_ }); originales = @(@($gi.original, $gr.original) | Where-Object { $_ }); csv = @($gi.csv, $gr.csv); instalador = [bool]$InstCsv
                                           idxIgual = $gi.igual; rscIgual = $gr.igual; retirables = @(@($(if ($gi.retirable) { $gi.ruta }), $(if ($gr.retirable) { $gr.ruta })) | Where-Object { $_ }) })
                }
                '/api/uso' {
                    # .scf (y .irc) donde aparece un identificador, con las pantallas que los cargan
                    $t = [string]$q['t']; if ($null -eq $t) { $t = '' }
                    $id = [string]$q['id']
                    if (-not $RValidos.ContainsKey($t) -or $id -notmatch '^[A-Za-z0-9_]+$') { Error404 $ctx; break }
                    $a = Art-Ficheros $t
                    $re = New-Object Text.RegularExpressions.Regex(('(?<![A-Za-z0-9_])' + [regex]::Escape($id) + '(?![A-Za-z0-9_])'), 'IgnoreCase')
                    $out = New-Object System.Collections.ArrayList
                    foreach ($e in @($a.f.Values)) {
                        if ($e.ext -eq '.lst') { continue }
                        $m = $re.Match($e.txt); if (-not $m.Success) { continue }
                        $ini = $e.txt.LastIndexOf("`n", [Math]::Max(0, $m.Index - 1)) + 1
                        $fin = $e.txt.IndexOf("`n", $m.Index); if ($fin -lt 0) { $fin = $e.txt.Length }
                        $linea = $e.txt.Substring($ini, $fin - $ini).Trim(); if ($linea.Length -gt 140) { $linea = $linea.Substring(0, 140) + '…' }
                        $pant = @(); $k = $e.rel.ToLower()
                        if ($a.scf.ContainsKey($k)) { $pant = @($a.scf[$k]) }
                        if ($e.ext -eq '.irc' -and $a.res.ContainsKey($k)) { $pant = @($a.res[$k]) }
                        [void]$out.Add([ordered]@{ p = $e.rel; ext = $e.ext; general = $e.general; n = $re.Matches($e.txt).Count; linea = $linea; pantallas = $pant })
                    }
                    Json $ctx @($out)
                }
                '/api/carga' {
                    # pantallas que cargan un .rsc: .irc con [LOADRES] "...\nombre" que aparecen en una lista *_Res.lst
                    $t = [string]$q['t']; if ($null -eq $t) { $t = '' }
                    if (-not $RValidos.ContainsKey($t)) { Error404 $ctx; break }
                    $nombre = [IO.Path]::GetFileNameWithoutExtension([string]$q['rsc'])
                    $a = Art-Ficheros $t
                    $re = New-Object Text.RegularExpressions.Regex(('\[LOADRES\]\s+(\S+)\s+"[^"]*[\\/]' + [regex]::Escape($nombre) + '"'), 'IgnoreCase')
                    $ircs = New-Object System.Collections.ArrayList; $pant = New-Object System.Collections.ArrayList
                    foreach ($e in @($a.f.Values)) {
                        if ($e.ext -ne '.irc') { continue }
                        $m = $re.Match($e.txt); if (-not $m.Success) { continue }
                        [void]$ircs.Add([ordered]@{ p = $e.rel; recurso = $m.Groups[1].Value })
                        $k = $e.rel.ToLower()
                        if ($a.res.ContainsKey($k)) { foreach ($x in $a.res[$k]) { if (-not $pant.Contains($x)) { [void]$pant.Add($x) } } }
                    }
                    Json $ctx ([ordered]@{ ircs = @($ircs); pantallas = @($pant) })
                }
                default { Error404 $ctx }
            }
            }
            elseif ($modulo -eq 'voz' -or $modulo -eq 'vaj') {
            switch ($ruta) {
                '/api/ping' { Json $ctx 'ok' }
                '/api/info' {
                    Voz-Autodetectar
                    if ($q['buscar'] -eq '1') { Voz-Buscar-Tlk }
                    $kit = $VozCfg.kit
                    $teatros = @(foreach ($t in $VozTeatros) {
                        $ing = Voz-Tlk-Ingles $t
                        $lista = if ($kit) { Join-Path $kit ("Lista_" + $t.nombre + '.csv') } else { $null }
                        $mont = if ($kit) { Join-Path $kit ("Falcon_" + $t.nombre + '.tlk') } else { $null }
                        $ed = Ruta-Editado $t.rel
                        [ordered]@{
                            nombre = $t.nombre; rel = $t.rel
                            lista = [bool]($lista -and (Test-Path -LiteralPath $lista))
                            ingles = $ing.ruta; inglesSeguro = $ing.seguro
                            enOriginal = [bool]((Ruta-Original $t.rel) -and (Test-Path -LiteralPath (Ruta-Original $t.rel)))
                            montado = $(if ($mont -and (Test-Path -LiteralPath $mont)) { (Get-Item -LiteralPath $mont).LastWriteTime.ToString('dd/MM HH:mm') } else { '' })
                            montadoMs = $(if ($mont -and (Test-Path -LiteralPath $mont)) { [DateTimeOffset]::new((Get-Item -LiteralPath $mont).LastWriteTime).ToUnixTimeMilliseconds() } else { 0 })
                            enInstalador = $(if ($ed -and (Test-Path -LiteralPath $ed)) { (Get-Item -LiteralPath $ed).LastWriteTime.ToString('dd/MM HH:mm') } else { '' })
                        }
                    })
                    $ffok = $false
                    if ($VozCfg.ffmpeg) { $ffok = Voz-Ffmpeg-Ok }
                    Json $ctx ([ordered]@{
                        kit = $kit; python = $VozCfg.python; ffmpeg = $VozCfg.ffmpeg
                        okKit = [bool]($kit -and (Test-Path -LiteralPath (Join-Path $kit 'generar_voces.py')))
                        okPython = [bool]($VozCfg.python -and (Test-Path -LiteralPath $VozCfg.python))
                        okFfmpeg = $ffok; okXtts = (Voz-Xtts-Ok)
                        preparar = [bool]($kit -and (Test-Path -LiteralPath (Join-Path $kit 'Preparar_voces.ps1')))
                        instalador = $InstCsv; teatros = $teatros; trabajos = @(Voz-Estado-Trabajos); ajustes = $VozAj
                    })
                }
                '/api/elegir' {
                    $que = $q['que']
                    if ($que -notin @('kit', 'python', 'ffmpeg')) { Error404 $ctx; break }
                    $r = Voz-Elegir $que
                    if ($r) { $VozCfg[$que] = $r; Voz-Guardar-Cfg }
                    Json $ctx ([ordered]@{ ok = [bool]$r; ruta = $r })
                }
                '/api/lista' {
                    $t = Voz-Teatro $q['t']; if (-not $t -or -not $VozCfg.kit) { Error404 $ctx; break }
                    $p = Join-Path $VozCfg.kit ('Lista_' + $t.nombre + '.csv')
                    if (-not (Test-Path -LiteralPath $p)) { Error404 $ctx; break }
                    Responder $ctx 200 ([IO.File]::ReadAllBytes($p)) 'text/plain; charset=utf-8'
                }
                '/api/generados' {
                    $t = Voz-Teatro $q['t']; if (-not $t -or -not $VozCfg.kit) { Error404 $ctx; break }
                    $d = Join-Path $VozCfg.kit ('wav_es\' + $t.nombre)
                    $ids = @()
                    if (Test-Path -LiteralPath $d) { $ids = @([IO.Directory]::EnumerateFiles($d, '*.wav') | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) }
                    Json $ctx $ids
                }
                '/api/audio' {
                    $t = Voz-Teatro $q['t']; if (-not $t) { Error404 $ctx; break }
                    $id = 0; if (-not [int]::TryParse([string]$q['id'], [ref]$id)) { Error404 $ctx; break }
                    $desde = $null
                    if ($q['src'] -eq 'es') {
                        $p = Join-Path $VozCfg.kit ('wav_es\' + $t.nombre + '\' + $id + '.wav')
                        if (Test-Path -LiteralPath $p) { Responder $ctx 200 ([IO.File]::ReadAllBytes($p)) 'audio/wav'; break }
                        # sin wav: el clip del Falcon.tlk traducido del instalador
                        $ed = Ruta-Editado $t.rel
                        if (-not $ed -or -not (Test-Path -LiteralPath $ed -PathType Leaf)) { Error404 $ctx; break }
                        $desde = $ed
                    }
                    $ing = if ($desde) { @{ ruta = $desde } } else { Voz-Tlk-Ingles $t }
                    if (-not $ing.ruta -or -not (Test-Path -LiteralPath $ing.ruta)) { Error404 $ctx; break }
                    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('bmsvoz_' + [Guid]::NewGuid().ToString('N') + '.wav')
                    $r = Voz-Python @((Join-Path $VozCfg.kit 'voces_util.py'), 'extraer', '--tlk', $ing.ruta, '--id', "$id", '--salida', $tmp, '--ffmpeg', $VozCfg.ffmpeg)
                    if ($r.codigo -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { Write-Host ("Voces: " + $r.texto) -ForegroundColor Red; Responder $ctx 500 ([Text.Encoding]::UTF8.GetBytes($r.texto)) 'text/plain; charset=utf-8'; break }
                    $b = [IO.File]::ReadAllBytes($tmp); Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    Responder $ctx 200 $b 'audio/wav'
                }
                '/api/texto' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('bmsvoz_' + [Guid]::NewGuid().ToString('N') + '.txt')
                    [IO.File]::WriteAllText($tmp, [string]$c.es, (New-Object Text.UTF8Encoding($false)))
                    $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'texto', '--teatro', $t.nombre, '--id', ([string][int]$c.id), '--es-fichero', $tmp)
                    # subtitulos: el F4Talk.csv de cada teatro en el instalador (Ficheros) se actualiza a la vez
                    $mapa = @{ 'COREA' = 'Corea'; 'BALCANES' = 'Balcanes'; 'GRECIA' = 'Grecia'; 'ISRAEL' = 'Israel' }
                    foreach ($f in (Leer-Csv)) {
                        if ([IO.Path]::GetFileName($f.data) -ieq 'F4Talk.csv' -and $mapa.ContainsKey($f.clave.ToUpper())) {
                            $ruta = RutaSegura $InstFicheros $f.fich
                            if ($ruta -and (Test-Path -LiteralPath $ruta)) { $a += @('--f4talk', ($mapa[$f.clave.ToUpper()] + '=' + $ruta)) }
                        }
                    }
                    $a += @('--respaldo', (Join-Path $Respaldo 'F4Talk'))
                    $r = Voz-Python $a
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    if ($r.codigo -ne 0) { Json $ctx ([ordered]@{ ok = $false; error = $r.texto }); break }
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                }
                '/api/generar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $a = @((Join-Path $VozCfg.kit 'generar_voces.py'))
                    $teatro = [string]$c.t
                    if ($teatro -ne 'todos' -and -not (Voz-Teatro $teatro)) { $teatro = 'todos' }
                    $a += @('--teatro', $teatro)
                    $titulo = "Generando voces ($teatro)"
                    if ($c.ids) {
                        $ids = @($c.ids | ForEach-Object { [int]$_ }) -join ','
                        $a += @('--ids', $ids, '--forzar'); $titulo = "Regenerando $ids ($teatro)"
                    }
                    if ($c.prueba) { $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--prueba', ([string][int]$c.prueba)); $titulo = 'Prueba de voces' }
                    if ($c.comparar) { $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--comparar', ([string][int]$c.comparar)); $titulo = 'Comparando ajustes de voz' }
                    if ($c.refiltrar) { $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', 'todos', '--refiltrar'); $titulo = 'Aplicando efectos de radio y volumen' }
                    $a += @(Voz-Args-Ajustes)
                    if ($c.igual -in @('todo', 'nada')) { $a += @('--igual', [string]$c.igual) }
                    if ($null -ne $c.rehacerVoz) { $vv = [int]$c.rehacerVoz; $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', 'todos', '--voces', "$vv", '--rehacer') + @(Voz-Args-Ajustes); $titulo = ('Regenerando la voz {0:D2} (4 teatros)' -f $vv) }
                    $id = Voz-Lanzar 'generar' $teatro $titulo $a
                    Json $ctx ([ordered]@{ ok = $true; id = $id })
                }
                '/api/montar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $a = Voz-Args-Montar $t
                    $id = Voz-Lanzar 'montar' $t.nombre ("Montando Falcon.tlk de " + $t.nombre) $a
                    Json $ctx ([ordered]@{ ok = $true; id = $id })
                }
                '/api/regmontar' {
                    # regenera un clip y monta el Falcon.tlk de los teatros que lo usan (luego la página lo guarda en el instalador)
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $id = [int]$c.id
                    # los tlkId comunes (< 33386) son los mismos en los 4 teatros
                    $afect = @(if ($id -lt 33386) { $VozTeatros | Where-Object { Test-Path -LiteralPath (Join-Path $VozCfg.kit ('Lista_' + $_.nombre + '.csv')) } } else { $t })
                    $pasos = New-Object System.Collections.ArrayList
                    [void]$pasos.Add(@((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', $(if ($id -lt 33386) { 'todos' } else { $t.nombre }), '--ids', "$id", '--forzar') + @(Voz-Args-Ajustes))
                    foreach ($x in $afect) { [void]$pasos.Add((Voz-Args-Montar $x)) }
                    $nombres = @($afect | ForEach-Object { $_.nombre })
                    $jid = Voz-Lanzar-Cadena 'regmontar' $nombres ("Regenerando $id y montando " + ($nombres -join ', ')) $pasos
                    Json $ctx ([ordered]@{ ok = $true; id = $jid; teatros = $nombres })
                }
                '/api/trabajos' { Json $ctx @(Voz-Estado-Trabajos) }
                '/api/ref-candidatos' {
                    $t = Voz-Teatro 'Corea'; if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'No se encuentra el Falcon.tlk de Corea.' }); break }
                    $ing = Voz-Tlk-Ingles $t
                    $r = Voz-Python @((Join-Path $VozCfg.kit 'voces_util.py'), 'candidatos', '--voz', ([string][int]$q['voz']), '--tlk', $ing.ruta, '--ffmpeg', $VozCfg.ffmpeg)
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $linea) { Json $ctx ([ordered]@{ ok = $false; error = $r.texto }); break }
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                }
                '/api/ref-crear' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro 'Corea'; if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'No se encuentra el Falcon.tlk de Corea.' }); break }
                    $ing = Voz-Tlk-Ingles $t
                    $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'referencia', '--voz', ([string][int]$c.voz), '--tlk', $ing.ruta, '--ffmpeg', $VozCfg.ffmpeg)
                    if ($c.inicial) { $a += '--inicial' } elseif ($c.auto) { $a += '--auto' } else { $a += @('--ids', ((@($c.ids) | ForEach-Object { [int]$_ }) -join ',')) }
                    $r = Voz-Python $a
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $linea) { Json $ctx ([ordered]@{ ok = $false; error = ($r.texto -split "`n" | Select-Object -Last 1) }); break }
                    Write-Host ('Voces: nueva referencia para la voz {0:D2}' -f [int]$c.voz)
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                }
                '/api/servidor' {
                    if ($req.HttpMethod -eq 'POST') { Voz-Srv-Arrancar }
                    Json $ctx ([ordered]@{ enMarcha = (Voz-Srv-Vivo); puerto = $VozSrv.puerto; token = $(if (Voz-Srv-Vivo) { $VozSrv.token } else { '' }) })
                }
                '/api/ajustes-voces' {
                    if ($req.HttpMethod -eq 'POST') {
                        $c = Voz-Leer-Cuerpo $req
                        $v = [int]$c.voz; if ($v -lt 0 -or $v -gt 13) { Json $ctx ([ordered]@{ ok = $false; error = 'voz no válida' }); break }
                        $h = Voz-Aj-Leer; $k = '{0:D2}' -f $v
                        if ($null -eq $c.ajustes) { $h.Remove($k) }
                        else {
                            $o = [ordered]@{}
                            foreach ($n in 'temperatura', 'velocidad', 'rms', 'radio', 'suavizado', 'limpieza', 'pausaInicio', 'pausaFin') {
                                if ($null -eq $c.ajustes.$n) { continue }
                                $x = [double]$c.ajustes.$n; $r = $VozAjRango[$n]
                                if ($x -lt $r[0]) { $x = $r[0] }; if ($x -gt $r[1]) { $x = $r[1] }
                                $o[$n] = $x
                            }
                            if ($c.ajustes.texto) { $o['texto'] = [string]$c.ajustes.texto }
                            $h[$k] = $o
                        }
                        $ord = [ordered]@{}; foreach ($n in ($h.Keys | Sort-Object)) { $ord[$n] = $h[$n] }
                        [IO.File]::WriteAllText((Voz-Aj-Fich), (ConvertTo-Json -InputObject $ord -Depth 4), (New-Object Text.UTF8Encoding($false)))
                        Write-Host ("Voces: ajustes de la voz " + $k + $(if ($null -eq $c.ajustes) { ' eliminados' } else { ' guardados' }))
                    }
                    Json $ctx ([ordered]@{ ok = $true; voces = (Voz-Aj-Leer); generales = $VozAj })
                }
                '/api/pruebas' {
                    # wav de Voces\prueba (Prueba 30) y Voces\prueba\comparar (Comparar ajustes)
                    $base = Join-Path $VozCfg.kit 'prueba'
                    $lista = @()
                    if ($VozCfg.kit -and (Test-Path -LiteralPath $base)) {
                        $lista = @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.wav' | Sort-Object FullName | ForEach-Object {
                            [ordered]@{ f = $_.FullName.Substring($base.Length).TrimStart('\'); fecha = $_.LastWriteTime.ToString('dd/MM HH:mm') }
                        })
                    }
                    Json $ctx $lista
                }
                '/api/prueba-audio' {
                    $p = RutaSegura (Join-Path $VozCfg.kit 'prueba') ([string]$q['f'])
                    if (-not $p -or -not $p.EndsWith('.wav', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { Error404 $ctx; break }
                    Responder $ctx 200 ([IO.File]::ReadAllBytes($p)) 'audio/wav'
                }
                '/api/ajustes' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    foreach ($k in @($VozAj.Keys)) {
                        if ($null -ne $c.$k) {
                            $v = [double]$c.$k; $r = $VozAjRango[$k]
                            if ($v -lt $r[0]) { $v = $r[0] }; if ($v -gt $r[1]) { $v = $r[1] }
                            $VozAj[$k] = $v
                        }
                    }
                    Voz-Guardar-Cfg
                    Json $ctx ([ordered]@{ ok = $true; ajustes = $VozAj })
                }
                '/api/preparar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $ps1 = Join-Path $VozCfg.kit 'Preparar_voces.ps1'
                    if (-not (Test-Path -LiteralPath $ps1)) { Json $ctx ([ordered]@{ ok = $false; error = 'No está Preparar_voces.ps1 en el kit.' }); break }
                    $id = Voz-Lanzar 'preparar' '' 'Preparando el entorno de voces' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1) (Join-Path $PSHOME 'powershell.exe')
                    Json $ctx ([ordered]@{ ok = $true; id = $id })
                }
                '/api/guardar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    if (-not $InstCsv) { Json $ctx ([ordered]@{ ok = $false; error = 'No se ha encontrado el instalador (Instalador\Archivos.csv).' }); break }
                    foreach ($w in $VozTrabajos) { if ($w.tipo -eq 'montar' -and $w.teatro -eq $t.nombre -and -not $w.proc.HasExited) { throw 'El montaje de este teatro aún está en marcha.' } }
                    $mont = Join-Path $VozCfg.kit ("Falcon_" + $t.nombre + '.tlk')
                    if (-not (Test-Path -LiteralPath $mont)) { Json $ctx ([ordered]@{ ok = $false; error = 'Primero hay que montar el Falcon.tlk de este teatro.' }); break }
                    $ing = Voz-Tlk-Ingles $t
                    $g = Guardar-Editado $t.rel ([IO.File]::ReadAllBytes($mont)) 'VOCES' $(if ($ing.seguro) { $ing.ruta } else { $null })
                    Json $ctx ([ordered]@{ ok = $true; ruta = $g.ruta; original = $g.original; csv = $g.csv })
                }
                default { Error404 $ctx }
            }
            }
            else {
            if (-not $InstCsv -and $ruta -ne '/api/ping') { Responder $ctx 404 ([Text.Encoding]::UTF8.GetBytes('sin instalador')) 'text/plain'; continue }
            switch ($ruta) {
                '/api/ping' { Json $ctx 'ok' }
                '/api/info' {
                    $lista = @(foreach ($f in $Filas) {
                        [ordered]@{ i = $f.i; teatro = $f.teatro; fich = $f.fich; data = $f.data
                                    hayFich = [bool](Test-Path -LiteralPath (Ruta-De $f 'fich') -PathType Leaf) }
                    })
                    Json $ctx ([ordered]@{ csv = $InstCsv; ficheros = $InstFicheros; original = $InstOriginal; data = $Data; filas = $lista })
                }
                '/api/get' {
                    $f = Fila-De $q
                    if (-not $f) { Error404 $ctx; break }
                    $full = Ruta-De $f $q['src']
                    if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { Error404 $ctx; break }
                    $fs = [IO.File]::Open($full, 'Open', 'Read', 'ReadWrite')
                    try {
                        $buf = New-Object byte[] $fs.Length
                        $leido = 0
                        while ($leido -lt $buf.Length) { $n = $fs.Read($buf, $leido, $buf.Length - $leido); if ($n -le 0) { break }; $leido += $n }
                    } finally { $fs.Close() }
                    Responder $ctx 200 $buf 'application/octet-stream'
                }
                '/api/put' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $f = Fila-De $q
                    if (-not $f) { Json $ctx ([ordered]@{ ok = $false; error = 'fila no válida' }); break }
                    $full = Ruta-De $f 'fich'
                    $ms = New-Object IO.MemoryStream
                    $req.InputStream.CopyTo($ms)
                    $bytes = $ms.ToArray()
                    if ($bytes.Length -lt 16) { Json $ctx ([ordered]@{ ok = $false; error = 'contenido vacío' }); break }
                    # copia del fichero tal y como estaba, solo la primera vez
                    $resp = $null
                    if (Test-Path -LiteralPath $full -PathType Leaf) {
                        $dst = Join-Path $Respaldo $f.fich
                        if (-not (Test-Path -LiteralPath $dst)) {
                            $dir = Split-Path $dst -Parent
                            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                            Copy-Item -LiteralPath $full -Destination $dst -Force
                            $resp = $dst
                            Write-Host ("Respaldo:  " + $dst)
                        }
                    }
                    # se escribe en un temporal y luego se reemplaza (no queda a medias)
                    $dir = Split-Path $full -Parent
                    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                    $tmp = $full + '.tmp'
                    [IO.File]::WriteAllBytes($tmp, $bytes)
                    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
                    Move-Item -LiteralPath $tmp -Destination $full
                    Write-Host ("Guardado:  " + $full)
                    Json $ctx ([ordered]@{ ok = $true; ruta = $full; respaldo = $resp })
                }
                default { Error404 $ctx }
            }
            }
        } catch {
            Write-Host ("Error: " + $_.Exception.Message) -ForegroundColor Red
            try { Json $ctx ([ordered]@{ ok = $false; error = $_.Exception.Message }) } catch { }
        }
    }
} finally {
    $Listener.Stop(); $Listener.Close()
    try { Remove-Item -LiteralPath $UrlFich -Force -ErrorAction SilentlyContinue } catch { }
    try { $Mutex.ReleaseMutex() } catch { }
}
