# Idiomas de la traducción de Falcon BMS (lo usan el instalador, el editor y Revisar_redundantes).
#
# Estructura (la carpeta Idiomas va dentro de Instalador o junto a ella, donde estaba Ficheros):
#   Idiomas\
#     actual.txt              código del idioma elegido (instalador y editor)
#     ES\
#       idioma.json           {"codigo":"ES","nombre":"Español","nombreEs":"español","voz":"es","codificacion":1252}
#       Archivos.csv          Teatro;Ficheros;Data   (igual que antes)
#       Ficheros\
#     PT\ ...
#   Data_ORIGINAL\            originales en inglés: comunes a todos los idiomas
#
# Formato antiguo (Archivos.csv junto a Instalador.ps1 y una sola carpeta Ficheros): se trata como el
# idioma ES hasta que se reorganiza con Idiomas-Migrar (el instalador lo propone al arrancar).

function Idiomas-Raiz([string]$instDir) {
    foreach ($c in @((Join-Path $instDir 'Idiomas'), (Join-Path (Split-Path $instDir -Parent) 'Idiomas'))) {
        if (Test-Path -LiteralPath $c -PathType Container) { return $c }
    }
    return $null
}

function Idiomas-Legado([string]$instDir) {
    $csv = Join-Path $instDir 'Archivos.csv'
    if (-not (Test-Path -LiteralPath $csv -PathType Leaf)) { return $null }
    $f = Join-Path $instDir 'Ficheros'
    if (-not (Test-Path -LiteralPath $f)) { $f = Join-Path (Split-Path $instDir -Parent) 'Ficheros' }
    return [pscustomobject]@{ csv = $csv; ficheros = $f }
}

function Idioma-Leer([string]$dir) {
    $cod = (Split-Path $dir -Leaf).ToUpper()
    $i = [pscustomobject]@{ codigo = $cod; nombre = $cod; nombreEs = $cod; voz = $cod.ToLower(); codificacion = 1252
                            dir = $dir; csv = (Join-Path $dir 'Archivos.csv'); ficheros = (Join-Path $dir 'Ficheros'); legado = $false }
    $j = Join-Path $dir 'idioma.json'
    if (Test-Path -LiteralPath $j) {
        try {
            $o = [IO.File]::ReadAllText($j, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            if ($o.nombre) { $i.nombre = [string]$o.nombre; $i.nombreEs = [string]$o.nombre }
            if ($o.nombreEs) { $i.nombreEs = [string]$o.nombreEs }
            if ($o.voz) { $i.voz = [string]$o.voz }
            if ($o.codificacion) { $i.codificacion = [int]$o.codificacion }
        } catch { }
    }
    return $i
}

function Idioma-Guardar-Json([string]$dir, [string]$cod, [string]$nombre, [string]$nombreEs, [string]$voz, [int]$cp) {
    if (-not $nombreEs) { $nombreEs = $nombre }
    if (-not $voz) { $voz = $cod.ToLower() }
    if (-not $cp) { $cp = 1252 }
    $o = [ordered]@{ codigo = $cod.ToUpper(); nombre = $nombre; nombreEs = $nombreEs; voz = $voz; codificacion = $cp }
    [IO.File]::WriteAllText((Join-Path $dir 'idioma.json'), (ConvertTo-Json $o), (New-Object Text.UTF8Encoding($false)))
}

# Hay que reorganizar: existe el formato antiguo y aún no hay Idiomas\ES\Archivos.csv
# (puede existir ya Idiomas\ES\Ficheros si se descomprimió encima una versión nueva del paquete)
function Idiomas-Necesita-Migrar([string]$instDir) {
    if (-not (Idiomas-Legado $instDir)) { return $false }
    $raiz = Idiomas-Raiz $instDir
    return (-not $raiz -or -not (Test-Path -LiteralPath (Join-Path $raiz 'ES\Archivos.csv')))
}

# Guarda los ajustes de un idioma ($c: nombre, nombreEs, voz, codificacion, lectura, pronunciaciones)
# en su idioma.json (sin perder otras claves) y en su pronunciaciones.txt
function Idioma-Guardar-Ajustes([string]$dir, $c) {
    $j = Join-Path $dir 'idioma.json'
    $o = [ordered]@{}
    if (Test-Path -LiteralPath $j) {
        try {
            $v = [IO.File]::ReadAllText($j, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            foreach ($p in $v.PSObject.Properties) { $o[$p.Name] = $p.Value }
        } catch { }
    }
    $o['codigo'] = (Split-Path $dir -Leaf).ToUpper()
    foreach ($k in 'nombre', 'nombreEs', 'voz') { if ($c.$k) { $o[$k] = [string]$c.$k } }
    if ($c.codificacion) { $o['codificacion'] = [int]$c.codificacion }
    if ($null -ne $c.lectura) { $o['lectura'] = $c.lectura }
    [IO.File]::WriteAllText($j, (ConvertTo-Json $o -Depth 6), (New-Object Text.UTF8Encoding($false)))
    if ($null -ne $c.pronunciaciones) {
        [IO.File]::WriteAllText((Join-Path $dir 'pronunciaciones.txt'), [string]$c.pronunciaciones, (New-Object Text.UTF8Encoding($true)))
    }
}

# Idiomas disponibles (con el formato antiguo, el español es el de Archivos.csv y Ficheros sueltos)
function Idiomas-Lista([string]$instDir) {
    $l = @()
    $raiz = Idiomas-Raiz $instDir
    if ($raiz) {
        $l = @(Get-ChildItem -LiteralPath $raiz -Directory | Where-Object { $_.Name -match '^[A-Za-z]{2,3}(-[A-Za-z]{2})?$' } |
               Sort-Object Name | ForEach-Object { Idioma-Leer $_.FullName })
    }
    $leg = Idiomas-Legado $instDir
    if ($leg -and (Idiomas-Necesita-Migrar $instDir)) {
        $es = [pscustomobject]@{ codigo = 'ES'; nombre = 'Español'; nombreEs = 'español'; voz = 'es'; codificacion = 1252
                                 dir = $instDir; csv = $leg.csv; ficheros = $leg.ficheros; legado = $true }
        $l = @(@($es) + @($l | Where-Object { $_.codigo -ne 'ES' }))
    }
    return $l
}

function Idioma-Actual([string]$instDir, $lista) {
    $cod = $null
    $raiz = Idiomas-Raiz $instDir
    if ($raiz) {
        $p = Join-Path $raiz 'actual.txt'
        if (Test-Path -LiteralPath $p) { try { $cod = ([IO.File]::ReadAllText($p)).Trim().ToUpper() } catch { } }
    }
    $i = @($lista | Where-Object { $_.codigo -eq $cod }) | Select-Object -First 1
    if (-not $i) { $i = @($lista | Where-Object { $_.codigo -eq 'ES' }) | Select-Object -First 1 }
    if (-not $i) { $i = @($lista) | Select-Object -First 1 }
    return $i
}

function Idioma-Poner-Actual([string]$instDir, [string]$cod) {
    $raiz = Idiomas-Raiz $instDir
    if ($raiz) { try { [IO.File]::WriteAllText((Join-Path $raiz 'actual.txt'), $cod.ToUpper()) } catch { } }
}

# Formato antiguo -> Idiomas\ES. Mueve Ficheros y Archivos.csv (no copia: es un cambio de nombre).
# Devuelve la carpeta del idioma, o $null si no había nada que migrar.
# Si ya existe Idiomas\ES\Ficheros (paquete nuevo descomprimido encima), se juntan: lo que ya está en
# Idiomas\ES\Ficheros manda (es más nuevo) y lo antiguo que coincide se aparta en Ficheros_antiguo_<fecha>.
function Idiomas-Migrar([string]$instDir) {
    if (-not (Idiomas-Necesita-Migrar $instDir)) { return $null }
    $leg = Idiomas-Legado $instDir
    $raiz = Idiomas-Raiz $instDir
    $nuevaRaiz = -not $raiz
    if (-not $raiz) { $raiz = Join-Path (Split-Path $leg.ficheros -Parent) 'Idiomas' }   # donde estaba Ficheros
    $dir = Join-Path $raiz 'ES'
    $dirF = Join-Path $dir 'Ficheros'
    $habiaDir = Test-Path -LiteralPath $dir
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $apartados = $null
    try {
        if (-not (Test-Path -LiteralPath $leg.ficheros)) { New-Item -ItemType Directory -Path $dirF -Force | Out-Null }
        elseif (-not (Test-Path -LiteralPath $dirF)) { Move-Item -LiteralPath $leg.ficheros -Destination $dirF }
        else {
            $raizLeg = (Resolve-Path -LiteralPath $leg.ficheros).ProviderPath.TrimEnd('\') + '\'
            foreach ($f in @(Get-ChildItem -LiteralPath $leg.ficheros -Recurse -File -Force)) {
                $rel = $f.FullName.Substring($raizLeg.Length)
                $dst = Join-Path $dirF $rel
                if (Test-Path -LiteralPath $dst) { continue }
                New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
                Move-Item -LiteralPath $f.FullName -Destination $dst
            }
            if (@(Get-ChildItem -LiteralPath $leg.ficheros -Recurse -File -Force).Count -eq 0) { Remove-Item -LiteralPath $leg.ficheros -Recurse -Force }
            else {
                $apartados = $leg.ficheros + '_antiguo_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
                Rename-Item -LiteralPath $leg.ficheros -NewName (Split-Path $apartados -Leaf)
            }
        }
    } catch {
        if ($nuevaRaiz) { Remove-Item -LiteralPath $raiz -Recurse -Force -ErrorAction SilentlyContinue }
        elseif (-not $habiaDir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
        throw "No se pudo mover la carpeta Ficheros (¿hay algún fichero abierto?): $($_.Exception.Message)"
    }
    try { Move-Item -LiteralPath $leg.csv -Destination (Join-Path $dir 'Archivos.csv') }
    catch { throw "No se pudo mover Archivos.csv a $($dir): $($_.Exception.Message)" }
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'idioma.json'))) { Idioma-Guardar-Json $dir 'ES' 'Español' 'español' 'es' 1252 }
    if (-not (Test-Path -LiteralPath (Join-Path $raiz 'actual.txt'))) { [IO.File]::WriteAllText((Join-Path $raiz 'actual.txt'), 'ES') }
    return [pscustomobject]@{ dir = $dir; apartados = $apartados }
}

# Filas de un Archivos.csv: Teatro, Ficheros, Data (y la línea tal cual)
function Idioma-Filas([string]$csv) {
    $o = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $csv)) { return $o }
    foreach ($l in ([IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8) -split "`r?`n")) {
        $c = $l.TrimStart([char]0xFEFF).Split(';')
        if ($c.Count -ge 3 -and $c[0].Trim() -and $c[2].Trim() -and $c[0].Trim() -ne 'Teatro') {
            [void]$o.Add([pscustomobject]@{ Teatro = $c[0].Trim(); Ficheros = $c[1].Trim(); Data = $c[2].Trim(); linea = $l.TrimStart([char]0xFEFF) })
        }
    }
    return $o
}

# Textos [ADDTEXT] de un .irc (ANSI): id -> texto
function Idioma-Irc-Textos([string]$f) {
    $h = @{}
    $ansi = [Text.Encoding]::GetEncoding(1252)
    foreach ($l in ($ansi.GetString([IO.File]::ReadAllBytes($f)) -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s*\[ADDTEXT\]\s+(\S+)\s+"([^"]*)"')
        if ($m.Success -and -not $h.ContainsKey($m.Groups[1].Value.ToUpper())) { $h[$m.Groups[1].Value.ToUpper()] = @($m.Groups[1].Value, $m.Groups[2].Value) }
    }
    return $h
}

# Crea Idiomas\<cod> partiendo siempre del inglés: la lista de ficheros es la de todos los idiomas que ya
# hay (sin repetir) y cada fichero es su original en inglés (Data_ORIGINAL; si no está ahí, el del juego,
# salvo que sea una traducción instalada). En las líneas "base + cambios" (LckTxtRc) la base es el original
# del primer teatro y los cambios de cada teatro, lo que su original tiene distinto.
# Los Falcon.tlk (voces) no se copian: se generan desde el editor.
function Idioma-Crear([string]$instDir, [string]$cod, [string]$nombre, [string]$nombreEs, [string]$voz, [string]$dirOriginal, [string]$bms) {
    $cod = $cod.ToUpper()
    if ($cod -notmatch '^[A-Z]{2,3}(-[A-Z]{2})?$') { throw 'Código de idioma no válido (dos o tres letras, p. ej. PT).' }
    if ($cod -eq 'EN') { throw 'EN no puede ser un idioma de traducción: el inglés son los originales del juego (Data_ORIGINAL).' }
    $raiz = Idiomas-Raiz $instDir
    if (-not $raiz) { $raiz = Join-Path (Split-Path $instDir -Parent) 'Idiomas'; New-Item -ItemType Directory -Path $raiz -Force | Out-Null }
    $dir = Join-Path $raiz $cod
    if (Test-Path -LiteralPath $dir) { throw "Ya existe el idioma $cod." }
    $todos = @(Idiomas-Lista $instDir)
    $r = [ordered]@{ dir = $dir; ficheros = 0; sinOriginal = @(); traducidos = @() }
    # lo que hay instalado de cualquier traducción (para no tomarlo como original)
    $inst = @{}
    if ($bms) {
        foreach ($fr in @(Get-ChildItem -LiteralPath $bms -Filter 'Traduccion_*_instalado.txt' -File -ErrorAction SilentlyContinue)) {
            foreach ($l in [IO.File]::ReadAllLines($fr.FullName, [Text.Encoding]::UTF8)) {
                $i = $l.LastIndexOf('|'); if ($i -gt 0) { $inst[$l.Substring(0, $i).ToLower() + '|' + $l.Substring($i + 1)] = $true }
            }
        }
    }
    New-Item -ItemType Directory -Path (Join-Path $dir 'Ficheros') -Force | Out-Null
    try {
        $ansi = [Text.Encoding]::GetEncoding(1252)
        $lineas = New-Object System.Collections.ArrayList
        [void]$lineas.Add('Teatro;Ficheros;Data')
        $bases = @{}; $vistos = @{}
        foreach ($idi in $todos) {
            foreach ($f in (Idioma-Filas $idi.csv)) {
                $kf = ($f.Teatro + '|' + $f.Data).ToLower()
                if ($vistos.ContainsKey($kf)) { continue }
                $vistos[$kf] = $true
                if ($f.Data -match '(^|\\)Falcon\.tlk$') { continue }
                $rel = $f.Data; $juego = $null
                if ($rel -match '^\.\.[\\/]') { $rel = $rel.Substring(3); if ($bms) { $juego = Join-Path $bms $rel } }
                elseif ($bms) { $juego = Join-Path (Join-Path $bms 'Data') $rel }
                $orig = Join-Path $dirOriginal $rel
                if (-not (Test-Path -LiteralPath $orig -PathType Leaf)) {
                    $orig = $null
                    if ($juego -and (Test-Path -LiteralPath $juego -PathType Leaf)) {
                        $h = (Get-FileHash -LiteralPath $juego -Algorithm MD5).Hash
                        if ($inst.ContainsKey($rel.ToLower() + '|' + $h)) { $r.traducidos += $f.Data } else { $orig = $juego }
                    } else { $r.sinOriginal += $f.Data }
                }
                if (-not $orig) { continue }
                $partes = @($f.Ficheros -split '\s*\+\s*')
                $dstBase = Join-Path (Join-Path $dir 'Ficheros') $partes[0].Trim()
                if ($partes.Count -gt 1) {
                    # base común + cambios del teatro
                    if (-not $bases.ContainsKey($dstBase.ToLower())) {
                        New-Item -ItemType Directory -Path (Split-Path $dstBase -Parent) -Force | Out-Null
                        Copy-Item -LiteralPath $orig -Destination $dstBase -Force
                        $bases[$dstBase.ToLower()] = Idioma-Irc-Textos $orig
                        $r.ficheros++
                    }
                    $tb = $bases[$dstBase.ToLower()]
                    $cambios = New-Object System.Collections.ArrayList
                    foreach ($e in (Idioma-Irc-Textos $orig).Values) {
                        $k = $e[0].ToUpper()
                        if (-not $tb.ContainsKey($k) -or $tb[$k][1] -cne $e[1]) { [void]$cambios.Add('[ADDTEXT] ' + $e[0] + ' "' + $e[1] + '"') }
                    }
                    $dstCamb = Join-Path (Join-Path $dir 'Ficheros') $partes[1].Trim()
                    New-Item -ItemType Directory -Path (Split-Path $dstCamb -Parent) -Force | Out-Null
                    [IO.File]::WriteAllBytes($dstCamb, $ansi.GetBytes((($cambios -join "`r`n") + $(if ($cambios.Count) { "`r`n" } else { '' }))))
                    $r.ficheros++
                } else {
                    if (-not (Test-Path -LiteralPath $dstBase)) {
                        New-Item -ItemType Directory -Path (Split-Path $dstBase -Parent) -Force | Out-Null
                        Copy-Item -LiteralPath $orig -Destination $dstBase -Force
                        $r.ficheros++
                    }
                }
                [void]$lineas.Add($f.linea)
            }
        }
        [IO.File]::WriteAllText((Join-Path $dir 'Archivos.csv'), (($lineas -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
        Idioma-Guardar-Json $dir $cod $nombre $nombreEs $voz 1252
    } catch {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
    return $r
}
