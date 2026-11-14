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
# Si el que está abierto es de una versión anterior (se han copiado ficheros nuevos encima), se le pide que se
# cierre y arranca este: si no, seguiría funcionando el código viejo aunque las páginas fueran las nuevas.
$UrlFich = Join-Path $env:LOCALAPPDATA 'Editor_BMS_url.txt'
$VerFich = Join-Path $env:LOCALAPPDATA 'Editor_BMS_ver.txt'
function Editor-Version {
    $v = @()
    foreach ($f in @($PSCommandPath, (Join-Path $PSScriptRoot 'Teatros.ps1'))) {
        if ($f -and (Test-Path -LiteralPath $f)) { $i = Get-Item -LiteralPath $f; $v += ('' + $i.Length + '-' + $i.LastWriteTimeUtc.Ticks) }
    }
    return ($v -join '|')
}
$creado = $false
$Mutex = New-Object System.Threading.Mutex($true, 'Local\Editor_BMS_Traduccion', [ref]$creado)
if (-not $creado) {
    $verVieja = $null; try { $verVieja = ([IO.File]::ReadAllText($VerFich)).Trim() } catch { }
    if ($verVieja -ne (Editor-Version)) {
        # el abierto es otra version: se le pide que se cierre y se espera a que suelte el editor
        try {
            $url0 = ([IO.File]::ReadAllText($UrlFich)).Trim()
            $k0 = ($url0 -replace '^.*[?&]k=', '')
            [void](Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri ($url0.Split('?')[0].TrimEnd('/') + '/salir?k=' + $k0))
        } catch { }
        try { $creado = $Mutex.WaitOne(20000) }
        catch {
            # el otro se cerro sin soltarlo (p. ej. ventana cerrada a mano): igualmente pasa a ser de este
            $e = $_.Exception; while ($e -and -not ($e -is [System.Threading.AbandonedMutexException])) { $e = $e.InnerException }
            if ($e) { $creado = $true }
        }
        if (-not $creado) {
            [void][System.Windows.Forms.MessageBox]::Show("Hay abierto un Editor de Falcon BMS de una versión anterior y no se ha cerrado solo.`n`nCierra su ventana (minimizada en la barra de tareas, «Editor de Falcon BMS») y vuelve a abrir el editor.", 'Editor de Falcon BMS', 'OK', 'Warning')
            exit 0
        }
    }
}
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
$I18nJs     = Join-Path $Aqui 'i18n.js'
$IdiomaFich = Join-Path $Aqui 'idioma.txt'
$Paginas    = @{ 'scf' = (Join-Path $Aqui 'scf.html'); 'rsc' = (Join-Path $Aqui 'rsc.html'); 'camp' = (Join-Path $Aqui 'campana.html'); 'voz' = (Join-Path $Aqui 'voces.html'); 'vaj' = (Join-Path $Aqui 'voces_ajuste.html'); 'teat' = (Join-Path $Aqui 'teatros.html'); 'str' = (Join-Path $Aqui 'strings.html'); 'tac' = (Join-Path $Aqui 'tacref.html'); 'ayu' = (Join-Path $Aqui 'ayuda.html') }
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
# Cada idioma de la traduccion tiene su Archivos.csv y su carpeta Ficheros (Idiomas\<CODIGO>, ver
# Instalador\Idiomas.ps1). El editor trabaja sobre el "idioma de trabajo" (el mismo que elige el instalador).
$InstDir = $null; $InstCsv = $null; $InstFicheros = $null; $InstOriginal = $null; $InstIdi = $null; $Idiomas = @()
$d = $Aqui
for ($i = 0; $i -lt 4 -and $d; $i++) {
    foreach ($cand in @((Join-Path $d 'Instalador'), $d)) {
        if (Test-Path -LiteralPath (Join-Path $cand 'Instalador.ps1')) { $InstDir = $cand; break }
    }
    if ($InstDir) { break }
    $d = Split-Path $d -Parent
}
if ($InstDir) {
    $dentro = Join-Path $InstDir 'Data_ORIGINAL'
    $InstOriginal = if (Test-Path -LiteralPath $dentro) { $dentro } else { Join-Path (Split-Path $InstDir -Parent) 'Data_ORIGINAL' }
    $mod = Join-Path $InstDir 'Idiomas.ps1'
    if (Test-Path -LiteralPath $mod) { . $mod }
}
if (-not (Get-Command Idiomas-Lista -ErrorAction SilentlyContinue)) {
    # instalador antiguo (sin Idiomas.ps1): un solo idioma, Archivos.csv junto al instalador
    function Idiomas-Lista([string]$dir) {
        $c = Join-Path $dir 'Archivos.csv'
        if (-not (Test-Path -LiteralPath $c)) { return @() }
        $f = Join-Path $dir 'Ficheros'; if (-not (Test-Path -LiteralPath $f)) { $f = Join-Path (Split-Path $dir -Parent) 'Ficheros' }
        return @([pscustomobject]@{ codigo = 'ES'; nombre = 'Español'; nombreEs = 'español'; voz = 'es'; codificacion = 1252; dir = $dir; csv = $c; ficheros = $f; legado = $true })
    }
    function Idioma-Actual([string]$dir, $lista) { return (@($lista) | Select-Object -First 1) }
    function Idioma-Poner-Actual([string]$dir, [string]$cod) { }
}
# Elige el idioma de trabajo ($cod vacio = el guardado en Idiomas\actual.txt) y recarga lo que depende de el
function Poner-Idioma-Trabajo([string]$cod) {
    $script:Idiomas = @()
    if ($script:InstDir) { $script:Idiomas = @(Idiomas-Lista $script:InstDir) }
    $sel = $null
    if ($cod) { $sel = @($script:Idiomas | Where-Object { $_.codigo -eq $cod.ToUpper() }) | Select-Object -First 1 }
    if (-not $sel -and $script:Idiomas.Count) { $sel = Idioma-Actual $script:InstDir $script:Idiomas }
    $script:InstIdi = $sel
    $script:InstCsv = $null; $script:InstFicheros = $null
    if ($sel -and (Test-Path -LiteralPath $sel.csv)) { $script:InstCsv = $sel.csv; $script:InstFicheros = $sel.ficheros }
    if ($cod -and $sel -and -not $sel.legado) { Idioma-Poner-Actual $script:InstDir $sel.codigo }
    if (Get-Command Cargar-Filas-Camp -ErrorAction SilentlyContinue) { Cargar-Filas-Camp }
}
function Info-Idiomas {
    return [ordered]@{
        instalador = [bool]$script:InstDir
        legado = [bool]($script:InstIdi -and $script:InstIdi.legado)
        modulo = [bool](Get-Command Idioma-Crear -ErrorAction SilentlyContinue)
        actual = $(if ($script:InstIdi) { [ordered]@{ codigo = $script:InstIdi.codigo; nombre = $script:InstIdi.nombre; nombreEs = $script:InstIdi.nombreEs } } else { $null })
        lista = @($script:Idiomas | ForEach-Object { [ordered]@{ codigo = $_.codigo; nombre = $_.nombre; nombreEs = $_.nombreEs; csv = $_.csv } })
    }
}
Poner-Idioma-Trabajo ''

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

# ---------- teatros (Teatros.ps1 del instalador, o la copia del editor) ----------
# los conocidos y cualquier "Add-On <Nombre>" de Data con pinta de teatro o que salga en Archivos.csv
foreach ($m in @($(if ($InstDir) { Join-Path $InstDir 'Teatros.ps1' }), (Join-Path $Aqui 'Teatros.ps1'))) {
    if ($m -and (Test-Path -LiteralPath $m)) { . $m; break }
}
if (-not (Get-Command Teatros-Detectar -ErrorAction SilentlyContinue)) { Aviso "Falta Teatros.ps1 (junto al editor o al instalador)." 'Error'; exit 1 }
$Teatros = @(Teatros-Detectar $Data @($script:Idiomas | ForEach-Object { $_.csv }))
$ClaveTeatro = @{ 'Art' = 'COREA' }; foreach ($t in $Teatros) { if ($t.Carpeta) { $ClaveTeatro[$t.Carpeta] = $t.Clave } }
foreach ($t in $Teatros) { if ($t.Carpeta) { Write-Host ("Teatro:    " + $t.Nombre + "  (" + $t.Carpeta + ", " + $t.Clave + ")") } }

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
    # si el navegador ya cerro la peticion (cambio de pagina, otro audio, filtro nuevo...) no hay a quien responder: no es un error
    try {
        if ($cuerpo) { $r.ContentLength64 = $cuerpo.Length; $r.OutputStream.Write($cuerpo, 0, $cuerpo.Length) }
        $r.OutputStream.Close()
    } catch {
        try { $r.Abort() } catch { }
    }
}
function Json($ctx, $obj) {
    $txt = if ($null -eq $obj) { 'null' } else { ConvertTo-Json -InputObject $obj -Depth 6 -Compress }
    if ($null -eq $txt) { $txt = 'null' }     # PowerShell 5.1 devuelve nada (no "null") en algunos casos
    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes([string]$txt)) 'application/json; charset=utf-8'
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
    return (Teatro-Clave-De-Ruta $Teatros $rel)
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
# cambia el fichero (columna Ficheros) de la linea de rel en Archivos.csv
function Cambiar-Csv-Fich([string]$rel, [string]$fich) {
    $bytes = [IO.File]::ReadAllBytes($InstCsv)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $texto = [Text.Encoding]::UTF8.GetString($bytes); if ($bom) { $texto = $texto.Substring(1) }
    $nl = if ($texto.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lineas = @($texto -split "`r?`n")
    for ($i = 0; $i -lt $lineas.Count; $i++) {
        $c = $lineas[$i].Split(';')
        if ($c.Count -ge 3 -and $c[2].Trim() -ieq $rel) { $c[1] = $fich; $lineas[$i] = $c -join ';' }
    }
    [IO.File]::WriteAllText($InstCsv, ($lineas -join $nl), (New-Object Text.UTF8Encoding($bom)))
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
$Nombres = @{}; foreach ($t in $Teatros) { if ($t.Carpeta) { $Nombres[$t.Carpeta] = $t.Nombre } }
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
# Editor de teatros: .tdf (nombre y descripcion), .tga (portada) y Theater.irc (paises, bandos, campanas)
# =====================================================================
$TeatDefs = @(foreach ($t in $Teatros) { if ($null -ne $t.Carpeta) { [ordered]@{ clave = $t.Clave; nombre = $t.Corto; pre = $t.Carpeta } } })
# rutas (columna Data) de un teatro en los Archivos.csv de todos los idiomas
function Teat-Rels-Csv([string]$clave) {
    $r = @()
    $csvs = @(); foreach ($i in $script:Idiomas) { if ($i.csv -and (Test-Path -LiteralPath $i.csv)) { $csvs += $i.csv } }
    foreach ($c in $csvs) {
        foreach ($l in ([IO.File]::ReadAllText($c, [Text.Encoding]::UTF8) -split "`r?`n")) {
            $x = $l.TrimStart([char]0xFEFF).Split(';')
            if ($x.Count -ge 3 -and $x[0].Trim() -ieq $clave -and $x[2].Trim()) { $r += $x[2].Trim() }
        }
    }
    return @($r | Select-Object -Unique)
}
function Teat-Existe([string]$rel) {
    foreach ($b in @($Data, $InstOriginal)) { if ($b) { $p = RutaSegura $b $rel; if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $true } } }
    $e = Ruta-Editado $rel; return [bool]($e -and (Test-Path -LiteralPath $e -PathType Leaf))
}
function Teat-Ed([string]$rel) { $e = Ruta-Editado $rel; return [bool]($e -and (Test-Path -LiteralPath $e -PathType Leaf)) }
# ed = la version editada (o, si no hay, el original); en = el original en ingles (Data_ORIGINAL, o el juego si
# no tiene instalada una traduccion de ese fichero)
function Teat-Ruta([string]$rel, [string]$src) {
    if ($src -eq 'ed') { $e = Ruta-Editado $rel; if ($e -and (Test-Path -LiteralPath $e -PathType Leaf)) { return $e } }
    $o = Ruta-Original $rel
    if ($o -and (Test-Path -LiteralPath $o -PathType Leaf)) { return $o }
    $g = RutaSegura $Data $rel
    if ($g -and (Test-Path -LiteralPath $g -PathType Leaf) -and ($src -eq 'ed' -or -not (Voz-Espanol-Instalado $rel))) { return $g }
    return $null
}
function Teat-Lista {
    $out = @()
    foreach ($d in $TeatDefs) {
        if ($d.pre -and -not (Test-Path -LiteralPath (Join-Path $Data $d.pre))) { continue }
        $pre = $(if ($d.pre) { $d.pre + '\' } else { '' })
        $rels = @(Teat-Rels-Csv $d.clave)
        $irc = @($rels | Where-Object { $_ -match '(^|\\)Theater\.irc$' })
        if (-not $irc.Count) { foreach ($c in 'Art\main\Theater.irc', 'Art\_FHD\Main\Theater.irc') { if (Teat-Existe ($pre + $c)) { $irc += ($pre + $c) } } }
        $tdf = @($rels | Where-Object { $_ -match '\.tdf$' }) | Select-Object -First 1
        if (-not $tdf) {
            foreach ($c in 'TerrData\theaterdefinition', 'theaterdefinition') {
                $dir = Join-Path $Data ($pre + $c)
                if (-not (Test-Path -LiteralPath $dir)) { continue }
                $f = Get-ChildItem -LiteralPath $dir -Filter '*.tdf' -File -ErrorAction SilentlyContinue | Sort-Object @{ e = { if ($d.clave -eq 'COREA' -and $_.Name -like 'Korea*') { 0 } else { 1 } } }, Name | Select-Object -First 1
                if ($f) { $tdf = $pre + $c + '\' + $f.Name; break }
            }
        }
        $tga = @($rels | Where-Object { $_ -match '\.tga$' }) | Select-Object -First 1
        if (-not $tga -and $tdf) {
            # la portada es la que indica la linea "bitmap" del .tdf (ruta dentro de Data)
            $p = Teat-Ruta $tdf 'ed'
            if ($p) { $m = [regex]::Match([IO.File]::ReadAllText($p, [Text.Encoding]::GetEncoding(1252)), '(?im)^[ \t]*bitmap[ \t]+([^\r\n]+)'); if ($m.Success) { $tga = $m.Groups[1].Value.Trim() } }
        }
        if (-not $irc.Count -and -not $tdf) { continue }
        $out += [ordered]@{ clave = $d.clave; nombre = $d.nombre; tdf = $tdf; tga = $tga; irc = @($irc | Select-Object -Unique)
                            tdfEd = [bool]($tdf -and (Teat-Ed $tdf)); tgaEd = [bool]($tga -and (Teat-Ed $tga)); ircEd = @($irc | Select-Object -Unique | ForEach-Object { Teat-Ed $_ }) }
    }
    return $out
}
# Strings.txt de cada teatro (textos del juego: comunes o propios del teatro)
# un fichero por teatro (Strings.txt, TacRefDB.xml): el de Archivos.csv, o el del juego si existe
function Lista-Por-Teatro([string]$patron, [string]$defecto) {
    $out = @()
    foreach ($d in $TeatDefs) {
        if ($d.pre -and -not (Test-Path -LiteralPath (Join-Path $Data $d.pre))) { continue }
        $rel = @(Teat-Rels-Csv $d.clave | Where-Object { $_ -match $patron }) | Select-Object -First 1
        if (-not $rel) { $c = $(if ($d.pre) { $d.pre + '\' } else { '' }) + $defecto; if (Teat-Existe $c) { $rel = $c } }
        if (-not $rel) { continue }
        $out += [ordered]@{ clave = $d.clave; nombre = $d.nombre; rel = $rel; ed = (Teat-Ed $rel) }
    }
    return $out
}
function Str-Lista { return @(Lista-Por-Teatro '(^|\\)Campaign\\Strings\.txt$' 'Campaign\Strings.txt') }
function Tac-Lista { return @(Lista-Por-Teatro '(^|\\)TerrData\\TacRefDB\.xml$' 'TerrData\TacRefDB.xml') }
function Mod-Lista([string]$modulo) { switch ($modulo) { 'str' { return @(Str-Lista) } 'tac' { return @(Tac-Lista) } default { return @(Teat-Lista) } } }
function Mod-Permitido([string]$modulo, [string]$rel) {
    if (-not $rel) { return $false }
    foreach ($t in (Mod-Lista $modulo)) { foreach ($r in @($t.tdf, $t.tga, $t.rel) + @($t.irc)) { if ($r -and $r -ieq $rel) { return $true } } }
    return $false
}

# =====================================================================
# Ayuda y menus: GuideTxt.irc, HelpText.irc, Menu.dat y LckTxtRc.irc ("base + cambios" por teatro)
# =====================================================================
# LckTxtRc.irc del idioma de trabajo segun Archivos.csv: la base (comun) o el fichero de cambios del teatro
function Lck-Fichero([string]$clave, [switch]$Cambios) {
    if (-not $InstCsv) { return $null }
    foreach ($l in ([IO.File]::ReadAllText($InstCsv, [Text.Encoding]::UTF8) -split "`r?`n")) {
        $c = $l.TrimStart([char]0xFEFF).Split(';')
        if ($c.Count -ge 3 -and $c[0].Trim() -ieq $clave -and $c[2].Trim() -match '(^|\\)LckTxtRc\.irc$') {
            $partes = @($c[1] -split '\+')
            if ($Cambios) { if ($partes.Count -lt 2) { return $null }; return (RutaSegura $InstFicheros $partes[1].Trim()) }
            return (RutaSegura $InstFicheros $partes[0].Trim())
        }
    }
    return $null
}
function Lck-Rels([string]$clave) {
    $r = @()
    if (-not $InstCsv) { return $r }
    foreach ($l in ([IO.File]::ReadAllText($InstCsv, [Text.Encoding]::UTF8) -split "`r?`n")) {
        $c = $l.TrimStart([char]0xFEFF).Split(';')
        if ($c.Count -ge 3 -and $c[0].Trim() -ieq $clave -and $c[2].Trim() -match '(^|\\)LckTxtRc\.irc$') { $r += $c[2].Trim() }
    }
    return $r
}
# pone "base + LckTxtRc\Cambios_<T>.irc" en las lineas del LckTxtRc.irc del teatro en Archivos.csv
function Lck-Csv-Cambios([string]$clave, [string]$fich) {
    $bytes = [IO.File]::ReadAllBytes($InstCsv)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $texto = [Text.Encoding]::UTF8.GetString($bytes); if ($bom) { $texto = $texto.Substring(1) }
    $nl = if ($texto.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lineas = @($texto -split "`r?`n")
    for ($i = 0; $i -lt $lineas.Count; $i++) {
        $c = $lineas[$i].Split(';')
        if ($c.Count -ge 3 -and $c[0].Trim() -ieq $clave -and $c[2].Trim() -match '(^|\\)LckTxtRc\.irc$' -and $c[1] -notmatch '\+') {
            $c[1] = $c[1].Trim() + ' + ' + $fich; $lineas[$i] = $c -join ';'
        }
    }
    $nuevo = [Text.Encoding]::UTF8.GetBytes(($lineas -join $nl))
    if ($bom) { $nuevo = [byte[]](0xEF, 0xBB, 0xBF) + $nuevo }
    [IO.File]::WriteAllBytes($InstCsv, $nuevo)
}
# copia en Data_ORIGINAL del fichero del juego, si falta y no es ya una traduccion instalada
function Asegurar-Original([string]$rel) {
    $o = Ruta-Original $rel
    if (-not $o -or (Test-Path -LiteralPath $o -PathType Leaf)) { return }
    $g = RutaSegura $Data $rel
    if ($g -and (Test-Path -LiteralPath $g -PathType Leaf) -and -not (Voz-Espanol-Instalado $rel)) { Copiar-A $g $o; Write-Host ("Original:  " + $o) }
}
# columna Ficheros del LckTxtRc.irc base (la de Corea)
function Lck-Base-Fich {
    if (-not $InstCsv) { return $null }
    foreach ($l in ([IO.File]::ReadAllText($InstCsv, [Text.Encoding]::UTF8) -split "`r?`n")) {
        $c = $l.TrimStart([char]0xFEFF).Split(';')
        if ($c.Count -ge 3 -and $c[0].Trim() -ieq 'COREA' -and $c[2].Trim() -match '(^|\\)LckTxtRc\.irc$') { return (@($c[1] -split '\+')[0]).Trim() }
    }
    return $null
}
# lineas nuevas en Archivos.csv para el LckTxtRc.irc de un teatro que aun no tenia ("base" o "base + cambios")
function Lck-Anadir-Filas($teat, [string]$fich) {
    $bytes = [IO.File]::ReadAllBytes($InstCsv)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $texto = [Text.Encoding]::UTF8.GetString($bytes); if ($bom) { $texto = $texto.Substring(1) }
    $nl = if ($texto.Contains("`r`n")) { "`r`n" } else { "`n" }
    if ($texto -and -not $texto.EndsWith("`n")) { $texto += $nl }
    foreach ($rel in $teat.rels) { $texto += ($teat.clave + ';' + $fich + ';' + $rel + $nl); Write-Host ("Archivos.csv: " + $teat.clave + ';' + $fich + ';' + $rel) }
    $nuevo = [Text.Encoding]::UTF8.GetBytes($texto)
    if ($bom) { $nuevo = [byte[]](0xEF, 0xBB, 0xBF) + $nuevo }
    [IO.File]::WriteAllBytes($InstCsv, $nuevo)
}
function Ayu-Lista {
    $r = [ordered]@{ guia = $null; ayuda = $null; menu = @(); lck = @(); lckBase = $false; instalador = [bool]$InstCsv }
    if (Teat-Existe 'Art\Help\GuideTxt.irc') { $r.guia = 'Art\Help\GuideTxt.irc' }
    if (Teat-Existe 'Art\Help\HelpText.irc') { $r.ayuda = 'Art\Help\HelpText.irc' }
    foreach ($d in $TeatDefs) {
        if ($d.pre -and -not (Test-Path -LiteralPath (Join-Path $Data $d.pre))) { continue }
        $pre = $(if ($d.pre) { $d.pre + '\' } else { '' })
        $m = @(Teat-Rels-Csv $d.clave | Where-Object { $_ -match '(^|\\)Menu\.dat$' }) | Select-Object -First 1
        if (-not $m -and (Teat-Existe ($pre + 'Art\CkptArt\Menu.dat'))) { $m = $pre + 'Art\CkptArt\Menu.dat' }
        if ($m) { $r.menu += [ordered]@{ clave = $d.clave; nombre = $d.nombre; rel = $m; ed = (Teat-Ed $m) } }
        $l = @(Lck-Rels $d.clave); $nuevo = $false
        if (-not $l.Count) {
            # teatro aun sin LckTxtRc en Archivos.csv (p. ej. un Add-On nuevo): los del juego; sus lineas se anaden al guardar
            foreach ($c in 'Art\main\LckTxtRc.irc', 'Art\_FHD\Main\LckTxtRc.irc') { if (Teat-Existe ($pre + $c)) { $l += ($pre + $c) } }
            $nuevo = [bool]$l.Count
        }
        if ($l.Count) { $r.lck += [ordered]@{ clave = $d.clave; nombre = $d.nombre; rels = $l; cambios = [bool](Lck-Fichero $d.clave -Cambios); nuevo = $nuevo } }
    }
    $b = Lck-Fichero 'COREA'
    $r.lckBase = [bool]($b -and (Test-Path -LiteralPath $b -PathType Leaf))
    return $r
}
function Ayu-Permitido([string]$rel) {
    if (-not $rel) { return $false }
    $a = Ayu-Lista
    foreach ($x in @($a.guia, $a.ayuda) + @($a.menu | ForEach-Object { $_.rel })) { if ($x -and $x -ieq $rel) { return $true } }
    return $false
}

# =====================================================================
# Editor de campanas
# =====================================================================
$Filas = New-Object System.Collections.ArrayList
# ---------- filas de Archivos.csv (del idioma de trabajo): .cam / .tac / .trn / .run / CampObjData.XML ----------
function Cargar-Filas-Camp {
    $script:Filas = New-Object System.Collections.ArrayList
    if (-not $script:InstCsv) { return }
    $texto = [IO.File]::ReadAllText($script:InstCsv, [Text.Encoding]::UTF8)
    foreach ($l in ($texto -split "`r?`n")) {
        $c = $l.TrimStart([char]0xFEFF).Split(';')
        if ($c.Count -lt 3) { continue }
        $fich = $c[1].Trim(); $dat = $c[2].Trim()
        # .cam/.tac/.trn/.run y el CampObjData.XML del teatro (nombres de objetivos, se editan juntos)
        if ($fich -notmatch '\.(cam|tac|trn|run)$' -and $dat -notmatch '(^|\\)CampObjData\.xml$') { continue }
        [void]$script:Filas.Add([ordered]@{ i = $script:Filas.Count; teatro = $c[0].Trim(); fich = $fich; data = $dat })
    }
    # teatros nuevos (Add-On que no son de los conocidos): los .cam/.tac/.trn y el CampObjData.xml del juego que aun
    # no estan en Archivos.csv (fich vacio: al guardar se copian a Ficheros\Campaign y se anade su linea)
    if (-not $script:Teatros) { return }
    $enCsv = @{}; foreach ($f in $script:Filas) { $enCsv[$f.data.ToLower()] = $true }
    foreach ($t in $script:Teatros) {
        if (-not $t.Carpeta -or @($TeatrosConocidos | Where-Object { $_.Clave -eq $t.Clave }).Count) { continue }
        $dir = Join-Path $Data ($t.Carpeta + '\Campaign')
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($x in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(cam|tac|trn)$' -or $_.Name -ieq 'CampObjData.xml' } | Sort-Object Name)) {
            $rel = $t.Carpeta + '\Campaign\' + $x.Name
            if ($enCsv[$rel.ToLower()]) { continue }
            [void]$script:Filas.Add([ordered]@{ i = $script:Filas.Count; teatro = $t.Clave; fich = ''; data = $rel })
        }
    }
}
Cargar-Filas-Camp
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
# Kit de voces (generar_voces.py, montar_tlk.py, voces_util.py, Mapas\, ref\) en la
# carpeta Voces junto a este script (o la que elijas). Python = el de la venv con coqui-tts.
$VozCfgFich = Join-Path $Aqui 'voces.json'
# motor de voz: chatterbox (MIT, por defecto; Python de Voces\venv_cb) o xtts (XTTS-v2, CPML; Python de Voces\venv)
$VozCfg = [ordered]@{ kit = ''; python = ''; pythonCb = ''; ffmpeg = ''; motor = 'chatterbox'; variante = 'v3' }
# ajustes de generacion (se guardan tambien en voces.json)
$VozAj = [ordered]@{ temperatura = 0.65; velocidad = 1.0; cbTemperatura = 0.8; expresividad = 0.5; cfg = 0.5; rms = 6000; radio = 1; pausaInicio = 25; pausaFin = 15; suavizado = 0; limpieza = 0; procesos = 2; igualTodo = 1 }
$VozAjRango = @{ temperatura = @(0.1, 1.0); velocidad = @(0.8, 1.3); cbTemperatura = @(0.05, 1.5); expresividad = @(0.25, 2.0); cfg = @(0.0, 1.0); rms = @(1000, 12000); radio = @(0, 2); pausaInicio = @(0, 500); pausaFin = @(0, 1000); suavizado = @(0, 1); limpieza = @(0, 1); procesos = @(1, 8); igualTodo = @(0, 1) }
if (Test-Path -LiteralPath $VozCfgFich) {
    try {
        $j = Get-Content -LiteralPath $VozCfgFich -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in 'kit', 'python', 'pythonCb', 'ffmpeg', 'motor', 'variante') { if ($j.$k) { $VozCfg[$k] = [string]$j.$k } }
        if ($VozCfg.motor -notin @('chatterbox', 'xtts')) { $VozCfg.motor = 'chatterbox' }
        if ($VozCfg.variante -notin @('v3', 'es-es')) { $VozCfg.variante = 'v3' }
        if ($j.ajustes) { foreach ($k in @($VozAj.Keys)) { if ($null -ne $j.ajustes.$k) { $VozAj[$k] = [double]$j.ajustes.$k } } }
    } catch { }
}
$Inv = [Globalization.CultureInfo]::InvariantCulture
function Voz-Num($v) { return ([double]$v).ToString($Inv) }
function Voz-Args-Ajustes {
    return @('--motor', $VozCfg.motor, '--variante', $VozCfg.variante,
             '--cb-temperatura', (Voz-Num $VozAj.cbTemperatura), '--expresividad', (Voz-Num $VozAj.expresividad), '--cfg', (Voz-Num $VozAj.cfg),
             '--temperatura', (Voz-Num $VozAj.temperatura), '--velocidad', (Voz-Num $VozAj.velocidad), '--rms', (Voz-Num $VozAj.rms),
             '--radio', ([string][int]$VozAj.radio), '--pausa-inicio', ([string][int]$VozAj.pausaInicio), '--pausa-fin', ([string][int]$VozAj.pausaFin),
             '--suavizado', (Voz-Num $VozAj.suavizado), '--limpieza', (Voz-Num $VozAj.limpieza), '--procesos', ([string][int]$VozAj.procesos),
             '--igual', $(if ([int]$VozAj.igualTodo) { 'todo' } else { 'numeros' }))
}
# ---------- voces por idioma de la traduccion ----------
# El kit es neutro: ref\ (voces clonadas del ingles), Mapa_<Teatro>.csv (clips: tlkId, fragmento, voz,
# ingles) y plantillas_lectura.json. Cada idioma trabaja en Voces\Idiomas\<CODIGO>\: wav\, cache\, prueba\,
# Falcon_<Teatro>.tlk. Los textos estan solo en su F4Talk.csv del instalador (Voz-Args-F4Talk).
# Lo que se lee (numeros, letras...) y el idioma de XTTS salen de su idioma.json; las pronunciaciones,
# de su pronunciaciones.txt. El audio de partida es siempre el ingles (referencias y Falcon.tlk original).
function Voz-Cod { if ($script:InstIdi) { return $script:InstIdi.codigo } else { return 'ES' } }
function Voz-Dir {
    $k = $VozCfg.kit; $c = Voz-Cod
    if (-not $k) { return [ordered]@{ cod = $c; base = $null; listas = $null; wav = $null; cache = $null; prueba = $null } }
    # lo generado de cada motor va aparte: wav\ y cache\ (XTTS), wav_cb\ y cache_cb\ (Chatterbox)
    $suf = $(if ($VozCfg.motor -eq 'xtts') { '' } else { '_cb' })
    $b = Join-Path $k ('Idiomas\' + $c); $w = Join-Path $b ('wav' + $suf); $ca = Join-Path $b ('cache' + $suf)
    return [ordered]@{ cod = $c; base = $b; listas = $b; wav = $w; cache = $ca; prueba = (Join-Path $b 'prueba') }
}
function Voz-Lectura {
    if ($script:InstIdi -and -not $script:InstIdi.legado) { $j = Join-Path $script:InstIdi.dir 'idioma.json'; if (Test-Path -LiteralPath $j) { return $j } }
    return ''
}
# pronunciaciones: las del idioma en el instalador (Idiomas\<CODIGO>\pronunciaciones.txt); si no hay, las de
# su carpeta de voces (lo que tenia el kit antiguo para el espanol)
function Voz-Dic {
    if ($script:InstIdi -and -not $script:InstIdi.legado) {
        $p = Join-Path $script:InstIdi.dir 'pronunciaciones.txt'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Join-Path (Voz-Dir).base 'pronunciaciones.txt')
}
# Kit antiguo (todo en espanol en la raiz del kit): lo generado pasa a Voces\Idiomas\ES
function Voz-Migrar-Kit {
    $k = $VozCfg.kit; if (-not $k) { return }
    $es = Join-Path $k 'Idiomas\ES'
    $mov = @()
    foreach ($par in @(@('wav_es', 'wav'), @('cache', 'cache'), @('prueba', 'prueba'))) {
        $o = Join-Path $k $par[0]; $d = Join-Path $es $par[1]
        if ((Test-Path -LiteralPath $o -PathType Container) -and -not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $es -Force | Out-Null
            try { Move-Item -LiteralPath $o -Destination $d; $mov += $par[0] } catch { Write-Host ("Voces: no se pudo mover " + $o + ": " + $_.Exception.Message) -ForegroundColor Red }
        }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $k -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Falcon_.+\.tlk|montado_.+\.json|pronunciaciones\.txt)$' })) {
        $d = Join-Path $es $f.Name
        New-Item -ItemType Directory -Path $es -Force | Out-Null
        if (Test-Path -LiteralPath $d) { continue }
        try { Move-Item -LiteralPath $f.FullName -Destination $d; $mov += $f.Name } catch { }
    }
    if ($mov.Count) { Write-Host ("Voces: lo que habia en español en el kit se ha movido a " + $es + ": " + ($mov -join ', ')) -ForegroundColor Yellow }
}
function Voz-IdiomaVoz { if ($script:InstIdi -and $script:InstIdi.voz) { return [string]$script:InstIdi.voz } else { return 'es' } }
function Voz-Codif { if ($script:InstIdi -and $script:InstIdi.codificacion) { return [string]$script:InstIdi.codificacion } else { return '1252' } }
function Voz-Args-Idioma {
    $d = Voz-Dir
    $a = @('--salida', $d.wav, '--cache', $d.cache, '--prueba-dir', $d.prueba, '--dic', (Voz-Dic), '--idioma-voz', (Voz-IdiomaVoz))
    $l = Voz-Lectura; if ($l) { $a += @('--lectura', $l) }
    $a += @('--codificacion', (Voz-Codif)) + @(Voz-Args-F4Talk)
    return $a
}
# F4Talk.csv (subtitulos) de un teatro en el instalador del idioma de trabajo
# nombre del fichero de subtitulos de un teatro en Ficheros\F4Talk: el de la clave, salvo Corea, que es KOREA
# (como Strings_KOREA.txt); F4Talk_COREA.csv no debe existir
function Voz-F4Talk-Nombre([string]$clave) { if ($clave -ieq 'COREA') { return 'F4Talk_KOREA.csv' }; return 'F4Talk_' + $clave.ToUpper() + '.csv' }
# arreglo de versiones anteriores, que creaban F4Talk_COREA.csv (copia del ingles) cuando no encontraban el de Corea:
# la linea de Archivos.csv pasa a F4Talk_KOREA.csv y F4Talk_COREA.csv se quita (se guarda en Respaldo\F4Talk)
function Voz-F4Talk-Quitar-Corea {
    if (-not $InstFicheros -or -not $InstCsv) { return }
    $mal = Join-Path $InstFicheros 'F4Talk\F4Talk_COREA.csv'
    if (-not (Test-Path -LiteralPath $mal)) { return }
    $bien = Join-Path $InstFicheros 'F4Talk\F4Talk_KOREA.csv'
    if (-not (Test-Path -LiteralPath $bien)) { Move-Item -LiteralPath $mal -Destination $bien }
    else {
        $res = Join-Path $Respaldo 'F4Talk'; [void](New-Item -ItemType Directory -Force -Path $res)
        Move-Item -LiteralPath $mal -Destination (Join-Path $res ('F4Talk_COREA_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.csv')) -Force
    }
    foreach ($f in (Leer-Csv)) {
        if ($f.fich -ieq 'F4Talk\F4Talk_COREA.csv') { Cambiar-Csv-Fich $f.data 'F4Talk\F4Talk_KOREA.csv' }
    }
    if (-not (@(Leer-Csv) | Where-Object { $_.fich -ieq 'F4Talk\F4Talk_KOREA.csv' })) { [void](Anadir-Csv 'Sounds\F4Talk.csv' 'F4Talk\F4Talk_KOREA.csv') }
    Write-Host 'Voces: quitado F4Talk_COREA.csv (copia del ingles de una version anterior); Corea usa F4Talk_KOREA.csv' -ForegroundColor Yellow
}
function Voz-F4Talk([string]$nombre) {
    $clave = Voz-Clave $nombre
    if ($clave -ieq 'COREA') { Voz-F4Talk-Quitar-Corea }
    foreach ($f in (Leer-Csv)) {
        if ([IO.Path]::GetFileName($f.data) -ieq 'F4Talk.csv' -and $f.clave -ieq $clave) {
            $ruta = RutaSegura $InstFicheros $f.fich
            if ($ruta -and (Test-Path -LiteralPath $ruta)) {
                # si la linea apunta a una copia del ingles (la que se crea cuando no habia subtitulos) y en
                # Ficheros\F4Talk hay otro del teatro que no es el ingles, ese es la traduccion: se pasa a usar ese
                $otro = Voz-F4Talk-Suelto $nombre
                if ($otro -and $otro -ine $ruta) {
                    $t = Voz-Teatro $nombre; $en = if ($t) { Voz-F4Talk-En $t } else { $null }
                    if ($en -and (Voz-Mismo-Fichero $ruta $en) -and -not (Voz-Mismo-Fichero $otro $en)) {
                        $nf = 'F4Talk\' + (Split-Path $otro -Leaf)
                        Cambiar-Csv-Fich $f.data $nf
                        Write-Host ("Voces: los subtitulos de " + $nombre + " eran una copia del ingles (" + $f.fich + "); se usa la traduccion " + $nf) -ForegroundColor Yellow
                        return $otro
                    }
                }
                return $ruta
            }
        }
    }
    # puesto a mano en Ficheros\F4Talk sin su linea en Archivos.csv: se adopta (y se apunta, para que el instalador
    # tambien lo copie). Nombres validos: F4Talk_<CLAVE>.csv, F4Talk_<Teatro>.csv o F4Talk_<carpeta del Add-On>.csv
    $p = Voz-F4Talk-Suelto $nombre
    if ($p) {
        $t = Voz-Teatro $nombre
        if ($t) {
            $fich = 'F4Talk\' + (Split-Path $p -Leaf)
            $r = Anadir-Csv ((Split-Path $t.rel -Parent) + '\F4Talk.csv') $fich
            Write-Host ("Voces: subtitulos de " + $nombre + " encontrados en Ficheros\" + $fich + " (Archivos.csv: " + $r + ")")
        }
        return $p
    }
    return $null
}
function Voz-Mismo-Fichero([string]$a, [string]$b) {
    $fa = Get-Item -LiteralPath $a; $fb = Get-Item -LiteralPath $b
    if ($fa.Length -ne $fb.Length) { return $false }
    return ((Get-FileHash -LiteralPath $a -Algorithm MD5).Hash -eq (Get-FileHash -LiteralPath $b -Algorithm MD5).Hash)
}
function Voz-F4Talk-Suelto([string]$nombre) {
    if (-not $InstFicheros) { return $null }
    $dir = Join-Path $InstFicheros 'F4Talk'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $t = @($Teatros | Where-Object { $_.Corto -eq $nombre }) | Select-Object -First 1
    if (-not $t) { return $null }
    $nombres = @($t.Clave, $t.Corto, $t.Nombre, ($t.Carpeta -replace '^Add-On ', ''), ($t.Detalle -replace '^Add-On ', '')) | Where-Object { $_ }
    if ($t.Clave -eq 'COREA') { $nombres += @('KOREA', 'Korea') }
    $norm = { param($x) ($x -replace '[\s_-]', '').ToUpperInvariant() }
    $quiero = @($nombres | ForEach-Object { & $norm $_ })
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter 'F4Talk_*.csv' -File -ErrorAction SilentlyContinue) {
        if ((& $norm ($f.BaseName.Substring(7))) -in $quiero) { return $f.FullName }
    }
    return $null
}
# Mapas de clips del kit (Mapas\Mapa_<Teatro>.csv: tlkId, fragmento, voz, ingles). Se rehacen desde los ficheros
# del juego: FragFile.xml (que voz dice cada fragmento y en que clip), F4Talk.csv en ingles y la cabecera del
# Falcon.tlk; solo si faltan o si esos ficheros han cambiado (su huella se guarda en Mapa_<Teatro>.origen.txt)
function Voz-Fuentes-Mapa($t) {
    $tlkJuego = Join-Path $Data $t.rel
    $o = Ruta-Original $t.rel
    $tlk = $null
    if ($o -and (Test-Path -LiteralPath $o -PathType Leaf)) { $tlk = $o } elseif (Test-Path -LiteralPath $tlkJuego -PathType Leaf) { $tlk = $tlkJuego }
    # FragFile.xml: junto al Falcon.tlk, en la carpeta de encima o, si no, dentro del teatro
    $ff = $null; $dir = Split-Path $tlkJuego -Parent
    foreach ($c in @($dir, (Split-Path $dir -Parent))) {
        if (-not $c -or -not (Test-Path -LiteralPath $c)) { continue }
        $x = Get-ChildItem -LiteralPath $c -Filter 'FragFile.xml' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($x) { $ff = $x.FullName; break }
    }
    if (-not $ff) {
        $base = $(if ($t.rel -match '^(Add-On [^\\]+)\\') { Join-Path $Data $Matches[1] } else { Join-Path $Data 'Sounds' })
        if (Test-Path -LiteralPath $base) {
            $x = Get-ChildItem -LiteralPath $base -Recurse -Depth 4 -Filter 'FragFile.xml' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($x) { $ff = $x.FullName }
        }
    }
    # F4Talk.csv en ingles: el original (Data_ORIGINAL) del de Archivos.csv, o el del juego si no es una traduccion
    $f4 = $null
    $clave = Voz-Clave $t.nombre
    foreach ($f in (Leer-Csv)) { if ([IO.Path]::GetFileName($f.data) -ieq 'F4Talk.csv' -and $f.clave -ieq $clave) { $f4 = Teat-Ruta $f.data 'en'; if ($f4) { break } } }
    if (-not $f4) { $f4 = Teat-Ruta ((Split-Path $t.rel -Parent) + '\F4Talk.csv') 'en' }
    return @{ tlk = $tlk; fragfile = $ff; f4talk = $f4 }
}
function Voz-Mapa([string]$nombre) {
    foreach ($p in @((Join-Path $VozCfg.kit ('Mapas\Mapa_' + $nombre + '.csv')), (Join-Path $VozCfg.kit ('Mapa_' + $nombre + '.csv')))) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}
function Voz-Preparar-Mapas {
    if (-not $VozCfg.kit -or -not (Voz-Py-Util)) { return }
    $d = Join-Path $VozCfg.kit 'Mapas'
    if (-not $script:VozFuentes) { $script:VozFuentes = @{} }
    foreach ($t in $VozTeatros) {
        # donde estan los ficheros se busca una vez por sesion; la huella (tamano y fecha) se mira siempre
        if (-not $script:VozFuentes.ContainsKey($t.nombre)) { $script:VozFuentes[$t.nombre] = Voz-Fuentes-Mapa $t }
        $s = $script:VozFuentes[$t.nombre]
        if (-not $s.tlk -or -not $s.fragfile -or -not $s.f4talk) {
            if (-not $script:VozAvisoMapa) { Write-Host ("Voces: no se puede rehacer el mapa de " + $t.nombre + " (falta " + (@(foreach ($k in 'fragfile', 'f4talk', 'tlk') { if (-not $s[$k]) { $k } }) -join ', ') + "); se usa el del kit") -ForegroundColor Yellow }
            continue
        }
        $huella = (@($s.fragfile, $s.f4talk, $s.tlk) | ForEach-Object { $i = Get-Item -LiteralPath $_; '{0}-{1}' -f $i.Length, $i.LastWriteTimeUtc.Ticks }) -join '_'
        $m = Join-Path $d ('Mapa_' + $t.nombre + '.csv'); $o = Join-Path $d ('Mapa_' + $t.nombre + '.origen.txt')
        if ((Test-Path -LiteralPath $m) -and (Test-Path -LiteralPath $o) -and ([IO.File]::ReadAllText($o).Trim() -eq $huella)) { continue }
        if (-not $script:VozMapaFallo) { $script:VozMapaFallo = @{} }
        if ((Test-Path -LiteralPath $m) -and $script:VozMapaFallo[$t.nombre] -eq $huella) { continue }   # ya fallo con estos ficheros
        $r = Voz-Python @((Join-Path $VozCfg.kit 'voces_util.py'), 'mapa', '--teatro', $t.nombre, '--fragfile', $s.fragfile, '--f4talk', $s.f4talk, '--tlk', $s.tlk, '--origen', $huella)
        if ($r.codigo -ne 0) { $script:VozMapaFallo[$t.nombre] = $huella; Write-Host ("Voces: no se pudo rehacer el mapa de " + $t.nombre + ": " + $r.texto) -ForegroundColor Red }
        else { Write-Host ("Voces: mapa de " + $t.nombre + " rehecho desde " + $s.fragfile) }
    }
    $script:VozAvisoMapa = $true
}
# F4Talk.csv en ingles de un teatro (para los teatros que aun no tienen el suyo en el instalador)
function Voz-F4Talk-En($t) { return (Teat-Ruta ((Split-Path $t.rel -Parent) + '\F4Talk.csv') 'en') }
# F4Talk.csv del teatro en el instalador; si no lo tiene (p. ej. un Add-On nuevo), se crea desde el ingles:
# original a Data_ORIGINAL, copia a Ficheros\F4Talk\F4Talk_<CLAVE>.csv y su linea en Archivos.csv
function Voz-F4Talk-Asegurar([string]$nombre) {
    $p = Voz-F4Talk $nombre; if ($p) { return $p }
    if (-not $InstCsv) { return $null }
    $t = Voz-Teatro $nombre; $k = Voz-Clave $nombre
    if (-not $t -or -not $k) { return $null }
    $rel = (Split-Path $t.rel -Parent) + '\F4Talk.csv'
    $en = Voz-F4Talk-En $t; if (-not $en) { return $null }
    $o = Ruta-Original $rel; if ($o -and -not (Test-Path -LiteralPath $o -PathType Leaf)) { Copiar-A $en $o; Write-Host ("Original:  " + $o) }
    $fich = 'F4Talk\' + (Voz-F4Talk-Nombre $k)
    $dst = RutaSegura $InstFicheros $fich; if (-not $dst) { return $null }
    if (Test-Path -LiteralPath $dst) { Write-Host ("Voces: " + $fich + " ya existe; se usa tal cual (no se sustituye por el ingles)") }
    else { Copiar-A $en $dst }
    $r = Anadir-Csv $rel $fich
    Write-Host ("Archivos.csv: " + $r + "  ($fich, subtitulos de " + $nombre + ")")
    return $dst
}
# Textos de las voces: salen SIEMPRE del F4Talk.csv traducido de cada teatro en el instalador (no hay otra copia):
# los scripts del kit cruzan al momento ese F4Talk con el mapa de clips (Voces\Mapas\Mapa_<Teatro>.csv).
# Un teatro sin F4Talk traducido sale con los textos en ingles.
# Se pasan en un .json {teatro: ruta} (Voces\Idiomas\<COD>\f4talk.json): sin rutas con espacios ni "=" en la linea de
# ordenes, que PowerShell 5.1 puede partir
function Voz-F4Talk-Json([string[]]$nombres) {
    if (-not $nombres -or -not $nombres.Count) { $nombres = @($VozTeatros | ForEach-Object { $_.nombre }) }
    $o = [ordered]@{}
    foreach ($n in $nombres) { $f = @(Voz-F4Talk $n) | Where-Object { $_ } | Select-Object -Last 1; if ($f) { $o[$n] = [string]$f } }
    $d = (Voz-Dir).base; [void](New-Item -ItemType Directory -Force -Path $d)
    $txt = ConvertTo-Json -InputObject $o
    $j = Join-Path $d ('f4talk_' + (($nombres | Sort-Object) -join '_') + '.json')
    if (-not (Test-Path -LiteralPath $j) -or [IO.File]::ReadAllText($j) -ne $txt) { [IO.File]::WriteAllText($j, $txt, (New-Object Text.UTF8Encoding($false))) }
    return $j
}
function Voz-Args-F4Talk {
    $a = @('--f4talk', (Voz-F4Talk-Json @($VozTeatros | ForEach-Object { $_.nombre })))
    if ($InstFicheros) { $a += @('--ficheros', [string]$InstFicheros) }     # y, si falta alguno, que lo busque ahi
    return $a
}
# las Lista_<Teatro>.csv de versiones anteriores ya no se usan: se borran (y su .origen.txt)
function Voz-Quitar-Listas-Viejas {
    if ($script:VozListasQuitadas -or -not $VozCfg.kit) { return }
    $d = (Voz-Dir).base; if (-not $d -or -not (Test-Path -LiteralPath $d)) { return }
    $v = @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Lista_.+\.csv(\.origen\.txt)?$' })
    foreach ($f in $v) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    if ($v.Count) { Write-Host ("Voces: quitadas las Lista_*.csv antiguas de " + $d + " (los textos salen ahora directamente de los F4Talk)") -ForegroundColor Yellow }
    $script:VozListasQuitadas = $true
}
# tabla de clips de un teatro (tlkId;frag;voz;estado;ingles;traduccion), hecha por voces_util con el mapa y el F4Talk;
# se guarda en memoria mientras el F4Talk y el mapa no cambien
function Voz-Tabla($t) {
    $f4 = Voz-F4Talk $t.nombre; $mp = Voz-Mapa $t.nombre
    if (-not $mp) { return $null }
    $hu = (@($f4, $mp) | Where-Object { $_ } | ForEach-Object { $i = Get-Item -LiteralPath $_; $i.FullName + '|' + $i.Length + '|' + $i.LastWriteTimeUtc.Ticks }) -join "`n"
    if (-not $script:VozTablas) { $script:VozTablas = @{} }
    $c = $script:VozTablas[$t.nombre]
    if ($c -and $c.huella -eq $hu) { return $c.bytes }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('bmsvoz_' + [Guid]::NewGuid().ToString('N') + '.csv')
    $jf = Voz-F4Talk-Json @($t.nombre)
    $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'lista', '--teatro', $t.nombre, '--salida', $tmp, '--codificacion', (Voz-Codif), '--f4talk', $jf)
    if ($InstFicheros) { $a += @('--ficheros', [string]$InstFicheros) }
    $r = Voz-Python $a
    $lj = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
    $avisos = ($r.texto -split "`n" | Where-Object { $_.Trim() -and -not $_.StartsWith('{') }) -join ' | '
    try { $lo = $lj | ConvertFrom-Json; if (-not $lo.f4talk) { Write-Host ("Voces: (diagnostico) " + $jf + " = " + [IO.File]::ReadAllText($jf) + " ; Ficheros = " + $InstFicheros + " ; Voz-F4Talk = " + (@(Voz-F4Talk $t.nombre) -join ' | ')) -ForegroundColor Red }; Write-Host ("Voces: textos de " + $t.nombre + " leidos de " + $(if ($lo.f4talk) { $lo.f4talk } else { 'NINGUN F4Talk (salen en ingles)' }) + " -> traducidos: " + $lo.estados.TRADUCIR + $(if ($avisos) { '  [' + $avisos + ']' } else { '' })) -ForegroundColor $(if ($lo.f4talk) { 'Gray' } else { 'Red' }) } catch { }
    if ($r.codigo -ne 0 -or -not (Test-Path -LiteralPath $tmp)) {
        Write-Host ("Voces: no se pudo leer los textos de " + $t.nombre + ": " + $r.texto) -ForegroundColor Red
        $script:VozErrTabla = (($r.texto -split "`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1)
        return $null
    }
    $script:VozErrTabla = $null
    $b = [IO.File]::ReadAllBytes($tmp); Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $script:VozTablas[$t.nombre] = @{ huella = $hu; bytes = $b }
    return $b
}
# frase de prueba de las voces del idioma (lectura.frasePrueba)
function Voz-Frase-Prueba {
    $l = Voz-Lectura
    if ($l) { try { $j = [IO.File]::ReadAllText($l, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json; if ($j.lectura.frasePrueba) { return [string]$j.lectura.frasePrueba } } catch { } }
    return 'Esto es una prueba de audio para la voz número'
}
# Python del motor elegido (el de Chatterbox o el de XTTS); para lo que no usa el modelo vale cualquiera de los dos
function Voz-Py { if ($VozCfg.motor -eq 'xtts') { return $VozCfg.python } else { return $VozCfg.pythonCb } }
function Voz-Py-Util { $p = Voz-Py; if ($p -and (Test-Path -LiteralPath $p)) { return $p }; foreach ($x in @($VozCfg.pythonCb, $VozCfg.python)) { if ($x -and (Test-Path -LiteralPath $x)) { return $x } }; return '' }
function Voz-Guardar-Cfg {
    $o = [ordered]@{ kit = $VozCfg.kit; python = $VozCfg.python; pythonCb = $VozCfg.pythonCb; ffmpeg = $VozCfg.ffmpeg; motor = $VozCfg.motor; variante = $VozCfg.variante; ajustes = $VozAj }
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
        $c = Join-Path $VozCfg.kit 'venv_cb\Scripts\python.exe'; if (Test-Path -LiteralPath $c) { $VozCfg.pythonCb = $c }
        $c = Join-Path $VozCfg.kit 'ffmpeg\bin\ffmpeg.exe'; if (Test-Path -LiteralPath $c) { $VozCfg.ffmpeg = $c }
        if (-not $script:VozMigrado) { $script:VozMigrado = $true; Voz-Migrar-Kit }
        if (Get-Command Voz-Poner-TtsHome -ErrorAction SilentlyContinue) { Voz-Poner-TtsHome }
    }
    if (-not $VozCfg.python -or -not (Test-Path -LiteralPath $VozCfg.python)) {
        $VozCfg.python = ''
        $cands = @()
        if ($VozCfg.kit) { $cands += @((Join-Path $VozCfg.kit 'venv\Scripts\python.exe'), (Join-Path $VozCfg.kit '.venv\Scripts\python.exe'), (Join-Path (Split-Path $VozCfg.kit -Parent) 'venv\Scripts\python.exe')) }
        $cands += @((Join-Path $env:USERPROFILE 'xtts\venv\Scripts\python.exe'), (Join-Path $env:USERPROFILE 'xtts\.venv\Scripts\python.exe'))
        foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $VozCfg.python = $c; break } }
        if (-not $VozCfg.python) { $g = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if ($g) { $VozCfg.python = $g.Source } }
    }
    if ($VozCfg.pythonCb -and -not (Test-Path -LiteralPath $VozCfg.pythonCb)) { $VozCfg.pythonCb = '' }
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
# teatros con voces: Corea (Data\Sounds) y cada Add-On que tenga su propio Falcon.tlk; se nombran por su nombre corto
$VozNombres = @{}; foreach ($t in $Teatros) { if ($t.Carpeta) { $VozNombres[$t.Carpeta] = $t.Corto } }
function Voz-Clave([string]$nombre) { $t = @($Teatros | Where-Object { $_.Corto -eq $nombre }) | Select-Object -First 1; if ($t) { return $t.Clave }; return $null }
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

# el juego tiene instalada alguna traduccion (de cualquier idioma) de ese fichero
function Voz-Espanol-Instalado([string]$rel) {
    foreach ($fr in @(Get-ChildItem -LiteralPath $Bms -Filter 'Traduccion_*_instalado.txt' -File -ErrorAction SilentlyContinue)) {
        foreach ($l in [IO.File]::ReadAllLines($fr.FullName, [Text.Encoding]::UTF8)) {
            $i = $l.LastIndexOf('|'); if ($i -gt 0 -and $l.Substring(0, $i) -ieq $rel) { return $true }
        }
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
    $sal = & (Voz-Py-Util) @argumentos 2>&1
    return @{ codigo = $LASTEXITCODE; texto = (($sal | ForEach-Object { "$_" }) -join "`n") }
}

# el Python del motor tiene lo que necesita (torch + chatterbox o TTS + scipy)
function Voz-Xtts-Ok {
    $py = Voz-Py
    if (-not $py -or -not (Test-Path -LiteralPath $py)) { return $false }
    $ErrorActionPreference = 'Continue'
    $mods = $(if ($VozCfg.motor -eq 'xtts') { "'torch','TTS','scipy'" } else { "'torch','chatterbox','scipy'" })
    $r = & $py -c "import importlib.util as u; print(all(u.find_spec(m) for m in ($mods)))" 2>$null
    return (($r | Select-Object -Last 1) -eq 'True')
}
function Voz-Ffmpeg-Ok {
    $ErrorActionPreference = 'Continue'
    try { $e = & $VozCfg.ffmpeg -hide_banner -encoders 2>&1; return [bool]((($e | ForEach-Object { "$_" }) -join "`n") -match 'libspeex') } catch { return $false }
}

$VozTrabajos = New-Object System.Collections.ArrayList
function Voz-Lanzar([string]$tipo, [string]$teatro, [string]$titulo, [string[]]$argumentos, [string]$exe) {
    if (-not $exe) { $exe = Voz-Py }
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
    $py = Voz-Py
    $lineas = @(foreach ($p in $pasos) { '"' + $py + '" ' + (Voz-Cita $p) })
    $cmd = '/c title ' + $titulo + ' & (' + ($lineas -join ' && ') + ') & echo. & call echo Codigo de salida: %^errorlevel% & pause'
    $pr = Start-Process -FilePath $env:ComSpec -ArgumentList $cmd -WorkingDirectory $VozCfg.kit -PassThru
    $w = [ordered]@{ id = [Guid]::NewGuid().ToString('N').Substring(0, 8); tipo = $tipo; teatro = ($teatros -join ','); teatros = $teatros; titulo = $titulo; inicio = (Get-Date); proc = $pr }
    [void]$VozTrabajos.Add($w)
    Write-Host ("Voces: " + $titulo)
    return $w.id
}
# argumentos de montar_tlk.py para un teatro (con el Falcon.tlk del instalador como base)
# carpeta de audios generados de un motor (wav_cb\ Chatterbox, wav\ XTTS) en el idioma de trabajo
function Voz-Wav-De([string]$motor) { $b = (Voz-Dir).base; if ($motor -eq 'xtts') { return (Join-Path $b 'wav') } else { return (Join-Path $b 'wav_cb') } }
# $motor: de que motor se cogen los audios (por defecto el elegido); $solo: sin el Falcon.tlk del instalador como base,
# asi lo que ese motor no tenga se queda en el ingles original (no se mezclan voces de los dos motores)
function Voz-Args-Montar($t, [string]$motor = '', [bool]$solo = $false) {
    if (-not $motor) { $motor = $VozCfg.motor }
    $ing = Voz-Tlk-Ingles $t
    if (-not $ing.seguro) { throw "No hay copia del Falcon.tlk de $($t.nombre) en inglés en Data_ORIGINAL y el del juego es el de la traducción. Restaura el inglés con el instalador y vuelve a intentarlo." }
    $o = Ruta-Original $t.rel
    if ($o -and -not (Test-Path -LiteralPath $o)) { Copiar-A $ing.ruta $o; Write-Host ("Original:  " + $o); $ing.ruta = $o }
    $d = Voz-Dir
    $a = @((Join-Path $VozCfg.kit 'montar_tlk.py'), '--teatro', $t.nombre, '--tlk', $ing.ruta, '--ffmpeg', $VozCfg.ffmpeg,
           '--pausa-inicio', ([string][int]$VozAj.pausaInicio), '--pausa-fin', ([string][int]$VozAj.pausaFin),
           '--codificacion', (Voz-Codif), '--wav', (Join-Path (Voz-Wav-De $motor) $t.nombre), '--salida', (Join-Path $d.base ('Falcon_' + $t.nombre + '.tlk')),
           '--manifiesto', (Join-Path $d.base ('montado_' + $t.nombre + '.json')))
    $a += @('--f4talk', (Voz-F4Talk-Json @($t.nombre)))
    if ($InstFicheros) { $a += @('--ficheros', [string]$InstFicheros) }
    $ed = Ruta-Editado $t.rel
    if (-not $solo -and $ed -and (Test-Path -LiteralPath $ed -PathType Leaf)) { $a += @('--base', $ed) }
    return ,$a
}
# ---------- modelo XTTS, restaurar y limpiar el kit ----------
# El modelo va en Voces\modelos (TTS_HOME); si ya estaba de antes en %LOCALAPPDATA%\tts, se sigue usando alli.
$VozModeloViejo = Join-Path $env:LOCALAPPDATA 'tts\tts_models--multilingual--multi-dataset--xtts_v2'
function Voz-Poner-TtsHome {
    if (-not $VozCfg.kit) { return }
    $m = Join-Path $VozCfg.kit 'modelos'
    if ((Test-Path -LiteralPath $VozModeloViejo) -and -not (Test-Path -LiteralPath (Join-Path $m 'tts'))) { Remove-Item Env:TTS_HOME -ErrorAction SilentlyContinue }
    else { $env:TTS_HOME = $m }
    $env:HF_HOME = Join-Path $m 'hf'      # Chatterbox (Hugging Face)
}
function Voz-Tamano([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    $i = Get-Item -LiteralPath $p -Force
    if (-not $i.PSIsContainer) { return [int64]$i.Length }
    $t = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    return [int64]$(if ($t) { $t } else { 0 })
}
# lo minimo del kit (lo que trae recien descomprimido)
Voz-Poner-TtsHome
$VozKitBase = @('LEEME.txt', 'Preparar_voces.ps1', 'generar_voces.py', 'motores.py', 'montar_tlk.py', 'voces_util.py', 'actualizar_motor.py', 'voz_servidor.py', 'lectura.py', 'plantillas_lectura.json', 'ref', 'Mapas')
# Lo que «Limpiar voces» puede borrar: [id, titulo, rutas, marcado, nota]
function Voz-Limpiar-Plan {
    $k = $VozCfg.kit; $out = New-Object System.Collections.ArrayList
    if (-not $k -or -not (Test-Path -LiteralPath $k)) { return @() }
    function Poner($grupo, $id, $titulo, $rutas, [bool]$marcado, [string]$nota) {
        $rutas = @($rutas | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
        if (-not $rutas.Count) { return }
        $t = [int64]0; foreach ($r in $rutas) { $t += (Voz-Tamano $r) }
        [void]$out.Add([ordered]@{ grupo = $grupo; id = $id; titulo = $titulo; rutas = @($rutas); bytes = $t; marcado = $marcado; nota = $nota })
    }
    # Marcado de serie solo lo que se rehace solo o no hace falta (preparaciones, pruebas, montajes, restos).
    # Lo que cuesta horas o descargas (audios generados, caches, entornos, modelos) y lo que es trabajo tuyo
    # (referencias, ajustes de voz) va desmarcado: se marca a mano o con los botones rapidos del dialogo.
    $idi = @(Get-ChildItem -LiteralPath (Join-Path $k 'Idiomas') -Directory -Force -ErrorAction SilentlyContinue)
    $gen = { param($nombres) @(foreach ($d in $idi) { foreach ($n in $nombres) { Join-Path $d.FullName $n } }) }
    $deIdi = { param($patron) @(foreach ($d in $idi) { Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $patron } | ForEach-Object { $_.FullName } }) }
    $rd = Join-Path $k 'ref'
    $enRef = { param($patron) @(Get-ChildItem -LiteralPath $rd -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $patron } | ForEach-Object { $_.FullName }) }
    $nInst = 'Lo ya guardado en el instalador no se toca.'
    $nGen = 'Son las voces ya generadas (horas de trabajo). Lo montado y guardado en el instalador no se pierde.'
    $nCache = 'Salida del modelo antes del efecto de radio. Los audios generados siguen valiendo sin ella, pero «Aplicar efectos de radio» ya no podrá rehacerlos (habría que volver a generar).'
    $nEnt = 'Para volver a usar este motor hay que reinstalarlo con «Preparar entorno» (descarga de varios GB).'

    foreach ($m in @(@{ g = 'Chatterbox'; p = 'cb'; venv = 'venv_cb'; mod = @(Join-Path $k 'modelos\hf'); wav = 'wav_cb'; cache = 'cache_cb'; pt = '\.chatterbox\.pt(\.lock|\.\d+\.tmp)?$'; nombre = 'Chatterbox' },
                     @{ g = 'XTTS'; p = 'x'; venv = 'venv'; mod = @((Join-Path $k 'modelos\tts'), $VozModeloViejo); wav = 'wav'; cache = 'cache'; pt = '\.latentes\.pt(\.lock|\.\d+\.tmp)?$'; nombre = 'XTTS' })) {
        Poner $m.g ($m.p + 'Prep') ('Voces preparadas para ' + $m.nombre + ' (ref\: se rehacen solas en un momento)') (& $enRef $m.pt) $true ''
        Poner $m.g ($m.p + 'Cache') ('Caché del modelo de ' + $m.nombre + ' (' + $m.cache + '\)') (& $gen @($m.cache)) $false $nCache
        Poner $m.g ($m.p + 'Gen') ('Audios generados con ' + $m.nombre + ' (' + $m.wav + '\)') (& $gen @($m.wav)) $false $nGen
        Poner $m.g ($m.p + 'Modelo') ('Modelo de ' + $m.nombre) $m.mod $false $nEnt
        Poner $m.g ($m.p + 'Venv') ('Entorno de ' + $m.nombre + ' (Voces\' + $m.venv + ': Python, PyTorch...)') @(Join-Path $k $m.venv) $false $nEnt
    }

    Poner 'Común' 'pruebas' 'Audios de «Prueba (30)» y «Comparar ajustes» (prueba\)' (& $gen @('prueba')) $true ''
    Poner 'Común' 'montados' 'Falcon_<Teatro>.tlk montados (copias de trabajo)' (& $deIdi '^(Falcon_.+\.tlk|montado_.+\.json)$') $true ($nInst + ' El próximo montaje tardará algo más.')
    $restos = @(& $deIdi '^(Lista_.+\.csv(\.origen\.txt)?|f4talk_.*\.json|.*\.tmp)$')
    $restos += @(& $enRef '\.(lock|tmp)$')
    $md = Join-Path $k 'Mapas'
    if (Test-Path -LiteralPath $md) { $restos += @(Get-ChildItem -LiteralPath $md -Force -File | Where-Object { $_.Name -notmatch '^Mapa_.+\.(csv|origen\.txt)$' } | ForEach-Object { $_.FullName }) }
    $restos += @(Get-ChildItem -LiteralPath $k -Recurse -Directory -Force -Filter '__pycache__' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike (Join-Path $k 'venv') + '*' } | ForEach-Object { $_.FullName })
    Poner 'Común' 'restos' 'Restos temporales y de versiones anteriores (listas antiguas, cerrojos, cachés de Python…)' $restos $true ''
    Poner 'Común' 'ffmpeg' 'ffmpeg (Voces\ffmpeg)' @(Join-Path $k 'ffmpeg') $false 'Lo usan los dos motores para montar y escuchar.'
    # referencias cambiadas: se vuelve a la de serie; y cualquier otro fichero de ref\ (sin las preparaciones de cada motor)
    Poner 'Común' 'ref' 'Referencias de voz cambiadas o limpiadas (vuelven las de serie)' (& $enRef '^(voz\d\d_inicial\.wav|voz\d\d_sinlimpiar\.wav|voz\d\d\.json)$') $false 'Es trabajo tuyo (Ajuste de voces → Referencia…).'
    Poner 'Común' 'ajustes' 'Ajustes propios de cada voz (ajustes_voces.json)' @(Join-Path $k 'ajustes_voces.json') $false 'Es trabajo tuyo (Ajuste de voces): las 14 voces vuelven a los ajustes generales.'
    # lo que no es del kit ni de lo anterior
    $conocidos = @('wav', 'cache', 'wav_cb', 'cache_cb', 'prueba', 'pronunciaciones.txt')
    $sueltos = @(foreach ($d in $idi) { Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $conocidos -and $_.Name -notmatch '^(Falcon_.+\.tlk|montado_.+\.json|Lista_.+\.csv(\.origen\.txt)?|f4talk_.*\.json|pretraducido_.+\.json|.*\.tmp)$' } | ForEach-Object { $_.FullName } })
    $sueltos += @(Get-ChildItem -LiteralPath (Join-Path $k 'modelos') -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('hf', 'tts') } | ForEach-Object { $_.FullName })
    $sueltos += @(& $enRef '^(?!voz\d\d\.wav$)(?!voz\d\d_inicial\.wav$)(?!voz\d\d_sinlimpiar\.wav$)(?!voz\d\d\.json$)(?!.*\.(chatterbox|latentes)\.pt)(?!.*\.(lock|tmp)$).*$')
    foreach ($f in Get-ChildItem -LiteralPath $k -Force -ErrorAction SilentlyContinue) {
        if ($VozKitBase -contains $f.Name -or $f.Name -in @('venv', 'venv_cb', 'ffmpeg', 'modelos', 'Idiomas', 'ajustes_voces.json', '__pycache__')) { continue }
        $sueltos += $f.FullName
    }
    Poner 'Común' 'otros' 'Otros ficheros y carpetas que no son del kit' $sueltos $false 'Revisa la lista antes de marcarlo.'
    Poner 'Común' 'pip' 'Caché de pip del usuario (descargas de PyTorch de versiones anteriores del kit)' @(Join-Path $env:LOCALAPPDATA 'pip\cache') $false 'La comparten todos los Python del usuario: se puede borrar sin problema, pero no es solo de las voces.'
    return @($out)
}
function Voz-Borrar([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    if ((Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p -Force).PSIsContainer) { cmd /c rd /s /q "$p" | Out-Null }
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}
function Voz-Limpiar([string[]]$ids) {
    foreach ($w in $VozTrabajos) { if (-not $w.proc.HasExited) { throw "Hay un proceso en marcha ($($w.titulo)). Espera a que termine o ciérralo." } }
    if (Voz-Srv-Vivo) { try { $VozSrv.proc.Kill(); $VozSrv.proc.WaitForExit(5000) } catch { } }
    $plan = Voz-Limpiar-Plan; $fallos = @(); $libres = [int64]0
    foreach ($it in $plan) {
        if ($ids -notcontains $it.id) { continue }
        if ($it.id -eq 'ref') {
            # vozNN_sinlimpiar.wav = la referencia antes de limpiarla; vozNN_inicial.wav = la de serie (manda sobre la otra):
            # vuelven a ser vozNN.wav
            foreach ($patron in @('^(voz\d\d)_sinlimpiar\.wav$', '^(voz\d\d)_inicial\.wav$')) {
                foreach ($r in $it.rutas) {
                    if ((Split-Path $r -Leaf) -match $patron) { Copy-Item -LiteralPath $r -Destination (Join-Path (Split-Path $r -Parent) ($Matches[1] + '.wav')) -Force }
                }
            }
        }
        foreach ($r in $it.rutas) { $x = Voz-Borrar $r; if ($x) { $fallos += $x } }
        $libres += $it.bytes
        Write-Host ("Voces: limpiado  " + $it.titulo)
    }
    if ($ids -contains 'xVenv') { $VozCfg.python = '' }
    if ($ids -contains 'cbVenv') { $VozCfg.pythonCb = '' }
    if ($ids -contains 'ffmpeg') { $VozCfg.ffmpeg = '' }
    Voz-Guardar-Cfg
    $script:VozFuentes = @{}
    return [ordered]@{ ok = ($fallos.Count -eq 0); libres = $libres; fallos = @($fallos) }
}

# servidor de pruebas de voz (voz_servidor.py): XTTS cargado para probar al momento
$VozSrv = @{ proc = $null; puerto = 0; token = ''; motor = '' }
function Voz-Srv-Vivo { return ($VozSrv.proc -and -not $VozSrv.proc.HasExited) }
function Voz-Srv-Parar { if (Voz-Srv-Vivo) { try { $VozSrv.proc.Kill(); $VozSrv.proc.WaitForExit(5000) } catch { } } }
function Voz-Srv-Arrancar {
    $m = $VozCfg.motor + ' ' + $VozCfg.variante
    if ((Voz-Srv-Vivo) -and $VozSrv.motor -ne $m) { Voz-Srv-Parar }      # se ha cambiado de motor
    if (Voz-Srv-Vivo) { return }
    $py = Join-Path $VozCfg.kit 'voz_servidor.py'
    if (-not (Test-Path -LiteralPath $py)) { throw 'No está voz_servidor.py en el kit de voces.' }
    $puerto = 0
    foreach ($p in 8899..8960) {
        try { $l = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p); $l.Start(); $l.Stop(); $puerto = $p; break } catch { }
    }
    if (-not $puerto) { throw 'No hay ningún puerto libre para el servidor de voz.' }
    $VozSrv.token = [Guid]::NewGuid().ToString('N'); $VozSrv.puerto = $puerto
    $arg = '"' + $py + '" --puerto ' + $puerto + ' --token ' + $VozSrv.token + ' --motor ' + $VozCfg.motor + ' --variante ' + $VozCfg.variante
    $VozSrv.motor = $m
    $VozSrv.proc = Start-Process -FilePath (Voz-Py) -ArgumentList $arg -WorkingDirectory $VozCfg.kit -WindowStyle Minimized -PassThru
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
if ($InstCsv) { Write-Host "Instalador: $InstCsv  (idioma $($InstIdi.codigo))" } else { Write-Host 'Instalador: no encontrado (el editor de campañas no estará disponible)' }
if ($InstCsv) { Write-Host "Ficheros .cam/.tac/.trn/.run en Archivos.csv: $($Filas.Count)" }
Write-Host ("Voces:      " + $(if ($VozCfg.kit) { $VozCfg.kit } else { 'kit no encontrado (carpeta Voces)' }))
Write-Host "Abierto en: $Url"
Write-Host 'Cierra esta ventana para terminar.'
try { [IO.File]::WriteAllText($UrlFich, $Url) } catch { }
$VerArranque = Editor-Version
try { [IO.File]::WriteAllText($VerFich, $VerArranque) } catch { }
$VerVisto = Get-Date
Start-Process $Url

function Leer-Consulta([string]$consulta) {
    $h = @{}
    foreach ($par in $consulta.TrimStart('?').Split('&')) {
        if (-not $par) { continue }
        $k, $v = $par.Split('=', 2)
        $k = [Uri]::UnescapeDataString($k.Replace('+', ' '))
        $v = if ($null -ne $v) { [Uri]::UnescapeDataString($v.Replace('+', ' ')) } else { '' }
        if (-not $h.ContainsKey($k)) { $h[$k] = $v }
    }
    return $h
}
$ultimo = Get-Date
$LimiteInactivo = [TimeSpan]::FromMinutes(5)
try {
    while ($Listener.IsListening) {
        $tarea = $Listener.GetContextAsync()
        while (-not $tarea.Wait(1000)) {
            if (((Get-Date) - $ultimo) -gt $LimiteInactivo) { return }
            if (((Get-Date) - $VerVisto).TotalSeconds -ge 5) {
                $VerVisto = Get-Date
                if ((Editor-Version) -ne $VerArranque) {
                    # se ha copiado una version nueva del editor encima: se reinicia solo (abre una pestaña nueva)
                    Write-Host 'El editor se ha actualizado: se reinicia con la versión nueva...' -ForegroundColor Yellow
                    Start-Process cmd.exe -ArgumentList @('/c', 'start', '"Editor de Falcon BMS"', '/min', 'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"')) -WindowStyle Hidden
                    return
                }
            }
        }
        $ctx = $tarea.Result
        $ultimo = Get-Date
        try {
            $req = $ctx.Request
            # la consulta se descodifica como UTF-8 (HttpListener usa la pagina de codigos del sistema y estropea las
            # tildes, p. ej. en los nombres de los audios de prueba)
            $q = Leer-Consulta $req.Url.Query
            $abs = $req.Url.AbsolutePath
            if ($abs -eq '/' -or $abs -eq '/index.html') {
                Responder $ctx 200 ([IO.File]::ReadAllBytes($HtmlShell)) 'text/html; charset=utf-8'; continue
            }
            if ($abs -eq '/i18n.js') {
                # idioma de la interfaz (idioma.txt junto al editor) + diccionario
                $lg = 'es'
                try { if ((Test-Path -LiteralPath $IdiomaFich) -and ([IO.File]::ReadAllText($IdiomaFich).Trim() -eq 'en')) { $lg = 'en' } } catch { }
                $js = "window.BMS_LANG='$lg';`r`n"
                if (Test-Path -LiteralPath $I18nJs) { $js += [IO.File]::ReadAllText($I18nJs, [Text.Encoding]::UTF8) }
                Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($js)) 'application/javascript; charset=utf-8'; continue
            }
            if ($abs -eq '/salir') {
                # otra version del editor pide paso (ver "una sola instancia")
                if ($q['k'] -ne $Token) { Responder $ctx 403 $null 'text/plain'; continue }
                Json $ctx 'ok'
                Write-Host 'Se abre otra versión del editor: esta se cierra.' -ForegroundColor Yellow
                return
            }
            if ($abs -eq '/idioma') {
                if ($q['k'] -ne $Token) { Responder $ctx 403 $null 'text/plain'; continue }
                $lg = 'es'; if ($q['l'] -eq 'en') { $lg = 'en' }
                try { [IO.File]::WriteAllText($IdiomaFich, $lg) } catch { }
                Json $ctx 'ok'; continue
            }
            if ($abs -eq '/idiomas' -or $abs -eq '/idioma-trabajo' -or $abs -eq '/idioma-nuevo' -or $abs -eq '/idioma-ajustes' -or $abs -eq '/idioma-probar' -or $abs -eq '/idioma-plantillas') {
                if ($q['k'] -ne $Token) { Responder $ctx 403 $null 'text/plain'; continue }
                if ($abs -eq '/idioma-trabajo') { Poner-Idioma-Trabajo ([string]$q['cod']); Write-Host ("Idioma de trabajo: " + $(if ($InstIdi) { $InstIdi.codigo + '  ' + $InstCsv } else { '-' })) }
                if ($abs -eq '/idioma-nuevo') {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; continue }
                    if (-not $InstDir -or -not (Get-Command Idioma-Crear -ErrorAction SilentlyContinue)) { Json $ctx ([ordered]@{ ok = $false; error = 'Hace falta el instalador nuevo (con Idiomas.ps1).' }); continue }
                    $c = Voz-Leer-Cuerpo $req
                    try {
                        # siempre desde el ingles (Data_ORIGINAL, o el juego si no tiene una traduccion instalada)
                        $r = Idioma-Crear $InstDir ([string]$c.codigo) ([string]$c.nombre) ([string]$c.nombreEs) ([string]$c.voz) $InstOriginal $Bms
                        Idioma-Guardar-Ajustes $r.dir $c
                        Poner-Idioma-Trabajo ([string]$c.codigo)
                        Write-Host ("Idioma nuevo: " + $r.dir + "  (" + $r.ficheros + " ficheros en inglés)")
                        $o = Info-Idiomas; $o.ok = $true; $o.ficheros = $r.ficheros; $o.sinOriginal = @($r.sinOriginal); $o.traducidos = @($r.traducidos)
                        Json $ctx $o
                    } catch { Json $ctx ([ordered]@{ ok = $false; error = $_.Exception.Message }) }
                    continue
                }
                if ($abs -eq '/idioma-plantillas') {
                    # plantillas de lectura (numeros, letras...) por idioma de voz: plantillas_lectura.json del kit
                    Voz-Autodetectar
                    $pf = if ($VozCfg.kit) { Join-Path $VozCfg.kit 'plantillas_lectura.json' } else { $null }
                    if ($pf -and (Test-Path -LiteralPath $pf)) { Responder $ctx 200 ([IO.File]::ReadAllBytes($pf)) 'application/json; charset=utf-8' }
                    else { Json $ctx ([ordered]@{}) }
                    continue
                }
                if ($abs -eq '/idioma-ajustes') {
                    # ajustes de un idioma: nombre, voz de XTTS, codificacion, como se leen numeros y letras, pronunciaciones
                    if ($req.HttpMethod -eq 'POST') {
                        $c = Voz-Leer-Cuerpo $req
                        $i = @($Idiomas | Where-Object { $_.codigo -eq ([string]$c.codigo).ToUpper() }) | Select-Object -First 1
                        if (-not $i) { Json $ctx ([ordered]@{ ok = $false; error = 'No existe ese idioma.' }); continue }
                        if ($i.legado -or -not (Get-Command Idioma-Guardar-Ajustes -ErrorAction SilentlyContinue)) {
                            Json $ctx ([ordered]@{ ok = $false; error = 'Este idioma está con el formato antiguo (Archivos.csv suelto): pásalo a Idiomas\ES para poder guardar sus ajustes.' }); continue
                        }
                        try {
                            Idioma-Guardar-Ajustes $i.dir $c
                            Poner-Idioma-Trabajo $(if ($InstIdi) { $InstIdi.codigo } else { '' })
                            Write-Host ("Ajustes del idioma " + $i.codigo + " guardados en " + $i.dir)
                            $o = Info-Idiomas; $o.ok = $true; Json $ctx $o
                        } catch { Json $ctx ([ordered]@{ ok = $false; error = $_.Exception.Message }) }
                        continue
                    }
                    $i = @($Idiomas | Where-Object { $_.codigo -eq ([string]$q['cod']).ToUpper() }) | Select-Object -First 1
                    if (-not $i) { Json $ctx ([ordered]@{ ok = $false; error = 'No existe ese idioma.' }); continue }
                    $lect = $null; $pron = ''
                    if (-not $i.legado) {
                        $j = Join-Path $i.dir 'idioma.json'
                        if (Test-Path -LiteralPath $j) { try { $lect = ([IO.File]::ReadAllText($j, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json).lectura } catch { } }
                        $pp = Join-Path $i.dir 'pronunciaciones.txt'
                        if (Test-Path -LiteralPath $pp) { $pron = [IO.File]::ReadAllText($pp, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) }
                    }
                    if (-not $pron) {
                        # las que hubiera en su carpeta de voces (el kit antiguo tenia las del espanol)
                        Voz-Autodetectar
                        if ($VozCfg.kit) { $pp = Join-Path $VozCfg.kit ('Idiomas\' + $i.codigo + '\pronunciaciones.txt'); if (Test-Path -LiteralPath $pp) { $pron = [IO.File]::ReadAllText($pp, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) } }
                    }
                    Json $ctx ([ordered]@{ ok = $true; codigo = $i.codigo; nombre = $i.nombre; nombreEs = $i.nombreEs; voz = $i.voz; codificacion = $i.codificacion
                                           lectura = $lect; pronunciaciones = $pron; legado = [bool]$i.legado; dir = $i.dir })
                    continue
                }
                if ($abs -eq '/idioma-probar') {
                    # como se leerian unas frases con unos ajustes (aun sin guardar): voces_util.py normalizar
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; continue }
                    $c = Voz-Leer-Cuerpo $req
                    Voz-Autodetectar
                    if (-not $VozCfg.kit -or -not (Voz-Py-Util) -or -not (Test-Path -LiteralPath (Join-Path $VozCfg.kit 'lectura.py'))) {
                        Json $ctx ([ordered]@{ ok = $false; error = 'Para probar hace falta el kit de voces con Python (pestaña Voces → ⚙).' }); continue
                    }
                    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('bmslec_' + [Guid]::NewGuid().ToString('N'))
                    $utf = New-Object Text.UTF8Encoding($false)
                    [IO.File]::WriteAllText($tmp + '.json', (ConvertTo-Json ([ordered]@{ voz = [string]$c.voz; lectura = $c.lectura }) -Depth 6), $utf)
                    [IO.File]::WriteAllText($tmp + '.dic', [string]$c.pronunciaciones, $utf)
                    [IO.File]::WriteAllText($tmp + '.txt', [string]$c.texto, $utf)
                    $r = Voz-Python @((Join-Path $VozCfg.kit 'voces_util.py'), 'normalizar', '--lectura', ($tmp + '.json'), '--dic', ($tmp + '.dic'), '--es-fichero', ($tmp + '.txt'))
                    foreach ($x in '.json', '.dic', '.txt') { Remove-Item -LiteralPath ($tmp + $x) -Force -ErrorAction SilentlyContinue }
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $linea) { Json $ctx ([ordered]@{ ok = $false; error = $r.texto }); continue }
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                    continue
                }
                Json $ctx (Info-Idiomas); continue
            }
            $mm = [regex]::Match($abs, '^/(scf|rsc|camp|voz|vaj|teat|str|tac|ayu)(/.*)?$')
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
            elseif ($modulo -in @('teat', 'str', 'tac')) {
            # Teatros (.tdf, .tga, Theater.irc), Strings.txt y TacRefDB.xml: ficheros que se leen y guardan enteros
            switch ($ruta) {
                '/api/info' {
                    Json $ctx ([ordered]@{ teatros = @(Mod-Lista $modulo); instalador = [bool]$InstCsv; idioma = $(if ($InstIdi) { $InstIdi.nombre } else { '' }) })
                }
                '/api/file' {
                    $rel = [string]$q['rel']
                    if (-not (Mod-Permitido $modulo $rel)) { Error404 $ctx; break }
                    $p = Teat-Ruta $rel ([string]$q['src'])
                    if (-not $p) { Error404 $ctx; break }
                    Responder $ctx 200 ([IO.File]::ReadAllBytes($p)) 'application/octet-stream'
                }
                '/api/guardar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $rel = [string]$q['rel']
                    if (-not (Mod-Permitido $modulo $rel)) { Json $ctx ([ordered]@{ ok = $false; error = 'fichero no válido' }); break }
                    $ms = New-Object IO.MemoryStream; $req.InputStream.CopyTo($ms); $bytes = $ms.ToArray()
                    if ($bytes.Length -lt 16) { Json $ctx ([ordered]@{ ok = $false; error = 'contenido vacío' }); break }
                    # el original del juego solo sirve de copia si no es ya una traduccion instalada
                    $origen = RutaSegura $Data $rel
                    if ($origen -and (Voz-Espanol-Instalado $rel)) { $origen = $null }
                    $g = Guardar-Editado $rel $bytes $(switch ($modulo) { 'str' { 'Strings' } 'tac' { 'TacRefDB' } default { 'Teatros' } }) $origen
                    Json $ctx ([ordered]@{ ok = $true; ruta = $g.ruta; original = $g.original; csv = $g.csv; igual = $g.igual; retirable = $g.retirable })
                }
                '/api/ping' { Json $ctx 'ok' }
                default { Error404 $ctx }
            }
            }
            elseif ($modulo -eq 'ayu') {
            # Ayuda y menus: ficheros enteros (GuideTxt, HelpText, Menu.dat) y el LckTxtRc.irc (base + cambios)
            switch ($ruta) {
                '/api/info' { $a = Ayu-Lista; $a.idioma = $(if ($InstIdi) { $InstIdi.nombre } else { '' }); Json $ctx $a }
                '/api/file' {
                    $rel = [string]$q['rel']
                    if (-not (Ayu-Permitido $rel)) { Error404 $ctx; break }
                    $p = Teat-Ruta $rel ([string]$q['src'])
                    if (-not $p) { Error404 $ctx; break }
                    Responder $ctx 200 ([IO.File]::ReadAllBytes($p)) 'application/octet-stream'
                }
                '/api/guardar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $rel = [string]$q['rel']
                    if (-not (Ayu-Permitido $rel)) { Json $ctx ([ordered]@{ ok = $false; error = 'fichero no válido' }); break }
                    $ms = New-Object IO.MemoryStream; $req.InputStream.CopyTo($ms); $bytes = $ms.ToArray()
                    if ($bytes.Length -lt 16) { Json $ctx ([ordered]@{ ok = $false; error = 'contenido vacío' }); break }
                    $origen = RutaSegura $Data $rel
                    if ($origen -and (Voz-Espanol-Instalado $rel)) { $origen = $null }
                    $g = Guardar-Editado $rel $bytes 'Ayuda' $origen
                    Json $ctx ([ordered]@{ ok = $true; ruta = $g.ruta; original = $g.original; csv = $g.csv; igual = $g.igual; retirable = $g.retirable })
                }
                '/api/lck' {
                    $que = [string]$q['que']; $t = [string]$q['t']
                    $teat = @((Ayu-Lista).lck | Where-Object { $_.clave -ieq $t }) | Select-Object -First 1
                    if ($req.HttpMethod -ne 'POST') {
                        if ($que -eq 'base') { $p = Lck-Fichero 'COREA' }
                        elseif ($que -eq 'cambios') { $p = $(if ($teat) { Lck-Fichero $teat.clave -Cambios } else { $null }) }
                        elseif ($que -eq 'en') { $rel = [string]$q['rel']; $p = $(if ($teat -and ($teat.rels -contains $rel)) { Teat-Ruta $rel 'en' } else { $null }) }
                        else { $p = $null }
                        if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { Error404 $ctx; break }
                        Responder $ctx 200 ([IO.File]::ReadAllBytes($p)) 'application/octet-stream'; break
                    }
                    $ms = New-Object IO.MemoryStream; $req.InputStream.CopyTo($ms); $bytes = $ms.ToArray()
                    if ($que -eq 'base') {
                        $p = Lck-Fichero 'COREA'
                        if (-not $p) { Json $ctx ([ordered]@{ ok = $false; error = 'No se encuentra el LckTxtRc.irc base en Archivos.csv' }); break }
                        foreach ($x in (Ayu-Lista).lck) { foreach ($rel in $x.rels) { Asegurar-Original $rel } }
                        Escribir $p $bytes; Write-Host ("Guardado:  " + $p)
                        # teatros que aun no lo tenian en Archivos.csv: se les instala tambien la base traducida
                        $bf = Lck-Base-Fich
                        if ($bf) { foreach ($x in @((Ayu-Lista).lck | Where-Object { $_.nuevo })) { Lck-Anadir-Filas $x $bf } }
                        Json $ctx ([ordered]@{ ok = $true; ruta = $p }); break
                    }
                    if ($que -eq 'cambios' -and $teat) {
                        $p = Lck-Fichero $teat.clave -Cambios; $csv = $null
                        if (-not $p) {
                            $fich = 'LckTxtRc\Cambios_' + $teat.clave + '.irc'
                            $p = RutaSegura $InstFicheros $fich
                            if ($teat.nuevo) { $bf = Lck-Base-Fich; if (-not $bf) { Json $ctx ([ordered]@{ ok = $false; error = 'No se encuentra el LckTxtRc.irc base en Archivos.csv' }); break }; Lck-Anadir-Filas $teat ($bf + ' + ' + $fich) }
                            else { Lck-Csv-Cambios $teat.clave $fich }
                            $csv = $fich
                            Write-Host ("Archivos.csv: LckTxtRc.irc + $fich  ($($teat.clave))")
                        }
                        foreach ($rel in $teat.rels) { Asegurar-Original $rel }
                        Escribir $p $bytes; Write-Host ("Guardado:  " + $p)
                        Json $ctx ([ordered]@{ ok = $true; ruta = $p; csv = $csv }); break
                    }
                    Json $ctx ([ordered]@{ ok = $false; error = 'petición no válida' })
                }
                '/api/ping' { Json $ctx 'ok' }
                default { Error404 $ctx }
            }
            }
            elseif ($modulo -eq 'voz' -or $modulo -eq 'vaj') {
            # cada idioma tiene sus listas, wav y Falcon.tlk (Voz-Dir); las de otro idioma salen de su F4Talk.csv
            if ($ruta -in @('/api/info', '/api/lista', '/api/generar', '/api/montar', '/api/regmontar', '/api/texto')) {
                if ($VozCfg.kit -and (Voz-Py-Util)) { Voz-Preparar-Mapas }
                Voz-Quitar-Listas-Viejas
            }
            switch ($ruta) {
                '/api/ping' { Json $ctx 'ok' }
                '/api/info' {
                    Voz-Autodetectar
                    if ($q['buscar'] -eq '1') { Voz-Buscar-Tlk }
                    $kit = $VozCfg.kit
                    $vd = if ($kit) { Voz-Dir } else { $null }
                    # (no llamarlo $teatros: PowerShell no distingue mayusculas y pisaria $Teatros, la lista de teatros
                    # de todo el editor, y despues ya no se encontrarian los F4Talk ni nada que dependa de ella)
                    $vozLista = @(foreach ($t in $VozTeatros) {
                        $ing = Voz-Tlk-Ingles $t
                        $mont = if ($kit) { Join-Path $vd.base ("Falcon_" + $t.nombre + '.tlk') } else { $null }
                        $ed = Ruta-Editado $t.rel
                        [ordered]@{
                            nombre = $t.nombre; rel = $t.rel
                            lista = [bool]($kit -and (Voz-Mapa $t.nombre))
                            ingles = $ing.ruta; inglesSeguro = $ing.seguro
                            enOriginal = [bool]((Ruta-Original $t.rel) -and (Test-Path -LiteralPath (Ruta-Original $t.rel)))
                            montado = $(if ($mont -and (Test-Path -LiteralPath $mont)) { (Get-Item -LiteralPath $mont).LastWriteTime.ToString('dd/MM HH:mm') } else { '' })
                            montadoMs = $(if ($mont -and (Test-Path -LiteralPath $mont)) { [DateTimeOffset]::new((Get-Item -LiteralPath $mont).LastWriteTime).ToUnixTimeMilliseconds() } else { 0 })
                            enInstalador = $(if ($ed -and (Test-Path -LiteralPath $ed)) { (Get-Item -LiteralPath $ed).LastWriteTime.ToString('dd/MM HH:mm') } else { '' })
                            subtitulosDonde = $(if ($InstFicheros) { Join-Path $InstFicheros 'F4Talk' } else { '' })
                            subtitulosHay = @(if ($InstFicheros -and (Test-Path -LiteralPath (Join-Path $InstFicheros 'F4Talk'))) { Get-ChildItem -LiteralPath (Join-Path $InstFicheros 'F4Talk') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } })
                            subtitulos = $(if ($InstFicheros) { $sf = Voz-F4Talk $t.nombre; if ($sf) { $sf } else { '' } } else { '' })
                        }
                    })
                    $ffok = $false
                    if ($VozCfg.ffmpeg) { $ffok = Voz-Ffmpeg-Ok }
                    Json $ctx ([ordered]@{
                        kit = $kit; python = (Voz-Py); ffmpeg = $VozCfg.ffmpeg
                        motor = $VozCfg.motor; variante = $VozCfg.variante
                        hayXtts = [bool]($VozCfg.python -and (Test-Path -LiteralPath $VozCfg.python)); hayCb = [bool]($VozCfg.pythonCb -and (Test-Path -LiteralPath $VozCfg.pythonCb))
                        okKit = [bool]($kit -and (Test-Path -LiteralPath (Join-Path $kit 'generar_voces.py')))
                        okRefs = [bool]($kit -and @(0..13 | Where-Object { -not (Test-Path -LiteralPath (Join-Path $kit ('ref\voz{0:D2}.wav' -f $_))) }).Count -eq 0)
                        okPython = [bool]((Voz-Py) -and (Test-Path -LiteralPath (Voz-Py)))
                        okFfmpeg = $ffok; okXtts = (Voz-Xtts-Ok)
                        preparar = [bool]($kit -and (Test-Path -LiteralPath (Join-Path $kit 'Preparar_voces.ps1')))
                        instalador = $InstCsv; teatros = $vozLista; trabajos = @(Voz-Estado-Trabajos); ajustes = $VozAj
                        idioma = $(if ($InstIdi) { $InstIdi.nombre } else { '' }); codigo = (Voz-Cod); idiomaVoz = (Voz-IdiomaVoz)
                        lectura = $(if ($kit) { Voz-Lectura } else { '' }); dic = $(if ($kit) { Voz-Dic } else { '' }); frasePrueba = (Voz-Frase-Prueba)
                        carpeta = $(if ($vd) { $vd.base } else { '' })
                        version = $VerArranque; sinListas = $true
                    })
                }
                '/api/elegir' {
                    $que = $q['que']
                    if ($que -notin @('kit', 'python', 'ffmpeg')) { Error404 $ctx; break }
                    $r = Voz-Elegir $que
                    if ($que -eq 'python' -and $VozCfg.motor -ne 'xtts') { $que = 'pythonCb' }     # el Python del motor elegido
                    if ($r) { $VozCfg[$que] = $r; Voz-Guardar-Cfg }
                    Json $ctx ([ordered]@{ ok = [bool]$r; ruta = $r })
                }
                '/api/lista' {
                    $t = Voz-Teatro $q['t']; if (-not $t -or -not $VozCfg.kit) { Error404 $ctx; break }
                    $b = Voz-Tabla $t
                    if (-not $b) { Responder $ctx 500 ([Text.Encoding]::UTF8.GetBytes([string]$script:VozErrTabla)) 'text/plain; charset=utf-8'; break }
                    Responder $ctx 200 $b 'text/plain; charset=utf-8'
                }
                '/api/generados' {
                    $t = Voz-Teatro $q['t']; if (-not $t -or -not $VozCfg.kit) { Error404 $ctx; break }
                    # los wav generados con el texto actual del F4Talk (los de un texto anterior no cuentan)
                    $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'generados', '--teatro', $t.nombre, '--wav', (Voz-Dir).wav, '--codificacion', (Voz-Codif), '--f4talk', (Voz-F4Talk-Json @($t.nombre)))
                    if ($InstFicheros) { $a += @('--ficheros', [string]$InstFicheros) }
                    $r = Voz-Python $a
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('[') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $linea) { Json $ctx @(); break }
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                }
                '/api/audio' {
                    $t = Voz-Teatro $q['t']; if (-not $t) { Error404 $ctx; break }
                    $id = 0; if (-not [int]::TryParse([string]$q['id'], [ref]$id)) { Error404 $ctx; break }
                    $desde = $null
                    if ($q['src'] -eq 'es') {
                        $p = Join-Path (Join-Path (Voz-Dir).wav $t.nombre) ("$id" + '.wav')
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
                    if ($r.codigo -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { Write-Host ("Voces: " + $r.texto) -ForegroundColor Red; Responder $ctx 500 ([Text.Encoding]::UTF8.GetBytes([string]$r.texto)) 'text/plain; charset=utf-8'; break }
                    $b = [IO.File]::ReadAllBytes($tmp); Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    Responder $ctx 200 $b 'audio/wav'
                }
                '/api/texto' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('bmsvoz_' + [Guid]::NewGuid().ToString('N') + '.txt')
                    [IO.File]::WriteAllText($tmp, [string]$c.es, (New-Object Text.UTF8Encoding($false)))
                    $vd = Voz-Dir
                    $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'texto', '--teatro', $t.nombre, '--id', ([string][int]$c.id), '--es-fichero', $tmp,
                           '--wav', $vd.wav, '--codificacion', (Voz-Codif))
                    # el texto se cambia en el F4Talk.csv (subtitulos) de cada teatro en el instalador: es el unico sitio donde esta.
                    # Los teatros sin F4Talk.csv en el instalador (Add-On nuevos) lo reciben ahora, desde el ingles
                    foreach ($x in $VozTeatros) { if (-not (Voz-F4Talk $x.nombre)) { [void](Voz-F4Talk-Asegurar $x.nombre) } }
                    $a += @(Voz-Args-F4Talk) + @('--respaldo', (Join-Path $Respaldo 'F4Talk'))
                    $r = Voz-Python $a
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    if ($r.codigo -ne 0) { Json $ctx ([ordered]@{ ok = $false; error = $r.texto }); break }
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                }
                '/api/sospechosos' {
                    # audios generados del teatro que duran mucho menos o mucho mas de lo que deberia su texto
                    $t = Voz-Teatro $q['t']; if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', $t.nombre) + @(Voz-Args-Ajustes) + @(Voz-Args-Idioma) + @('--sospechosos')
                    $r = Voz-Python $a
                    $l = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $l) { Json $ctx ([ordered]@{ ok = $false; error = (($r.texto -split "`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1) }); break }
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($l)) 'application/json; charset=utf-8'
                }
                '/api/desfasadas' {
                    # antes de Generar: qué falta y qué voces han cambiado (referencia o ajustes) desde que se generaron
                    $c = Voz-Leer-Cuerpo $req
                    $teatro = [string]$c.t
                    if ($teatro -ne 'todos' -and -not (Voz-Teatro $teatro)) { $teatro = 'todos' }
                    $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', $teatro) + @(Voz-Args-Ajustes)
                    if ($c.igual -in @('todo', 'nada')) { $a += @('--igual', [string]$c.igual) }
                    $a += @(Voz-Args-Idioma) + @('--desfasadas')
                    $r = Voz-Python $a
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $linea) { Json $ctx ([ordered]@{ ok = $false; error = ($r.texto -split "`n" | Select-Object -Last 1) }); break }
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
                        if ($c.idsDe -and (Voz-Teatro ([string]$c.idsDe))) {
                            # tlkId de ese teatro; tambien sus copias en los otros teatros (misma voz y texto)
                            $a += @('--ids-de', [string]$c.idsDe)
                            $titulo = 'Regenerando ' + @($c.ids).Count + ' audios sospechosos (' + [string]$c.idsDe + ')'
                        }
                    }
                    if ($c.prueba) { $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--prueba', ([string][int]$c.prueba)); $titulo = 'Prueba de voces (' + (Voz-Cod) + ')' }
                    if ($c.comparar) { $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--comparar', ([string][int]$c.comparar)); $titulo = 'Comparando ajustes de voz' }
                    if ($c.refiltrar) { $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', 'todos', '--refiltrar'); $titulo = 'Aplicando efectos de radio y volumen' }
                    $a += @(Voz-Args-Ajustes)
                    if ($c.igual -in @('todo', 'nada')) { $a += @('--igual', [string]$c.igual) }
                    if ($null -ne $c.rehacerVoz) { $vv = [int]$c.rehacerVoz; $a = @((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', 'todos', '--voces', "$vv", '--rehacer') + @(Voz-Args-Ajustes); $titulo = ('Regenerando la voz {0:D2} (4 teatros)' -f $vv) }
                    if ($c.regenerar -and -not $c.prueba -and -not $c.comparar -and -not $c.refiltrar) {
                        $rv = @($c.regenerar | ForEach-Object { [int]$_ } | Where-Object { $_ -ge 0 -and $_ -le 13 })
                        if ($rv.Count) { $a += @('--regenerar-voces', ($rv -join ',')); $titulo += ' + voces ' + (($rv | ForEach-Object { '{0:D2}' -f $_ }) -join ', ') }
                    }
                    $a += @(Voz-Args-Idioma)
                    if ((Voz-Cod) -ne 'ES') { $titulo += ' · ' + (Voz-Cod) }
                    $id = Voz-Lanzar 'generar' $teatro $titulo $a
                    Json $ctx ([ordered]@{ ok = $true; id = $id })
                }
                '/api/montar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $mot = $(if ([string]$c.motor -in @('chatterbox', 'xtts')) { [string]$c.motor } else { $VozCfg.motor })
                    $a = Voz-Args-Montar $t $mot ([bool]$c.solo)
                    $id = Voz-Lanzar 'montar' $t.nombre ("Montando Falcon.tlk de " + $t.nombre + " (" + $(if ($mot -eq 'xtts') { 'XTTS' } else { 'Chatterbox' }) + $(if ($c.solo) { ', sin mezclar' } else { '' }) + ")") $a
                    Json $ctx ([ordered]@{ ok = $true; id = $id })
                }
                '/api/pretraducir' {
                    # rellena lo que sigue en ingles en el F4Talk del teatro con lo ya traducido en los otros teatros
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    if (-not $InstFicheros) { Json $ctx ([ordered]@{ ok = $false; error = 'No hay instalador del idioma de trabajo.' }); break }
                    if (-not (Voz-F4Talk $t.nombre)) { [void](Voz-F4Talk-Asegurar $t.nombre) }     # sin F4Talk: copia del ingles
                    $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'pretraducir', '--teatro', $t.nombre, '--codificacion', (Voz-Codif),
                           '--salida', (Join-Path (Voz-Dir).base ('pretraducido_' + $t.nombre + '.json')), '--respaldo', (Join-Path $Respaldo 'F4Talk')) + @(Voz-Args-F4Talk)
                    $r = Voz-Python $a
                    $l = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $l) { Json $ctx ([ordered]@{ ok = $false; error = (($r.texto -split "`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1) }); break }
                    Write-Host ("Voces: pretraducido " + $t.nombre + ": " + $l)
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($l)) 'application/json; charset=utf-8'
                }
                '/api/pretraducido' {
                    $t = Voz-Teatro $q['t']; if (-not $t) { Json $ctx $null; break }
                    $f = Join-Path (Voz-Dir).base ('pretraducido_' + $t.nombre + '.json')
                    if (-not (Test-Path -LiteralPath $f)) { Json $ctx $null; break }
                    Responder $ctx 200 ([IO.File]::ReadAllBytes($f)) 'application/json; charset=utf-8'
                }
                '/api/pretraducir-deshacer' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $f = Join-Path (Voz-Dir).base ('pretraducido_' + $t.nombre + '.json')
                    $j = $null; try { $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json } catch { }
                    $dst = Voz-F4Talk $t.nombre
                    if (-not $j -or -not $j.copia -or -not (Test-Path -LiteralPath $j.copia) -or -not $dst) { Json $ctx ([ordered]@{ ok = $false; error = 'No está la copia de antes de pretraducir.' }); break }
                    Copy-Item -LiteralPath $j.copia -Destination $dst -Force
                    (Get-Item -LiteralPath $dst).LastWriteTime = Get-Date      # fecha nueva: la tabla se vuelve a leer
                    Remove-Item -LiteralPath $f -Force
                    Write-Host ("Voces: deshecha la pretraduccion de " + $t.nombre + " (" + $dst + ")")
                    Json $ctx ([ordered]@{ ok = $true })
                }
                '/api/motor-version' {
                    # version instalada del motor y la ultima publicada (PyPI), con el Python de su entorno
                    $m = $(if ($q['m'] -eq 'xtts') { 'xtts' } else { 'chatterbox' })
                    $py = $(if ($m -eq 'xtts') { $VozCfg.python } else { $VozCfg.pythonCb })
                    if (-not $py -or -not (Test-Path -LiteralPath $py)) { Json $ctx ([ordered]@{ ok = $false; error = 'Este motor no está instalado: usa «Preparar entorno».' }); break }
                    $env:PYTHONIOENCODING = 'utf-8'; $eapAntes = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                    $sal = & $py (Join-Path $VozCfg.kit 'actualizar_motor.py') '--motor' $m '--comprobar' 2>&1
                    $ErrorActionPreference = $eapAntes
                    $l = (@($sal | ForEach-Object { "$_" }) | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if (-not $l) { Json $ctx ([ordered]@{ ok = $false; error = ((@($sal | ForEach-Object { "$_" })) -join ' ') }); break }
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($l)) 'application/json; charset=utf-8'
                }
                '/api/motor-actualizar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $m = $(if ([string]$c.m -eq 'xtts') { 'xtts' } else { 'chatterbox' })
                    $py = $(if ($m -eq 'xtts') { $VozCfg.python } else { $VozCfg.pythonCb })
                    if (-not $py -or -not (Test-Path -LiteralPath $py)) { Json $ctx ([ordered]@{ ok = $false; error = 'Este motor no está instalado: usa «Preparar entorno».' }); break }
                    Voz-Srv-Parar      # el servidor de pruebas tiene el motor cargado: en Windows no se podrian sustituir sus ficheros
                    $id = Voz-Lanzar 'actualizar' '' ('Actualizando ' + $(if ($m -eq 'xtts') { 'XTTS (coqui-tts)' } else { 'Chatterbox (chatterbox-tts)' })) @((Join-Path $VozCfg.kit 'actualizar_motor.py'), '--motor', $m, '--actualizar') $py
                    Json $ctx ([ordered]@{ ok = $true; id = $id })
                }
                '/api/montar-info' {
                    # para elegir con que motor montar: audios generados (con el texto actual) de cada uno en este teatro
                    $t = Voz-Teatro $q['t']; if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $o = [ordered]@{ ok = $true; actual = $VozCfg.motor }
                    foreach ($m in @('chatterbox', 'xtts')) {
                        $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'generados', '--teatro', $t.nombre, '--wav', (Voz-Wav-De $m), '--codificacion', (Voz-Codif), '--f4talk', (Voz-F4Talk-Json @($t.nombre)))
                        if ($InstFicheros) { $a += @('--ficheros', [string]$InstFicheros) }
                        $r = Voz-Python $a
                        $l = ($r.texto -split "`n" | Where-Object { $_.StartsWith('[') } | Select-Object -Last 1)
                        $o[$m] = $(if ($l -and $l.Trim() -ne '[]') { $l.Split(',').Count } else { 0 })
                    }
                    $ed = Ruta-Editado $t.rel
                    $o.enInstalador = [bool]($ed -and (Test-Path -LiteralPath $ed -PathType Leaf))
                    Json $ctx $o
                }
                '/api/regmontar' {
                    # regenera un clip y monta el Falcon.tlk de los teatros que lo usan (luego la página lo guarda en el instalador)
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    $id = [int]$c.id
                    # los tlkId comunes (< 33386) son los mismos en los 4 teatros
                    $vd = Voz-Dir
                    $afect = @(if ($id -lt 33386) { $VozTeatros | Where-Object { Voz-Mapa $_.nombre } } else { $t })
                    $pasos = New-Object System.Collections.ArrayList
                    [void]$pasos.Add(@((Join-Path $VozCfg.kit 'generar_voces.py'), '--teatro', $(if ($id -lt 33386) { 'todos' } else { $t.nombre }), '--ids', "$id", '--forzar') + @(Voz-Args-Ajustes) + @(Voz-Args-Idioma))
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
                    if ($c.limpiar -and -not $c.inicial) { $a += '--limpiar' }
                    $r = Voz-Python $a
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $linea) { Json $ctx ([ordered]@{ ok = $false; error = ($r.texto -split "`n" | Select-Object -Last 1) }); break }
                    Write-Host ('Voces: nueva referencia para la voz {0:D2}' -f [int]$c.voz)
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                }
                '/api/ref-limpiar' {
                    # limpia (o deshace la limpieza de) la referencia de una voz o de las 14: ruido de fondo y saturación
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $a = @((Join-Path $VozCfg.kit 'voces_util.py'), 'limpiar-ref')
                    if ($null -ne $c.voz -and "$($c.voz)" -ne '') { $a += @('--voz', ([string][int]$c.voz)) }
                    if ($c.quitar) { $a += '--quitar' }
                    $r = Voz-Python $a
                    $linea = ($r.texto -split "`n" | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1)
                    if ($r.codigo -ne 0 -or -not $linea) { Json $ctx ([ordered]@{ ok = $false; error = ($r.texto -split "`n" | Select-Object -Last 1) }); break }
                    Write-Host ('Voces: referencia {0} {1}' -f $(if ($null -ne $c.voz -and "$($c.voz)" -ne '') { '{0:D2}' -f [int]$c.voz } else { '(las 14)' }), $(if ($c.quitar) { 'sin limpiar' } else { 'limpiada' }))
                    Responder $ctx 200 ([Text.Encoding]::UTF8.GetBytes($linea)) 'application/json; charset=utf-8'
                }
                '/api/servidor' {
                    if ($req.HttpMethod -eq 'POST') { Voz-Srv-Arrancar }
                    Json $ctx ([ordered]@{ enMarcha = (Voz-Srv-Vivo); puerto = $VozSrv.puerto; token = $(if (Voz-Srv-Vivo) { $VozSrv.token } else { '' }); motor = $VozCfg.motor; variante = $VozCfg.variante })
                }
                '/api/ajustes-voces' {
                    if ($req.HttpMethod -eq 'POST') {
                        $c = Voz-Leer-Cuerpo $req
                        $v = [int]$c.voz; if ($v -lt 0 -or $v -gt 13) { Json $ctx ([ordered]@{ ok = $false; error = 'voz no válida' }); break }
                        $h = Voz-Aj-Leer; $k = '{0:D2}' -f $v
                        if ($null -eq $c.ajustes) { $h.Remove($k) }
                        else {
                            # se mezcla con lo que ya tuviera la voz (cada motor guarda sus propios valores)
                            $o = [ordered]@{}
                            if ($h.Contains($k) -and $h[$k]) { foreach ($pp in $h[$k].PSObject.Properties) { $o[$pp.Name] = $pp.Value } }
                            foreach ($n in 'temperatura', 'velocidad', 'cbTemperatura', 'expresividad', 'cfg', 'rms', 'radio', 'suavizado', 'limpieza', 'pausaInicio', 'pausaFin') {
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
                    $base = (Voz-Dir).prueba
                    $lista = @()
                    if ($VozCfg.kit -and (Test-Path -LiteralPath $base)) {
                        $lista = @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.wav' | Sort-Object FullName | ForEach-Object {
                            [ordered]@{ f = $_.FullName.Substring($base.Length).TrimStart('\'); fecha = $_.LastWriteTime.ToString('dd/MM HH:mm') }
                        })
                    }
                    Json $ctx $lista
                }
                '/api/prueba-audio' {
                    $p = RutaSegura (Voz-Dir).prueba ([string]$q['f'])
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
                '/api/motor' {
                    # motor de voz: chatterbox (por defecto) o xtts; variante de Chatterbox: v3 o es-es
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $ocupado = @($VozTrabajos | Where-Object { -not $_.proc.HasExited }) | Select-Object -First 1
                    if ($ocupado) { Json $ctx ([ordered]@{ ok = $false; error = "Hay un proceso en marcha ($($ocupado.titulo)). Espera a que termine." }); break }
                    if ($c.motor -in @('chatterbox', 'xtts')) { $VozCfg.motor = [string]$c.motor }
                    if ($c.variante -in @('v3', 'es-es')) { $VozCfg.variante = [string]$c.variante }
                    Voz-Srv-Parar; Voz-Guardar-Cfg
                    Write-Host ("Voces: motor " + $VozCfg.motor + $(if ($VozCfg.motor -eq 'chatterbox') { ' ' + $VozCfg.variante } else { '' }))
                    Json $ctx ([ordered]@{ ok = $true; motor = $VozCfg.motor; variante = $VozCfg.variante })
                }
                '/api/preparar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $ps1 = Join-Path $VozCfg.kit 'Preparar_voces.ps1'
                    if (-not (Test-Path -LiteralPath $ps1)) { Json $ctx ([ordered]@{ ok = $false; error = 'No está Preparar_voces.ps1 en el kit.' }); break }
                    $c = Voz-Leer-Cuerpo $req
                    $rest = [bool]($c -and $c.restaurar)
                    # el servidor de pruebas usa el Python de la venv: se cierra antes de tocarla
                    Voz-Srv-Parar
                    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1, '-Motor', $VozCfg.motor); if ($rest) { $a += '-Restaurar' }
                    # Falcon.tlk original de Corea: para crear las referencias de voz si el kit viene sin ellas
                    $tc = Voz-Teatro 'Corea'
                    if ($tc) { $ing = Voz-Tlk-Ingles $tc; if ($ing.seguro -and $ing.ruta -and (Test-Path -LiteralPath $ing.ruta -PathType Leaf)) { $a += @('-Tlk', $ing.ruta) } }
                    $id = Voz-Lanzar 'preparar' '' $(if ($rest) { 'Restaurando el entorno de voces' } else { 'Preparando el entorno de voces' }) $a (Join-Path $PSHOME 'powershell.exe')
                    Json $ctx ([ordered]@{ ok = $true; id = $id })
                }
                '/api/limpiar' {
                    # GET: lo que se puede borrar (con tamanos); POST {ids:[...]}: lo borra
                    if ($req.HttpMethod -ne 'POST') { Json $ctx ([ordered]@{ ok = $true; kit = $VozCfg.kit; items = @(Voz-Limpiar-Plan) }); break }
                    $c = Voz-Leer-Cuerpo $req
                    Json $ctx (Voz-Limpiar @($c.ids))
                }
                '/api/guardar' {
                    if ($req.HttpMethod -ne 'POST') { Responder $ctx 405 $null 'text/plain'; break }
                    $c = Voz-Leer-Cuerpo $req
                    $t = Voz-Teatro ([string]$c.t); if (-not $t) { Json $ctx ([ordered]@{ ok = $false; error = 'teatro no válido' }); break }
                    if (-not $InstCsv) { Json $ctx ([ordered]@{ ok = $false; error = 'No se ha encontrado el instalador (Instalador\Archivos.csv).' }); break }
                    foreach ($w in $VozTrabajos) { if ($w.tipo -eq 'montar' -and $w.teatro -eq $t.nombre -and -not $w.proc.HasExited) { throw 'El montaje de este teatro aún está en marcha.' } }
                    $mont = Join-Path (Voz-Dir).base ("Falcon_" + $t.nombre + '.tlk')
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
                                    hayFich = [bool]($(Ruta-De $f 'fich') -and (Test-Path -LiteralPath (Ruta-De $f 'fich') -PathType Leaf)) }
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
                    if (-not $f.fich) {
                        # fichero de un teatro nuevo que aun no esta en el instalador: original a Data_ORIGINAL, copia a Ficheros y linea en Archivos.csv
                        $g = Guardar-Editado $f.data $bytes 'Campaign' $null
                        if ($g.ruta) { $f.fich = $g.ruta.Substring($InstFicheros.TrimEnd('\').Length + 1) }
                        Json $ctx ([ordered]@{ ok = $true; ruta = $g.ruta; fich = $f.fich; csv = $g.csv; igual = $g.igual }); break
                    }
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
