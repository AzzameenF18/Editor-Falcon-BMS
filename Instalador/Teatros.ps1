# Teatros de Falcon BMS, comunes al instalador y al editor.
# Los conocidos (con su nombre en español) y, además, cualquier carpeta "Add-On <Nombre>" de Data que
# parezca un teatro (tiene TerrData, Campaign, Art o Sounds) y cualquier teatro que salga en Archivos.csv.
# Un teatro nuevo (p. ej. "Add-On Malvinas") tiene clave MALVINAS y nombre "Malvinas".

$TeatrosConocidos = @(
    [pscustomobject]@{ Clave = 'COREA';    Nombre = 'Corea';                  Corto = 'Corea';     Detalle = 'Falcon BMS 4.38';  Carpeta = '' }
    [pscustomobject]@{ Clave = 'TVT';      Nombre = 'Corea Equipo vs Equipo'; Corto = 'Corea TvT'; Detalle = 'Add-On Korea TvT'; Carpeta = 'Add-On Korea TvT' }
    [pscustomobject]@{ Clave = 'BALCANES'; Nombre = 'Balcanes';               Corto = 'Balcanes';  Detalle = 'Add-On Balkans';   Carpeta = 'Add-On Balkans' }
    [pscustomobject]@{ Clave = 'GRECIA';   Nombre = 'Grecia';                 Corto = 'Grecia';    Detalle = 'Add-On Hellas';    Carpeta = 'Add-On Hellas' }
    [pscustomobject]@{ Clave = 'ISRAEL';   Nombre = 'Israel';                 Corto = 'Israel';    Detalle = 'Add-On Israel';    Carpeta = 'Add-On Israel' }
)

# "Add-On Malvinas" -> MALVINAS ; "Add-On Desert Storm" -> DESERT_STORM
function Teatro-Clave-De-Carpeta([string]$carpeta) {
    $n = ($carpeta -replace '^Add-On\s+', '').Trim().ToUpperInvariant()
    $n = $n.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    return (($n -replace '[^A-Z0-9]+', '_').Trim('_'))
}
function Teatro-Nombre-De-Carpeta([string]$carpeta) { return ($carpeta -replace '^Add-On\s+', '').Trim() }
function Teatro-Parece([string]$dir) {
    foreach ($s in 'TerrData', 'Campaign', 'Art', 'Sounds') { if (Test-Path -LiteralPath (Join-Path $dir $s)) { return $true } }
    return $false
}

# Lista de teatros: los conocidos, los Add-On de Data y los de Archivos.csv.
# $csvs: rutas de Archivos.csv (de uno o varios idiomas) para sacar las claves y su carpeta (columna Data).
function Teatros-Detectar([string]$data, [string[]]$csvs) {
    $out = New-Object System.Collections.ArrayList
    foreach ($t in $TeatrosConocidos) { [void]$out.Add($t) }
    $ya = { param($c) @($out | Where-Object { $_.Carpeta -and $_.Carpeta -ieq $c }).Count -gt 0 }
    if ($data -and (Test-Path -LiteralPath $data)) {
        foreach ($d in (Get-ChildItem -LiteralPath $data -Directory -Filter 'Add-On *' -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if (& $ya $d.Name) { continue }
            if (-not (Teatro-Parece $d.FullName)) { continue }
            $n = Teatro-Nombre-De-Carpeta $d.Name; $c = Teatro-Clave-De-Carpeta $d.Name
            if (@($out | Where-Object { $_.Clave -eq $c }).Count) { $c = $c + '_2' }
            [void]$out.Add([pscustomobject]@{ Clave = $c; Nombre = $n; Corto = $n; Detalle = $d.Name; Carpeta = $d.Name })
        }
    }
    # teatros que solo están en Archivos.csv (p. ej., el Add-On aún no está instalado en este BMS)
    foreach ($csv in @($csvs)) {
        if (-not $csv -or -not (Test-Path -LiteralPath $csv)) { continue }
        foreach ($l in ([IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8) -split "`r?`n")) {
            $p = $l.TrimStart([char]0xFEFF).Split(';')
            if ($p.Count -lt 3) { continue }
            $c = $p[0].Trim().ToUpperInvariant(); $rel = $p[2].Trim()
            if (-not $c -or $c -eq 'TEATRO' -or @($out | Where-Object { $_.Clave -eq $c }).Count) { continue }
            $car = $(if ($rel -match '^(Add-On [^\\]+)\\') { $Matches[1] } else { $null })
            if ($car -and (& $ya $car)) { continue }
            $n = $(if ($car) { Teatro-Nombre-De-Carpeta $car } else { (Get-Culture).TextInfo.ToTitleCase($c.ToLower()) })
            [void]$out.Add([pscustomobject]@{ Clave = $c; Nombre = $n; Corto = $n; Detalle = $(if ($car) { $car } else { '?' }); Carpeta = $car })
        }
    }
    # sin coma: quien llama ya lo envuelve en @( ); con la coma, @( ) daba un solo elemento con toda la lista
    return $out.ToArray()
}
# Clave del teatro de una ruta dentro de Data ("Add-On Malvinas\Campaign\..." -> MALVINAS); Corea si no es de un Add-On
function Teatro-Clave-De-Ruta($teatros, [string]$rel) {
    $p = $rel.Split('\')[0]
    if ($p -notlike 'Add-On *') { return 'COREA' }
    $t = @($teatros | Where-Object { $_.Carpeta -and $_.Carpeta -ieq $p }) | Select-Object -First 1
    if ($t) { return $t.Clave }
    return (Teatro-Clave-De-Carpeta $p)
}
