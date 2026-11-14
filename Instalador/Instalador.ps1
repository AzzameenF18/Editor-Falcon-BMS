# Instalador de la traducción de Falcon BMS 4.38 (varios idiomas)
# Interfaz gráfica (WPF). Se lanza desde Instalar.bat, que está junto a la carpeta Instalador.
# Cada idioma está en Idiomas\<CÓDIGO>\ con su Archivos.csv (Teatro;Ficheros;Data), su carpeta
# Ficheros e idioma.json (ver Idiomas.ps1). Data_ORIGINAL (originales en inglés) es común.
# Con el formato antiguo (Archivos.csv y Ficheros sueltos junto al instalador) lo trata como el español.
# Al instalar un idioma, lo que hubiera instalado de otro en esos teatros se quita antes.
# La columna Data es relativa a Falcon BMS 4.38\Data. Si empieza por ..\ es relativa
# a la carpeta de Falcon BMS 4.38 (por ejemplo ..\Launcher\FalconBMS_Alternative_Launcher.exe);
# en ese caso el original se busca en Data_ORIGINAL sin el ..\ (Data_ORIGINAL\Launcher\...).
# Al instalar el español, si en Data_ORIGINAL falta la copia original de un fichero,
# se guarda antes la que hay en la instalación de Falcon BMS (así no hace falta
# distribuir Data_ORIGINAL con la traducción). No se guarda si el fichero del juego
# ya es igual a la traducción (porque entonces ya no es el original).
# En la columna Ficheros se puede poner "base + cambios" (por ejemplo
# "LckTxtRc.irc + LckTxtRc\Cambios_BALCANES.irc"): se instala la base con las
# líneas [ADDTEXT] del fichero de cambios aplicadas encima (las que no existen en
# la base se añaden al final). Así un texto editado en la base llega a todos los teatros.
# Además:
# - No copia los ficheros que ya están igual ("ya estaba").
# - Guarda en Falcon BMS\Traduccion_<CÓDIGO>_instalado.txt el MD5 de lo instalado; así, si un
#   fichero del juego no es ni el original guardado ni lo que instaló el instalador, es que
#   lo ha actualizado BMS: guarda el nuevo original (el anterior va a Data_ORIGINAL\_anteriores)
#   y avisa de que su traducción puede estar desfasada.
# - No instala ni restaura con Falcon BMS abierto.
# - Muestra el estado de cada teatro, tiene un botón «Comprobar» que revisa Archivos.csv
#   sin copiar nada, y deja el registro de la última operación en Registro.log.
# - La versión de la traducción se lee de version.txt (junto al instalador o en la carpeta de encima).
# - Si encuentra el Editor BMS (Editor_BMS\Editor_BMS.bat junto al instalador o una o dos carpetas
#   más arriba), muestra el botón «Abrir editor»; al volver, recalcula el estado.
# - «Comprobar» avisa de los ficheros del instalador idénticos al original (no hacen falta);
#   Revisar_redundantes.bat saca la lista completa para retirarlos.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# una sola instancia: si ya está abierto, se trae al frente y no se abre otro
$creado = $false
$Mutex = New-Object System.Threading.Mutex($true, 'Local\Instalador_Traduccion_BMS', [ref]$creado)
if (-not $creado) {
    $ok = $false
    try { Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.Interaction]::AppActivate('Traducción de Falcon BMS 4.38'); $ok = $true } catch { }
    if (-not $ok) { [void][System.Windows.MessageBox]::Show('El instalador ya está abierto.', 'Traducción de Falcon BMS', 'OK', 'Information') }
    exit 0
}
trap {
    [void][System.Windows.MessageBox]::Show("Error en el instalador:`n`n$($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)", 'Instalador', 'OK', 'Error')
    break
}

$Aqui = $PSScriptRoot
$ModIdiomas = Join-Path $Aqui 'Idiomas.ps1'
if (-not (Test-Path -LiteralPath $ModIdiomas)) {
    [void][System.Windows.MessageBox]::Show("Falta Idiomas.ps1 junto al instalador:`n$ModIdiomas", 'Instalador', 'OK', 'Error'); exit 1
}
. $ModIdiomas
$ModTeatros = Join-Path $Aqui 'Teatros.ps1'
if (-not (Test-Path -LiteralPath $ModTeatros)) {
    [void][System.Windows.MessageBox]::Show("Falta Teatros.ps1 junto al instalador:`n$ModTeatros", 'Instalador', 'OK', 'Error'); exit 1
}
. $ModTeatros
# Data_ORIGINAL puede estar dentro de la carpeta Instalador o junto a ella
function Buscar-Carpeta([string]$nombre) {
    $dentro = Join-Path $Aqui $nombre
    if (Test-Path $dentro) { return $dentro }
    return (Join-Path (Split-Path $Aqui -Parent) $nombre)
}
$DirOriginal = Buscar-Carpeta 'Data_ORIGINAL'
# idioma elegido (lo fija Poner-Idioma): su Archivos.csv y su carpeta Ficheros
$Csv = Join-Path $Aqui 'Archivos.csv'
$DirFicheros = Buscar-Carpeta 'Ficheros'
$script:Idiomas = @()
$script:Idi = $null
$script:Regs = @{}
$Ansi = [Text.Encoding]::GetEncoding(1252)
$script:Temporal = $null
$script:LogTexto = New-Object System.Collections.ArrayList
$script:EstadoTxt = @{}
$script:Detalle = @{}
$script:Instalado = @{}
$script:HayRegistro = $false
$Version = ''
foreach ($v in @((Join-Path $Aqui 'version.txt'), (Join-Path (Split-Path $Aqui -Parent) 'version.txt'))) {
    if (Test-Path -LiteralPath $v) { $Version = (@(Get-Content -LiteralPath $v -Encoding UTF8 -TotalCount 1) -join '').Trim(); break }
}

# Une un .irc base con un fichero de cambios (líneas [ADDTEXT] ID "texto") y lo deja en $salida.
# Devuelve cuántos textos se han sustituido y cuántos añadido.
function Combinar-Irc([string]$base, [string]$cambios, [string]$salida) {
    $txt = $Ansi.GetString([IO.File]::ReadAllBytes($base))
    if ($txt.Contains("`r`n")) { $nl = "`r`n" } else { $nl = "`n" }
    $nuevos = New-Object System.Collections.ArrayList
    $sust = 0
    foreach ($l in ($Ansi.GetString([IO.File]::ReadAllBytes($cambios)) -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s*\[ADDTEXT\]\s+(\S+)\s+"([^"]*)"\s*$')
        if (-not $m.Success) { continue }
        $id = $m.Groups[1].Value
        $val = $m.Groups[2].Value
        $re = New-Object Text.RegularExpressions.Regex ('(?im)^([ \t]*\[ADDTEXT\][ \t]+' + [regex]::Escape($id) + '[ \t]+")[^"\r\n]*(")')
        if ($re.IsMatch($txt)) {
            $txt = $re.Replace($txt, '${1}' + $val.Replace('$', '$$') + '${2}')
            $sust++
        } else {
            [void]$nuevos.Add('[ADDTEXT] ' + $id + ' "' + $val + '"')
        }
    }
    if ($nuevos.Count -gt 0) {
        if (-not $txt.EndsWith($nl)) { $txt += $nl }
        $txt += ($nuevos -join $nl) + $nl
    }
    [IO.File]::WriteAllBytes($salida, $Ansi.GetBytes($txt))
    return @($sust, $nuevos.Count)
}

# Teatros (Teatros.ps1): los conocidos, los Add-On que haya en Data y los de Archivos.csv; se recalculan en Detectar
$Teatros = @(Teatros-Detectar $null @())

[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Traducción de Falcon BMS 4.38"
        Width="1080" Height="640" MinWidth="680" MinHeight="560"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="Fondo"   Color="#14191F"/>
    <SolidColorBrush x:Key="Panel"   Color="#1C232B"/>
    <SolidColorBrush x:Key="Borde"   Color="#2C3640"/>
    <SolidColorBrush x:Key="Texto"   Color="#E6EBF0"/>
    <SolidColorBrush x:Key="Tenue"   Color="#8A96A3"/>
    <SolidColorBrush x:Key="Acento"  Color="#F2A900"/>
    <SolidColorBrush x:Key="Verde"   Color="#4CC38A"/>

    <Style x:Key="Boton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Texto}"/>
      <Setter Property="Background" Value="#26303A"/>
      <Setter Property="BorderBrush" Value="{StaticResource Borde}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primario" TargetType="Button" BasedOn="{StaticResource Boton}">
      <Setter Property="Background" Value="{StaticResource Acento}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Acento}"/>
      <Setter Property="Foreground" Value="#14191F"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style x:Key="Ventana" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Tenue}"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#2C3640"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Teatro" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Texto}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="card" Background="#1F2730" BorderBrush="{StaticResource Borde}" BorderThickness="1"
                    CornerRadius="8" Padding="12,10">
              <DockPanel LastChildFill="True">
                <Border x:Name="box" DockPanel.Dock="Left" Width="20" Height="20" CornerRadius="4"
                        BorderBrush="#4A5663" BorderThickness="2" Background="Transparent" Margin="0,0,12,0"
                        VerticalAlignment="Center">
                  <TextBlock x:Name="tick" Text="&#x2713;" FontSize="13" FontWeight="Bold" Foreground="#14191F"
                             HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
                </Border>
                <ContentPresenter VerticalAlignment="Center"/>
              </DockPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="#F2A900"/>
                <Setter TargetName="box" Property="BorderBrush" Value="#F2A900"/>
                <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
                <Setter TargetName="card" Property="BorderBrush" Value="#5A4A1A"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="card" Property="Background" Value="#242D37"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="card" Property="Opacity" Value="0.45"/>
                <Setter Property="Cursor" Value="Arrow"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border Background="{StaticResource Fondo}" BorderBrush="{StaticResource Borde}" BorderThickness="1" CornerRadius="10">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Barra de título -->
      <Grid x:Name="Titulo" Grid.Row="0" Background="Transparent" Height="40">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
          <Border Width="10" Height="10" CornerRadius="5" Background="{StaticResource Acento}" Margin="0,0,10,0"/>
          <TextBlock Text="FALCON BMS 4.38  ·  INSTALADOR" Foreground="{StaticResource Tenue}" FontSize="11"
                     FontWeight="SemiBold" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,6,0">
          <Button x:Name="BtnMin" Style="{StaticResource Ventana}" Content="&#x2014;" FontSize="12"/>
          <Button x:Name="BtnCerrarX" Style="{StaticResource Ventana}" Content="&#x2715;" FontSize="13"/>
        </StackPanel>
      </Grid>

      <!-- Cabecera (con el logo a la derecha si hay logo.png junto al instalador) -->
      <Grid Grid.Row="1" Margin="28,6,28,18">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Border x:Name="LogoCaja" Grid.Column="1" Background="Transparent" Margin="16,0,0,0"
              VerticalAlignment="Center" Visibility="Collapsed">
        <Image x:Name="Logo" Height="62" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
      </Border>
      <StackPanel Grid.Column="0">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="TxtTitulo" Text="Traducción" Foreground="{StaticResource Texto}" FontSize="28" FontWeight="Light"/>
          <TextBlock x:Name="TxtVersion" Foreground="{StaticResource Tenue}" FontSize="13" VerticalAlignment="Bottom" Margin="14,0,0,6"/>
          <Button x:Name="BtnIdioma" Style="{StaticResource Boton}" Padding="10,4" FontSize="12" Margin="16,0,0,4" VerticalAlignment="Bottom"
                  Content="Idioma" ToolTip="Idioma de la traducción que se instala (el editor usa el mismo)"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
          <Border CornerRadius="10" Background="#26303A" Padding="10,3" Margin="0,0,10,0">
            <TextBlock x:Name="TxtEstado" Text="Comprobando..." Foreground="{StaticResource Tenue}" FontSize="12"/>
          </Border>
          <TextBlock x:Name="TxtRuta" Foreground="{StaticResource Tenue}" FontSize="12" VerticalAlignment="Center"
                     TextTrimming="CharacterEllipsis" MaxWidth="440"/>
          <TextBlock Margin="10,0,0,0" VerticalAlignment="Center" FontSize="12">
            <Hyperlink x:Name="LnkRuta" Foreground="{StaticResource Acento}">Cambiar</Hyperlink>
          </TextBlock>
        </StackPanel>
      </StackPanel>
      </Grid>

      <!-- Cuerpo -->
      <Grid Grid.Row="2" Margin="28,0,28,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="280"/>
          <ColumnDefinition Width="20"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0">
          <TextBlock Text="TEATROS" Foreground="{StaticResource Tenue}" FontSize="11" FontWeight="SemiBold" Margin="2,0,0,10"/>
          <StackPanel x:Name="PanelTeatros"/>
        </StackPanel>

        <Border Grid.Column="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Borde}"
                BorderThickness="1" CornerRadius="8">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="REGISTRO" Foreground="{StaticResource Tenue}" FontSize="11"
                       FontWeight="SemiBold" Margin="14,12,14,6"/>
            <ScrollViewer x:Name="Scroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="14,0,6,0">
              <StackPanel x:Name="Log"/>
            </ScrollViewer>
            <StackPanel Grid.Row="2" Margin="14,8,14,12">
              <ProgressBar x:Name="Barra" Height="4" Minimum="0" Maximum="1" Value="0"
                           Background="#26303A" Foreground="{StaticResource Acento}" BorderThickness="0"/>
              <TextBlock x:Name="TxtResumen" Foreground="{StaticResource Tenue}" FontSize="12" Margin="0,8,0,0"
                         Text="Elige los teatros y pulsa Instalar."/>
            </StackPanel>
          </Grid>
        </Border>
      </Grid>

      <!-- Botonera -->
      <Grid Grid.Row="3" Margin="28,18,28,22">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
          <Button x:Name="BtnEsp" Style="{StaticResource Primario}" Content="Instalar español" Margin="0,0,10,0"/>
          <Button x:Name="BtnEng" Style="{StaticResource Boton}" Content="Restaurar inglés" Margin="0,0,10,0"/>
          <Button x:Name="BtnComprobar" Style="{StaticResource Boton}" Content="Comprobar" ToolTip="Revisa Archivos.csv y las carpetas sin copiar nada"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnEditor" Style="{StaticResource Boton}" Content="&#x270E;  Abrir editor" Margin="0,0,10,0" Visibility="Collapsed"
                  ToolTip="Editor BMS (SCF, RSC, campañas y voces): lo que guardes va a este instalador"/>
          <Button x:Name="BtnJugar" Style="{StaticResource Boton}" Content="&#x25B6;  Abrir Falcon BMS" Margin="0,0,10,0"/>
          <Button x:Name="BtnSalir" Style="{StaticResource Boton}" Content="Salir"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $Xaml))
function Ctl($n) { $Win.FindName($n) }
$PanelTeatros = Ctl 'PanelTeatros'; $Log = Ctl 'Log'; $Scroll = Ctl 'Scroll'; $Barra = Ctl 'Barra'
$TxtResumen = Ctl 'TxtResumen'; $TxtRuta = Ctl 'TxtRuta'; $TxtEstado = Ctl 'TxtEstado'
# logo (opcional): logo.png (o .jpg/.bmp/.webp) junto al instalador o en la carpeta de encima
foreach ($n in 'logo.png', 'logo.jpg', 'logo.bmp', 'logo.webp') {
    $f = @((Join-Path $Aqui $n), (Join-Path (Split-Path $Aqui -Parent) $n)) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $f) { continue }
    try {
        $bmp = New-Object Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'; $bmp.UriSource = New-Object Uri($f); $bmp.EndInit(); $bmp.Freeze()
        (Ctl 'Logo').Source = $bmp; (Ctl 'LogoCaja').Visibility = 'Visible'; break
    } catch { }   # p. ej. .webp sin el códec de Windows: se prueba el siguiente
}
$BtnEsp = Ctl 'BtnEsp'; $BtnEng = Ctl 'BtnEng'; $BtnJugar = Ctl 'BtnJugar'; $BtnSalir = Ctl 'BtnSalir'; $BtnEditor = Ctl 'BtnEditor'
# Editor BMS: junto al instalador, en la carpeta de al lado o un nivel más arriba
$Editor = $null
foreach ($c in @((Join-Path $Aqui 'Editor_BMS\Editor_BMS.bat'), (Join-Path (Split-Path $Aqui -Parent) 'Editor_BMS\Editor_BMS.bat'),
                 (Join-Path (Split-Path (Split-Path $Aqui -Parent) -Parent) 'Editor_BMS\Editor_BMS.bat'))) {
    if (Test-Path -LiteralPath $c -PathType Leaf) { $Editor = $c; break }
}
if ($Editor) { $BtnEditor.Visibility = 'Visible'; $BtnEditor.ToolTip = $BtnEditor.ToolTip + "`n" + (Split-Path $Editor -Parent) }
$BtnComprobar = Ctl 'BtnComprobar'; $TxtVersion = Ctl 'TxtVersion'; $TxtTitulo = Ctl 'TxtTitulo'; $BtnIdioma = Ctl 'BtnIdioma'
if ($Version) { $TxtVersion.Text = $Version }

$Brush = @{
    Texto = [Windows.Media.BrushConverter]::new().ConvertFrom('#E6EBF0')
    Tenue = [Windows.Media.BrushConverter]::new().ConvertFrom('#8A96A3')
    Verde = [Windows.Media.BrushConverter]::new().ConvertFrom('#4CC38A')
    Amar  = [Windows.Media.BrushConverter]::new().ConvertFrom('#E8C15A')
    Rojo  = [Windows.Media.BrushConverter]::new().ConvertFrom('#F06A6A')
    Acento= [Windows.Media.BrushConverter]::new().ConvertFrom('#F2A900')
}

# ---------- utilidades ----------
function Refrescar {
    # deja que la ventana se repinte durante operaciones largas
    $Win.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
}

function Escribir([string]$texto, [string]$color = 'Texto', [switch]$Titulo) {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $texto
    $tb.Foreground = $Brush[$color]
    $tb.FontFamily = New-Object Windows.Media.FontFamily('Consolas, Segoe UI')
    $tb.FontSize = 12
    $tb.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
    if ($Titulo) { $tb.FontWeight = [Windows.FontWeights]::SemiBold; $tb.Margin = New-Object Windows.Thickness(0, 8, 0, 2); $tb.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI') }
    [void]$Log.Children.Add($tb)
    if ($Titulo) { [void]$script:LogTexto.Add('') ; [void]$script:LogTexto.Add('== ' + $texto + ' ==') } else { [void]$script:LogTexto.Add($texto) }
    $Scroll.ScrollToEnd()
    Refrescar
}

function Buscar-BMS {
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Benchmark Sims\Falcon BMS 4.38',
                   'HKLM:\SOFTWARE\Benchmark Sims\Falcon BMS 4.38') {
        try {
            $v = (Get-ItemProperty -Path $k -Name baseDir -ErrorAction Stop).baseDir
            if ($v -and (Test-Path (Join-Path $v 'Data'))) { return $v.TrimEnd('\') }
        } catch { }
    }
    return $null
}

function Elegir-Ruta {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Selecciona la carpeta de instalación de Falcon BMS 4.38 (la que contiene Data)'
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq 'OK') {
        $r = $dlg.SelectedPath.TrimEnd('\')
        if (Test-Path (Join-Path $r 'Data')) { return $r }
        if ((Split-Path $r -Leaf) -eq 'Data') { return (Split-Path $r -Parent) }
        [void][Windows.MessageBox]::Show('En esa carpeta no hay una carpeta Data de Falcon BMS.', 'Ruta no válida', 'OK', 'Warning')
    }
    return $null
}

function Leer-Lista([string]$csv) {
    if (-not $csv) { $csv = $script:Csv }
    if (-not $csv -or -not (Test-Path -LiteralPath $csv)) { return @() }
    return @(Import-Csv -LiteralPath $csv -Delimiter ';' -Encoding UTF8 | Where-Object { $_.Teatro -and $_.Data })
}

# ---------- idiomas ----------
function Cod-Idioma { if ($script:Idi) { return $script:Idi.codigo } else { return 'ES' } }
function Nombre-Idioma([string]$cod) {
    if (-not $cod) { if ($script:Idi) { return $script:Idi.nombre } else { return '' } }
    $i = @($script:Idiomas | Where-Object { $_.codigo -eq $cod }) | Select-Object -First 1
    if ($i) { return $i.nombre } else { return $cod }
}
function Cargar-Idiomas { $script:Idiomas = @(Idiomas-Lista $Aqui) }
function Poner-Idioma($i) {
    $script:Idi = $i
    if ($i) { $script:Csv = $i.csv; $script:DirFicheros = $i.ficheros }
    if ($i) {
        $n = Nombre-Idioma
        $TxtTitulo.Text = 'Traducción: ' + $n
        $BtnEsp.Content = 'Instalar ' + $n
        $BtnIdioma.Content = 'Idioma: ' + $i.nombre + '   ' + [char]0x25BE
    } else {
        # sin ningún idioma (instalación limpia del paquete): no hay nada que instalar
        $TxtTitulo.Text = 'Traducción de Falcon BMS'
        $BtnEsp.Content = 'Instalar traducción'
        $BtnIdioma.Content = 'Idioma: ninguno   ' + [char]0x25BE
    }
    Botones-Idioma
    if ($i -and -not $i.legado) { Idioma-Poner-Actual $Aqui $i.codigo }
}
# sin idioma elegido no se puede instalar ni comprobar (Restaurar inglés sí: usa la lista de todos los idiomas)
function Botones-Idioma {
    $hay = [bool]$script:Idi
    $BtnEsp.IsEnabled = $hay -and $BtnSalir.IsEnabled
    $BtnComprobar.IsEnabled = $hay -and $BtnSalir.IsEnabled
    $BtnEng.IsEnabled = ($script:Idiomas.Count -gt 0) -and $BtnSalir.IsEnabled
}
function Menu-Idiomas {
    $m = New-Object Windows.Controls.ContextMenu
    foreach ($i in $script:Idiomas) {
        $it = New-Object Windows.Controls.MenuItem
        $it.Header = $i.nombre + '   (' + $i.codigo + ')'
        $it.IsChecked = [bool]($script:Idi -and $i.codigo -eq $script:Idi.codigo)
        $it.Tag = $i.codigo
        $it.Add_Click({
            param($s)
            $x = @($script:Idiomas | Where-Object { $_.codigo -eq $s.Tag }) | Select-Object -First 1
            if ($x) { Poner-Idioma $x; Estado-Actual }
        })
        [void]$m.Items.Add($it)
    }
    if ($script:Idiomas.Count) { [void]$m.Items.Add((New-Object Windows.Controls.Separator)) }
    $n = New-Object Windows.Controls.MenuItem
    $n.Header = $(if ($Editor) { 'Los idiomas nuevos se crean en el editor (Abrir editor)' } else { 'Los idiomas nuevos se crean con el editor' })
    $n.IsEnabled = $false
    [void]$m.Items.Add($n)
    $m.PlacementTarget = $BtnIdioma
    $m.Placement = [Windows.Controls.Primitives.PlacementMode]::Bottom
    $m.IsOpen = $true
}

$script:BMS = $null
$script:Cajas = @{}

function Detectar {
    $data = Join-Path $script:BMS 'Data'
    $script:Teatros = @(Teatros-Detectar $data @($script:Idiomas | ForEach-Object { $_.csv }))
    $TxtRuta.Text = $script:BMS
    $PanelTeatros.Children.Clear()
    $script:Cajas = @{}
    foreach ($t in $Teatros) {
        $ok = ($t.Carpeta -eq '') -or ($t.Carpeta -and (Test-Path -LiteralPath (Join-Path $data $t.Carpeta)))
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Style = $Win.FindResource('Teatro')
        $sp = New-Object Windows.Controls.StackPanel
        $n = New-Object Windows.Controls.TextBlock; $n.Text = $t.Nombre; $n.FontSize = 14; $n.Foreground = $Brush.Texto
        $d = New-Object Windows.Controls.TextBlock; $d.FontSize = 11; $d.Foreground = $Brush.Tenue
        if ($ok) { $d.Text = $t.Detalle } else { $d.Text = $t.Detalle + '  ·  no instalado' }
        $e = New-Object Windows.Controls.TextBlock; $e.FontSize = 11; $e.Foreground = $Brush.Tenue; $e.Margin = New-Object Windows.Thickness(0, 2, 0, 0)
        if ($ok) { $e.Text = '●  comprobando…' }
        [void]$sp.Children.Add($n); [void]$sp.Children.Add($d); [void]$sp.Children.Add($e)
        $script:EstadoTxt[$t.Clave] = $e
        $script:Instalado[$t.Clave] = $ok
        $cb.Content = $sp
        $cb.IsEnabled = $ok
        $cb.IsChecked = $ok
        [void]$PanelTeatros.Children.Add($cb)
        $script:Cajas[$t.Clave] = $cb
    }
    if ($Win.IsLoaded) { Estado-Actual }   # al arrancar se calcula al mostrarse la ventana
}

# ---------- comparación de ficheros (MD5 con caché) ----------
$script:Hashes = @{}
function Md5([string]$p) {
    $i = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if (-not $i -or $i.PSIsContainer) { return $null }
    $k = $i.FullName + '|' + $i.Length + '|' + $i.LastWriteTimeUtc.Ticks
    if (-not $script:Hashes.ContainsKey($k)) { $script:Hashes[$k] = (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash }
    return $script:Hashes[$k]
}
function Mismo-Fichero($a, $b) {
    if (-not $a -or -not $b) { return $false }
    if (-not (Test-Path -LiteralPath $a -PathType Leaf) -or -not (Test-Path -LiteralPath $b -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $a).Length -ne (Get-Item -LiteralPath $b).Length) { return $false }
    return (Md5 $a) -eq (Md5 $b)
}

# ---------- carpeta temporal (ficheros "base + cambios") ----------
function Temporal {
    if (-not $script:Temporal -or -not (Test-Path -LiteralPath $script:Temporal)) {
        $script:Temporal = Join-Path ([IO.Path]::GetTempPath()) ('TraduccionBMS_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Temporal -Force | Out-Null
    }
    return $script:Temporal
}
function Borrar-Temporal {
    if ($script:Temporal -and (Test-Path -LiteralPath $script:Temporal)) {
        Remove-Item -LiteralPath $script:Temporal -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:Temporal = $null
}

# ---------- rutas de una línea de Archivos.csv ----------
# dst = fichero del juego; orig = su copia en Data_ORIGINAL
function Destino($f) {
    if ($f.Data -match '^\.\.[\\/]') { $rel = $f.Data.Substring(3); $dst = Join-Path $script:BMS $rel }
    else { $rel = $f.Data; $dst = Join-Path (Join-Path $script:BMS 'Data') $rel }
    return [pscustomobject]@{ rel = $rel; dst = $dst; orig = (Join-Path $DirOriginal $rel) }
}
# Fichero traducido a instalar (si es "base + cambios", se monta en la carpeta temporal).
# falta = parte que no existe en Ficheros
function Fuente-Esp($f, [string]$clave, [string]$rel) {
    $partes = @($f.Ficheros -split '\s*\+\s*')
    $r = [pscustomobject]@{ src = (Join-Path $DirFicheros $partes[0].Trim()); nota = ''; falta = $null }
    if (-not (Test-Path -LiteralPath $r.src -PathType Leaf)) { $r.falta = $partes[0].Trim(); return $r }
    if ($partes.Count -gt 1) {
        $cambios = Join-Path $DirFicheros $partes[1].Trim()
        if (-not (Test-Path -LiteralPath $cambios -PathType Leaf)) { $r.falta = $partes[1].Trim(); return $r }
        $comb = Join-Path (Temporal) ($clave + '_' + ($rel -replace '[\\/:]', '_'))
        $c = Combinar-Irc $r.src $cambios $comb
        $r.src = $comb
        $r.nota = "   (+ $($partes[1].Trim()): $($c[0]) cambiados"
        if ($c[1] -gt 0) { $r.nota += ", $($c[1]) añadidos" }
        $r.nota += ')'
    }
    return $r
}

# ---------- registro de lo instalado (en la carpeta de Falcon BMS) ----------
# Guarda el MD5 de cada fichero que instala el instalador. Sirve para distinguir
# "versión anterior de la traducción" de "fichero actualizado por BMS".
# Un registro por idioma: Traduccion_<CÓDIGO>_instalado.txt (el del español sigue llamándose igual que antes).
function Ruta-Registro([string]$cod) { if (-not $cod) { $cod = Cod-Idioma }; return (Join-Path $script:BMS ('Traduccion_' + $cod + '_instalado.txt')) }
function Leer-Registro([string]$cod) {
    $h = @{}
    $p = Ruta-Registro $cod
    if (Test-Path -LiteralPath $p) {
        foreach ($l in [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)) {
            $i = $l.LastIndexOf('|'); if ($i -gt 0) { $h[$l.Substring(0, $i).ToLower()] = $l.Substring($i + 1) }
        }
    }
    return $h
}
# Registros de todos los idiomas (también de códigos que ya no están en Idiomas, si dejaron registro)
function Leer-Registros {
    $r = @{}
    $script:HayRegistro = $false
    $cods = @($script:Idiomas | ForEach-Object { $_.codigo })
    foreach ($f in @(Get-ChildItem -LiteralPath $script:BMS -Filter 'Traduccion_*_instalado.txt' -File -ErrorAction SilentlyContinue)) {
        $script:HayRegistro = $true
        $m = [regex]::Match($f.Name, '^Traduccion_(.+)_instalado\.txt$')
        if ($m.Success -and $cods -notcontains $m.Groups[1].Value.ToUpper()) { $cods += $m.Groups[1].Value.ToUpper() }
    }
    if ($cods -notcontains (Cod-Idioma)) { $cods += Cod-Idioma }
    foreach ($c in $cods) { $r[$c] = Leer-Registro $c }
    return $r
}
function Guardar-Registro([string]$cod, $h) {
    $p = Ruta-Registro $cod
    # no se crean registros vacíos de idiomas que no se han instalado nunca
    if ($h.Count -eq 0 -and -not (Test-Path -LiteralPath $p)) { return }
    $lineas = @($h.Keys | Sort-Object | ForEach-Object { $_ + '|' + $h[$_] })
    try { [IO.File]::WriteAllLines($p, [string[]]$lineas, (New-Object Text.UTF8Encoding($true))) } catch { }
}
# Idioma (distinto del elegido) cuya traducción es el fichero del juego, según los registros
function Idioma-De-Fichero([string]$k, [string]$hash) {
    foreach ($c in $script:Regs.Keys) {
        if ($c -ne (Cod-Idioma) -and $script:Regs[$c].ContainsKey($k) -and $script:Regs[$c][$k] -eq $hash) { return $c }
    }
    return $null
}

# ---------- Falcon BMS en marcha ----------
function Procesos-BMS {
    $raiz = $script:BMS.TrimEnd('\') + '\'
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $ruta = $null; try { $ruta = $_.Path } catch { }
        $ruta -and $ruta.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)
    })
}
function Esperar-Cierre {
    while ($true) {
        $p = Procesos-BMS
        if ($p.Count -eq 0) { return $true }
        $nombres = (@($p | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)) -join ', '
        $r = [Windows.MessageBox]::Show("Falcon BMS está abierto ($nombres).`n`nCiérralo y pulsa Aceptar para continuar, o Cancelar para no hacer nada.", 'Falcon BMS en marcha', 'OKCancel', 'Warning')
        if ($r -ne 'OK') { return $false }
    }
}

# ---------- estado de cada teatro ----------
function Estado-Teatro([string]$clave) {
    # n = ficheros del teatro que hay en el juego; igual = los que son idénticos en inglés y en español
    # (no cuentan para decidir el idioma); es / en / otro = el resto
    # desc = iguales a la traducción pero sin original con que comparar (no se sabe si cambian)
    # otrosIdi = ficheros que son la traducción de otro idioma instalado (código -> cuántos)
    $e = [pscustomobject]@{ n = 0; igual = 0; desc = 0; es = 0; en = 0; otro = 0; lEs = (New-Object System.Collections.ArrayList); lOtro = (New-Object System.Collections.ArrayList); lDesc = (New-Object System.Collections.ArrayList); lIgual = (New-Object System.Collections.ArrayList)
                            otrosIdi = @{}; lOtroIdi = (New-Object System.Collections.ArrayList) }
    foreach ($f in @($script:Lista | Where-Object { $_.Teatro -eq $clave })) {
        $d = Destino $f
        if (-not (Test-Path -LiteralPath $d.dst -PathType Leaf)) { continue }
        $e.n++
        $hayOrig = Test-Path -LiteralPath $d.orig
        $fu = Fuente-Esp $f $clave $d.rel
        $trad = $null; if (-not $fu.falta) { $trad = $fu.src }
        # la traducción es idéntica al original: el fichero es igual en los dos idiomas
        if ($hayOrig -and $trad -and (Mismo-Fichero $trad $d.orig)) { $e.igual++; [void]$e.lIgual.Add($d.rel); continue }
        if ($hayOrig -and (Mismo-Fichero $d.orig $d.dst)) { $e.en++ }
        elseif ($trad -and (Mismo-Fichero $trad $d.dst)) {
            if ($hayOrig) { $e.es++; [void]$e.lEs.Add($d.rel) }
            else { $e.desc++; [void]$e.lDesc.Add($d.rel) }
        }
        else {
            $cx = Idioma-De-Fichero $d.rel.ToLower() (Md5 $d.dst)
            if ($cx) { $e.otrosIdi[$cx] = 1 + [int]$e.otrosIdi[$cx]; [void]$e.lOtroIdi.Add($d.rel + '   (' + $cx + ')') }
            elseif (-not $hayOrig) { $e.en++ }
            else { $e.otro++; [void]$e.lOtro.Add($d.rel) }
        }
    }
    return $e
}
function Estado-Actual {
    $TxtEstado.Text = '●  Comprobando…'; $TxtEstado.Foreground = $Brush.Tenue
    Refrescar
    if (-not $script:Idi) {
        foreach ($x in $script:EstadoTxt.Values) { if ($x) { $x.Text = ''; $x.ToolTip = $null } }
        $TxtEstado.Text = '●  Sin ninguna traducción'; $TxtEstado.Foreground = $Brush.Tenue
        $TxtResumen.Text = 'No hay ningún idioma de la traducción. Créalo con el editor (Traducción → ＋ Nuevo idioma…) o copia su carpeta en Idiomas.'
        return
    }
    $script:Lista = Leer-Lista
    $script:Regs = Leer-Registros
    $nom = Nombre-Idioma
    $resumen = @{ es = @(); en = @(); mezcla = @(); otro = @{} }
    foreach ($t in $Teatros) {
        $txt = $script:EstadoTxt[$t.Clave]
        if (-not $txt -or -not $script:Instalado[$t.Clave]) { continue }
        $e = Estado-Teatro $t.Clave
        $script:Detalle[$t.Clave] = $e
        $txt.ToolTip = $null
        if ($e.lEs.Count -or $e.lOtro.Count -or $e.lDesc.Count -or $e.lOtroIdi.Count) {
            $tip = @()
            if ($e.lEs.Count) { $tip += "En $($nom):"; $tip += @($e.lEs | ForEach-Object { '   ' + $_ }) }
            if ($e.lOtroIdi.Count) { $tip += 'En otro idioma de la traducción:'; $tip += @($e.lOtroIdi | ForEach-Object { '   ' + $_ }) }
            if ($e.lOtro.Count) { $tip += 'Distintos del original y de la traducción:'; $tip += @($e.lOtro | ForEach-Object { '   ' + $_ }) }
            if ($e.lDesc.Count) { $tip += 'Iguales a la traducción, sin original para comparar (se guardará al instalar):'; $tip += @($e.lDesc | ForEach-Object { '   ' + $_ }) }
            $txt.ToolTip = ($tip -join "`n")
        }
        if ($e.n -eq 0) { $txt.Text = ''; continue }
        $cuenta = $e.n - $e.igual - $e.desc          # los que se sabe que cambian entre inglés y español
        $extra = $(if ($e.desc) { " · $($e.desc) sin original para comparar" } else { '' })
        if ($cuenta -le 0) {
            if ($e.desc) { $txt.Text = '●  igual a la traducción' + $extra; $txt.Foreground = $Brush.Amar; $resumen.mezcla += $t.Nombre }
            else { $txt.Text = '●  sin diferencias'; $txt.Foreground = $Brush.Tenue }
            continue
        }
        $nOtros = 0; foreach ($v in $e.otrosIdi.Values) { $nOtros += $v }
        if ($e.es -eq $cuenta) { $txt.Text = '●  ' + $nom + $extra; $txt.Foreground = $Brush.Verde; $resumen.es += $t.Nombre }
        elseif ($e.es -eq 0 -and $e.otro -eq 0 -and $nOtros -eq 0) { $txt.Text = '●  inglés' + $extra; $txt.Foreground = $Brush.Tenue; $resumen.en += $t.Nombre }
        elseif ($e.es -eq 0 -and $e.otro -eq 0 -and $e.otrosIdi.Count -eq 1 -and $e.en -eq 0) {
            $cx = @($e.otrosIdi.Keys)[0]
            $txt.Text = '●  ' + (Nombre-Idioma $cx) + ' (otro idioma)' + $extra; $txt.Foreground = $Brush.Amar; $resumen.otro[$cx] = $true
        }
        else {
            $txt.Text = "●  mezcla: $($e.es) de $cuenta en $nom" + $(if ($nOtros) { " · $nOtros en otro idioma" } else { '' }) + $(if ($e.otro) { " · $($e.otro) distintos" } else { '' })
            $txt.Foreground = $Brush.Amar; $resumen.mezcla += $t.Nombre
        }
        Refrescar
    }
    $nOt = $resumen.otro.Count
    if ($resumen.mezcla.Count -eq 0 -and $resumen.en.Count -eq 0 -and $nOt -eq 0 -and $resumen.es.Count) { $TxtEstado.Text = '●  Instalado: ' + $nom; $TxtEstado.Foreground = $Brush.Verde }
    elseif ($resumen.mezcla.Count -eq 0 -and $resumen.es.Count -eq 0 -and $nOt -eq 0 -and $resumen.en.Count) { $TxtEstado.Text = '●  Instalado: inglés'; $TxtEstado.Foreground = $Brush.Tenue }
    elseif ($resumen.mezcla.Count -eq 0 -and $resumen.es.Count -eq 0 -and $resumen.en.Count -eq 0 -and $nOt -eq 1) { $TxtEstado.Text = '●  Instalado: ' + (Nombre-Idioma @($resumen.otro.Keys)[0]) + ' (no es el idioma elegido)'; $TxtEstado.Foreground = $Brush.Amar }
    elseif ($resumen.es.Count -or $resumen.en.Count -or $resumen.mezcla.Count -or $nOt) { $TxtEstado.Text = '●  Instalación mixta (mira cada teatro)'; $TxtEstado.Foreground = $Brush.Amar }
    else { $TxtEstado.Text = '●  Estado desconocido'; $TxtEstado.Foreground = $Brush.Amar }
    Borrar-Temporal
}

# Escribe en el registro qué ficheros de cada teatro no están en inglés
function Listar-Estado($elegidos) {
    $hay = $false
    foreach ($t in $elegidos) {
        $e = $script:Detalle[$t.Clave]
        if (-not $e -or ($e.lEs.Count -eq 0 -and $e.lOtro.Count -eq 0 -and $e.lDesc.Count -eq 0 -and $e.lOtroIdi.Count -eq 0)) { continue }
        $cod = Cod-Idioma
        if (-not $hay) { Escribir ''; Escribir "Ficheros que no están en inglés ($cod / otro idioma / ≠) o que no se pueden comprobar (?):" 'Acento'; $hay = $true }
        Escribir ('  ' + $t.Nombre) 'Texto'
        foreach ($x in $e.lEs) { Escribir ('    ' + $cod.PadRight(3) + ' ' + $x) 'Amar' }
        foreach ($x in $e.lOtroIdi) { Escribir ('    ··  ' + $x) 'Amar' }
        foreach ($x in $e.lOtro) { Escribir ('    ≠   ' + $x + '   (ni original ni traducción)') 'Amar' }
        foreach ($x in $e.lDesc) { Escribir ('    ?   ' + $x + '   (igual a la traducción; sin original para comparar)') 'Tenue' }
    }
    return $hay
}

function Bloquear([bool]$si) {
    foreach ($b in $BtnEsp, $BtnEng, $BtnComprobar, $BtnJugar, $BtnSalir, $BtnEditor, $BtnIdioma) { $b.IsEnabled = -not $si }
    foreach ($c in $script:Cajas.Values) { if ($si) { $c.Tag = $c.IsEnabled; $c.IsEnabled = $false } else { $c.IsEnabled = [bool]$c.Tag } }
    if (-not $si) { Botones-Idioma }
}

function Guardar-Log([string]$titulo) {
    try {
        $p = Join-Path $Aqui 'Registro.log'
        $cab = @("$titulo  ·  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "Falcon BMS: $script:BMS", "Traducción: $Version  ·  idioma $(Cod-Idioma) ($Csv)", '')
        [IO.File]::WriteAllLines($p, [string[]]($cab + $script:LogTexto), (New-Object Text.UTF8Encoding($true)))
    } catch { }
}

function Teatros-Elegidos {
    return @($Teatros | Where-Object { $script:Cajas[$_.Clave].IsChecked -and $script:Cajas[$_.Clave].IsEnabled })
}

# ---------- Comprobar (no copia nada) ----------
function Comprobar {
    $lista = Leer-Lista
    if ($lista.Count -eq 0) { [void][Windows.MessageBox]::Show("No se encuentra Archivos.csv o está vacío.`n$Csv", 'Falta la lista', 'OK', 'Error'); return }
    $elegidos = Teatros-Elegidos
    if ($elegidos.Count -eq 0) { [void][Windows.MessageBox]::Show('Marca al menos un teatro.', 'Nada que hacer', 'OK', 'Information'); return }
    Bloquear $true
    $Log.Children.Clear(); $script:LogTexto = New-Object System.Collections.ArrayList
    $TxtResumen.Text = 'Comprobando...'; $TxtResumen.Foreground = $Brush.Tenue
    $falta = 0; $carp = 0; $dup = 0; $sinOrig = 0; $nuevos = 0
    # líneas repetidas (mismo destino dos veces)
    $vistos = @{}
    foreach ($f in $lista) { $k = $f.Data.ToLower(); if ($vistos.ContainsKey($k)) { $vistos[$k]++ } else { $vistos[$k] = 1 } }
    foreach ($t in $elegidos) {
        Escribir $t.Nombre 'Acento' -Titulo
        $avisos = 0
        foreach ($f in @($lista | Where-Object { $_.Teatro -eq $t.Clave })) {
            $d = Destino $f
            $fu = Fuente-Esp $f $t.Clave $d.rel
            if ($fu.falta) { Escribir ('  ✗  ' + $d.rel + '   falta en Ficheros: ' + $fu.falta) 'Rojo'; $falta++; $avisos++ }
            if ($vistos[$d.rel.ToLower()] -gt 1) { Escribir ('  !  ' + $d.rel + '   aparece ' + $vistos[$d.rel.ToLower()] + ' veces en Archivos.csv') 'Amar'; $dup++; $avisos++ }
            $dir = Split-Path $d.dst -Parent
            if (-not (Test-Path -LiteralPath $dir)) { Escribir ('  !  ' + $d.rel + '   la carpeta no existe en el juego (¿ruta correcta?)') 'Amar'; $carp++; $avisos++ }
            elseif (-not (Test-Path -LiteralPath $d.dst -PathType Leaf)) { $nuevos++ }
            elseif (-not (Test-Path -LiteralPath $d.orig)) { $sinOrig++ }
            $Barra.Value = 0
        }
        if ($avisos -eq 0) { Escribir '  ✓  sin problemas' 'Verde' }
    }
    Borrar-Temporal
    Escribir ''
    if ($nuevos) { Escribir ("$nuevos ficheros no existen aún en el juego: se crearán al instalar (y «Restaurar inglés» no podrá quitarlos).") 'Tenue' }
    if ($sinOrig) { Escribir ("$sinOrig ficheros aún no tienen copia en Data_ORIGINAL: se guardará al instalar (es lo normal la primera vez).") 'Tenue' }
    Estado-Actual
    [void](Listar-Estado $elegidos)
    # ficheros del instalador idénticos al original: no hacen falta (y confunden la detección del idioma)
    $red = @(foreach ($t in $elegidos) { $e = $script:Detalle[$t.Clave]; if ($e) { $e.lIgual } })
    if ($red.Count) {
        Escribir ''
        Escribir ("$($red.Count) ficheros del instalador son idénticos al original en inglés: no hacen falta.") 'Amar'
        foreach ($x in $red) { Escribir ('    =   ' + $x) 'Tenue' }
        Escribir ('Revisar_redundantes.bat saca la lista completa con sus líneas de Archivos.csv para retirarlos.') 'Tenue'
    }
    $TxtResumen.Text = "Faltan en Ficheros: $falta    ·    Carpetas que no existen: $carp    ·    Repetidos: $dup"
    if ($falta -or $carp -or $dup) { $TxtResumen.Foreground = $Brush.Amar } else { $TxtResumen.Foreground = $Brush.Verde; $TxtResumen.Text = 'Todo correcto: ' + $TxtResumen.Text }
    Guardar-Log 'Comprobar'
    Bloquear $false
}

function Instalar([string]$modo) {
    $lista = Leer-Lista
    if ($modo -eq 'ENG') {
        # restaurar el inglés: todo lo que cualquier idioma pueda haber instalado (Data_ORIGINAL es común)
        $vistos = @{}
        $lista = @(foreach ($i in $script:Idiomas) { foreach ($f in (Leer-Lista $i.csv)) {
            $k = $f.Teatro + '|' + $f.Data.ToLower(); if (-not $vistos.ContainsKey($k)) { $vistos[$k] = $true; $f } } })
    }
    if ($lista.Count -eq 0) {
        [void][Windows.MessageBox]::Show("No se encuentra Archivos.csv o está vacío.`n$Csv", 'Falta la lista', 'OK', 'Error'); return
    }
    if ($modo -eq 'ESP' -and -not (Test-Path $DirFicheros)) {
        [void][Windows.MessageBox]::Show("No existe la carpeta:`n$DirFicheros", 'Falta carpeta', 'OK', 'Error'); return
    }
    if ($modo -eq 'ENG' -and -not (Test-Path $DirOriginal)) {
        [void][Windows.MessageBox]::Show("No hay copia de los originales (Data_ORIGINAL).`n`nSe crea al instalar el español por primera vez; si no lo has instalado nunca, el juego ya está en inglés.", 'Sin originales', 'OK', 'Information'); return
    }
    $elegidos = Teatros-Elegidos
    if ($elegidos.Count -eq 0) {
        [void][Windows.MessageBox]::Show('Marca al menos un teatro.', 'Nada que hacer', 'OK', 'Information'); return
    }
    if (-not (Esperar-Cierre)) { return }
    $claves = $elegidos | ForEach-Object { $_.Clave }
    $trabajo = @($lista | Where-Object { $claves -contains $_.Teatro })

    Bloquear $true
    $Log.Children.Clear(); $script:LogTexto = New-Object System.Collections.ArrayList
    $Barra.Maximum = [Math]::Max(1, $trabajo.Count); $Barra.Value = 0
    $nom = Nombre-Idioma; $cod = Cod-Idioma
    if ($modo -eq 'ESP') { $TxtResumen.Text = "Instalando traducción: $nom..." } else { $TxtResumen.Text = 'Restaurando originales en inglés...' }
    $TxtResumen.Foreground = $Brush.Tenue
    $cop = 0; $igual = 0; $omi = 0; $err = 0; $perm = 0; $bak = 0; $act = 0; $sinOrig = 0; $carp = 0; $quit = 0
    $script:Regs = Leer-Registros
    $reg = $script:Regs[$cod]
    $sello = Get-Date -Format 'yyyyMMdd_HHmmss'
    if ($modo -eq 'ESP' -and -not (Test-Path -LiteralPath $DirOriginal)) {
        Escribir 'Primera instalación: se crea Data_ORIGINAL con los ficheros originales de tu Falcon BMS.' 'Acento'
    }

    foreach ($t in $elegidos) {
        Escribir $t.Nombre 'Acento' -Titulo
        $p0 = @($cop, $igual, $omi, $err, $sinOrig)
        $filasT = @($trabajo | Where-Object { $_.Teatro -eq $t.Clave })
        if ($modo -eq 'ESP') {
            # lo que otro idioma instaló en este teatro y este idioma no trae: se vuelve al original
            $propios = @{}; foreach ($f in $filasT) { $propios[(Destino $f).rel.ToLower()] = $true }
            foreach ($i in @($script:Idiomas | Where-Object { $_.codigo -ne $cod })) {
                $rI = $script:Regs[$i.codigo]
                if (-not $rI -or $rI.Count -eq 0) { continue }
                foreach ($f in @(Leer-Lista $i.csv | Where-Object { $_.Teatro -eq $t.Clave })) {
                    $d = Destino $f; $k = $d.rel.ToLower()
                    if ($propios.ContainsKey($k) -or -not $rI.ContainsKey($k)) { continue }
                    if (-not (Test-Path -LiteralPath $d.dst -PathType Leaf) -or (Md5 $d.dst) -ne $rI[$k]) { $rI.Remove($k); continue }
                    if (-not (Test-Path -LiteralPath $d.orig -PathType Leaf)) { Escribir ('  !  ' + $d.rel + "   es de $($i.nombre) y no hay original guardado: se queda") 'Amar'; continue }
                    try { Copiar-Fichero $d.orig $d.dst; $rI.Remove($k); $quit++; Escribir ('  ↺  ' + $d.rel + "   (era de $($i.nombre): vuelve al original)") 'Tenue' }
                    catch { Escribir ('  ✗  ' + $d.rel + '   ' + $_.Exception.Message) 'Rojo'; $err++ }
                }
            }
        }
        foreach ($f in $filasT) {
            $Barra.Value = $Barra.Value + 1
            $d = Destino $f
            $k = $d.rel.ToLower()
            $existe = Test-Path -LiteralPath $d.dst -PathType Leaf
            $nota = ''
            if ($modo -eq 'ESP') {
                $fu = Fuente-Esp $f $t.Clave $d.rel
                if ($fu.falta) { Escribir ('  –  ' + $d.rel + '   (falta en Ficheros: ' + $fu.falta + ')') 'Tenue'; $omi++; continue }
                $src = $fu.src; $nota = $fu.nota
                if ($existe -and (Mismo-Fichero $src $d.dst)) {
                    $txtIgual = '   (ya estaba)'
                    if (-not (Test-Path -LiteralPath $d.orig)) {
                        # el del juego ya es igual a la traducción y no hay copia del original:
                        # es un fichero igual en los dos idiomas (p. ej. un .idx que no cambia)
                        try { Copiar-Fichero $d.dst $d.orig; $bak++; $txtIgual = '   (igual en inglés y en español)' } catch { }
                    } elseif ((Test-Path -LiteralPath $d.orig) -and (Mismo-Fichero $d.orig $d.dst)) { $txtIgual = '   (igual en inglés y en español)' }
                    Escribir ('  =  ' + $d.rel + $txtIgual) 'Tenue'; $igual++; $reg[$k] = Md5 $d.dst
                    foreach ($c in @($script:Regs.Keys)) { if ($c -ne $cod) { $script:Regs[$c].Remove($k) } }
                    continue
                }
                if ($existe) {
                    $hDst = Md5 $d.dst
                    # "nuestro" = lo instaló este instalador (en este idioma o en otro)
                    $nuestro = ($reg.ContainsKey($k) -and $reg[$k] -eq $hDst) -or [bool](Idioma-De-Fichero $k $hDst)
                    if (-not (Test-Path -LiteralPath $d.orig)) {
                        if ($nuestro) {
                            Escribir ('  !  ' + $d.rel + '   no hay original guardado (el del juego es una traducción anterior)') 'Amar'
                        } else {
                            # primera vez: el del juego es el original
                            try { Copiar-Fichero $d.dst $d.orig; $bak++ }
                            catch { Escribir ('  !  ' + $d.rel + '   no se pudo guardar el original: ' + $_.Exception.Message) 'Amar' }
                        }
                    } elseif (-not $nuestro -and $hDst -ne (Md5 $d.orig)) {
                        if ($script:HayRegistro) {
                            # ni es el original guardado ni lo instalamos nosotros: lo ha cambiado BMS (o un mod)
                            try {
                                Copiar-Fichero $d.orig (Join-Path (Join-Path $DirOriginal "_anteriores\$sello") $d.rel)
                                Copiar-Fichero $d.dst $d.orig
                                $act++
                                Escribir ('  !  ' + $d.rel + '   actualizado por BMS: nuevo original guardado; revisa su traducción') 'Amar'
                            } catch { Escribir ('  !  ' + $d.rel + '   no se pudo actualizar el original: ' + $_.Exception.Message) 'Amar' }
                        } else {
                            $nota += '   (distinto del original: se toma como versión anterior de la traducción)'
                        }
                    }
                } elseif (-not (Test-Path -LiteralPath (Split-Path $d.dst -Parent))) {
                    Escribir ('  !  ' + $d.rel + '   la carpeta no existía en el juego: se crea (¿ruta correcta?)') 'Amar'; $carp++
                }
            } else {
                $src = $d.orig
                if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
                    if ($existe) { Escribir ('  !  ' + $d.rel + '   no hay original guardado: se queda traducido') 'Amar'; $sinOrig++ }
                    else { Escribir ('  –  ' + $d.rel + '   (no está en el juego)') 'Tenue'; $omi++ }
                    continue
                }
                if ($existe -and (Mismo-Fichero $src $d.dst)) {
                    Escribir ('  =  ' + $d.rel + '   (ya estaba en inglés)') 'Tenue'; $igual++
                    foreach ($c in @($script:Regs.Keys)) { $script:Regs[$c].Remove($k) }
                    continue
                }
            }
            try {
                Copiar-Fichero $src $d.dst
                Escribir ('  ✓  ' + $d.rel + $nota) 'Verde'; $cop++
                if ($modo -eq 'ESP') {
                    $reg[$k] = Md5 $d.dst
                    foreach ($c in @($script:Regs.Keys)) { if ($c -ne $cod) { $script:Regs[$c].Remove($k) } }
                } else { foreach ($c in @($script:Regs.Keys)) { $script:Regs[$c].Remove($k) } }
            } catch [UnauthorizedAccessException] {
                Escribir ('  ✗  ' + $d.rel + '   sin permiso para escribir') 'Rojo'; $err++; $perm++
            } catch {
                $m = $_.Exception.Message
                if ($_.Exception -is [UnauthorizedAccessException] -or $m -match 'denegado|denied') { $perm++ }
                Escribir ('  ✗  ' + $d.rel + '   ' + $m) 'Rojo'; $err++
            }
        }
        $txtCop = $(if ($modo -eq 'ESP') { 'copiados' } else { 'restaurados' })
        $sub = "  $($filasT.Count) ficheros: $($cop - $p0[0]) $txtCop, $($igual - $p0[1]) ya estaban, $($omi - $p0[2]) no encontrados"
        if ($sinOrig - $p0[4]) { $sub += ", $($sinOrig - $p0[4]) sin original" }
        if ($err - $p0[3]) { $sub += ", $($err - $p0[3]) errores" }
        Escribir $sub 'Tenue'
    }
    Borrar-Temporal
    foreach ($c in @($script:Regs.Keys)) { Guardar-Registro $c $script:Regs[$c] }
    $total = $trabajo.Count
    if ($modo -eq 'ESP') {
        $TxtResumen.Text = "$total ficheros:  copiados $cop  ·  ya estaban $igual  ·  no encontrados $omi  ·  errores $err"
        if ($quit) { $TxtResumen.Text += "  ·  de otro idioma, devueltos al original $quit" }
    }
    else { $TxtResumen.Text = "$total ficheros:  restaurados $cop  ·  ya estaban $igual  ·  sin original $sinOrig  ·  no están $omi  ·  errores $err" }
    if ($bak -gt 0) {
        $TxtResumen.Text += "    ·    Originales guardados: $bak"
        Escribir ''
        Escribir ("Se guardaron $bak originales en Data_ORIGINAL (para «Restaurar inglés»).") 'Acento'
    }
    if ($act -gt 0) {
        Escribir ''
        Escribir ("$act ficheros los ha actualizado BMS desde la última instalación: su traducción puede estar desfasada.") 'Amar'
        Escribir ("Los originales anteriores están en Data_ORIGINAL\_anteriores\$sello.") 'Amar'
    }
    if ($sinOrig -gt 0) {
        Escribir ''
        Escribir ("$sinOrig ficheros siguen traducidos porque no hay copia de su original en Data_ORIGINAL.") 'Amar'
    }
    if ($carp -gt 0) { Escribir ''; Escribir ("$carp ficheros se copiaron a carpetas que no existían: revisa sus rutas en Archivos.csv.") 'Amar' }
    if ($err -gt 0) { $TxtResumen.Foreground = $Brush.Rojo }
    elseif ($act -gt 0 -or $sinOrig -gt 0 -or $carp -gt 0) { $TxtResumen.Foreground = $Brush.Amar }
    elseif ($modo -eq 'ESP') { $TxtResumen.Foreground = $Brush.Verde }
    else { $TxtResumen.Foreground = $Brush.Texto }
    Guardar-Log $(if ($modo -eq 'ESP') { "Instalar $nom" } else { 'Restaurar inglés' })
    Bloquear $false
    if ($perm -gt 0) {
        [void][Windows.MessageBox]::Show("No se pudieron escribir $perm ficheros por falta de permisos.`n`nSi Falcon BMS está en «Archivos de programa» o en otra carpeta protegida, cierra el instalador y ábrelo con clic derecho en Instalar.bat → «Ejecutar como administrador».", 'Permisos', 'OK', 'Warning')
    }
    Estado-Actual
    if ($modo -eq 'ENG') { if (Listar-Estado $elegidos) { Guardar-Log 'Restaurar inglés' } }
}

function Copiar-Fichero([string]$src, [string]$dst) {
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}

# ---------- eventos ----------
(Ctl 'Titulo').Add_MouseLeftButtonDown({ $Win.DragMove() })
(Ctl 'BtnMin').Add_Click({ $Win.WindowState = 'Minimized' })
(Ctl 'BtnCerrarX').Add_Click({ $Win.Close() })
$BtnSalir.Add_Click({ $Win.Close() })
$BtnEsp.Add_Click({ Instalar 'ESP' })
$BtnComprobar.Add_Click({ Comprobar })
$BtnIdioma.Add_Click({ Menu-Idiomas })
$Win.Add_ContentRendered({ Estado-Actual })
$BtnEng.Add_Click({
    $r = [Windows.MessageBox]::Show('Se restaurarán los ficheros originales en inglés de los teatros marcados. ¿Continuar?', 'Restaurar inglés', 'YesNo', 'Question')
    if ($r -eq 'Yes') { Instalar 'ENG' }
})
(Ctl 'LnkRuta').Add_Click({
    $r = Elegir-Ruta
    if ($r) { $script:BMS = $r; Detectar }
})
$BtnEditor.Add_Click({
    if (-not $Editor -or -not (Test-Path -LiteralPath $Editor)) { [void][Windows.MessageBox]::Show('No se encuentra el editor.', 'Editor BMS', 'OK', 'Warning'); return }
    Start-Process -FilePath $env:ComSpec -ArgumentList ('/c "' + $Editor + '"') -WorkingDirectory (Split-Path $Editor -Parent)
    $script:VolverEstado = $true
})
$Win.Add_Activated({
    # al volver del editor, Archivos.csv puede haber cambiado
    # (y el editor puede haber creado un idioma o cambiado el de trabajo)
    if ($script:VolverEstado -and $BtnEsp.IsEnabled) {
        $script:VolverEstado = $false
        Cargar-Idiomas; Poner-Idioma (Idioma-Actual $Aqui $script:Idiomas)
        Estado-Actual
    }
})
$BtnJugar.Add_Click({
    $exe = Join-Path $script:BMS 'Launcher\FalconBMS_Alternative_Launcher.exe'
    if (Test-Path $exe) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe); $Win.Close() }
    else { [void][Windows.MessageBox]::Show("No se encontró el launcher:`n$exe", 'Falcon BMS', 'OK', 'Warning') }
})

# ---------- arranque ----------
$script:BMS = Buscar-BMS
if (-not $script:BMS) {
    [void][Windows.MessageBox]::Show('No se encontró Falcon BMS 4.38 en el registro. Selecciona su carpeta de instalación.', 'Falcon BMS', 'OK', 'Information')
    $script:BMS = Elegir-Ruta
    if (-not $script:BMS) { return }
}
Cargar-Idiomas
Poner-Idioma (Idioma-Actual $Aqui $script:Idiomas)
Detectar
if ($script:Idiomas.Count -eq 0) {
    Escribir 'Todavía no hay ningún idioma de la traducción (carpeta Idiomas).' 'Acento'
    Escribir $(if ($Editor) { 'Para empezar uno: Abrir editor → Traducción → ＋ Nuevo idioma… (parte de los originales en inglés).' } else { 'Para empezar uno, usa el Editor BMS (Traducción → ＋ Nuevo idioma…).' }) 'Tenue'
    Escribir 'Si ya tienes una traducción, copia su carpeta en Idiomas\<CÓDIGO> (con Archivos.csv y Ficheros).' 'Tenue'
}
elseif (-not (Test-Path -LiteralPath $Csv)) { Escribir ('No se encuentra ' + $Csv) 'Rojo' }
[void]$Win.ShowDialog()
Borrar-Temporal
