# Herramienta de traducción de Falcon BMS 4.38

Herramientas para traducir **Falcon BMS 4.38** a cualquier idioma y para instalar esa traducción en el juego:

- **Instalador:** pone y quita una traducción en Falcon BMS sin tocar nada más del juego, teatro a teatro.
- **Editor:** crea y edita la traducción: menús, textos, fichas, campañas, imágenes y voces de radio.

El paquete **no incluye ninguna traducción**. Se crea una con el editor, o se añade una ya hecha en la carpeta `Idiomas` (ver [Dónde va cada traducción](#dónde-va-cada-traducción)).

Funciona con los cinco teatros del juego (**Corea**, **Corea Equipo vs Equipo**, **Balcanes**, **Grecia** e **Israel**) y con cualquier teatro nuevo instalado como `Data\Add-On <Nombre>`.

---

## Requisitos

- **Falcon BMS 4.38** instalado.
- Windows 10 u 11 (usa PowerShell 5, incluido en Windows).
- Solo para generar voces de radio: tarjeta **NVIDIA** con CUDA (recomendable 8 GB o más), unos 8 GB libres e internet la primera vez.

---

## Contenido

```
├── Instalar.bat                  Abre el instalador
├── LEEME.txt                     Primeros pasos
├── Instalador/
│   ├── Instalador.ps1            Instalador (ventana)
│   ├── Idiomas.ps1               Idiomas de la traducción (lo usan el instalador y el editor)
│   ├── Teatros.ps1               Teatros: los conocidos y cualquier «Add-On» nuevo
│   ├── logo.png                  Logo de la ventana (opcional; se puede cambiar)
│   ├── Revisar_redundantes.bat   Lista los ficheros traducidos idénticos al original
│   └── Retirar_redundantes.bat   Los retira del idioma (con copia de seguridad)
└── Editor_BMS/
    ├── Editor_BMS.bat            Abre el editor
    ├── Crear_distribucion.bat    Crea el zip para repartir la herramienta con tus traducciones
    ├── Crear_paquete.bat         Crea un zip solo con el editor
    └── Voces/                    Kit de voces de radio (scripts y mapas de clips)
```

Al usarlo se crean además:

- `Idiomas\`: las traducciones (las crea el editor o las copias tú).
- `Data_ORIGINAL\`: los originales en inglés de los ficheros traducidos. Los guarda el instalador la primera vez y sirven para volver al inglés.

---

## Dónde va cada traducción

Cada traducción es una carpeta dentro de `Idiomas`, con el código del idioma (dos o tres letras):

```
Idiomas/
├── actual.txt               Idioma elegido (lo escriben el instalador y el editor)
├── ES/
│   ├── idioma.json          Código, nombre, idioma de las voces y codificación
│   ├── Archivos.csv         Qué fichero traducido va a qué sitio del juego
│   ├── pronunciaciones.txt  (opcional) Palabras que la voz dice mal
│   └── Ficheros/            Ficheros traducidos
└── PT/ …                    Otros idiomas, con la misma estructura
```

- **Para añadir una traducción ya hecha:** copia su carpeta (por ejemplo `ES`) dentro de `Idiomas`, junto a `Instalar.bat`. Si la carpeta `Idiomas` no existe, créala. El instalador y el editor la encuentran solos.
- **Para tener varias:** una carpeta por idioma. Se elige cuál instalar con el botón **Idioma** del instalador.
- **Formato antiguo:** si la traducción trae `Archivos.csv` y `Ficheros` sueltos junto al instalador, se trata como el español y el instalador propone pasarla a `Idiomas\ES`.

### `idioma.json`

```json
{ "codigo": "PT", "nombre": "Português", "voz": "pt", "codificacion": 1252,
  "lectura": { "basicos": "zero,um,dois,…", "decenas": "vinte,trinta,…", "union": " e ", "decimal": "vírgula", … } }
```

- **nombre:** el nombre del idioma en su propio idioma; es el que se ve en el instalador y en el editor.
- **voz:** idioma del motor de voz (es, pt, fr, it, de…).
- **codificacion:** página de códigos de los textos del juego (1252 sirve para español, portugués, francés, italiano o alemán).
- **lectura:** cómo se leen en voz alta los números, las siglas y los decimales. Se edita desde el editor.

### `Archivos.csv`

Cada línea indica qué fichero traducido va a qué sitio del juego:

```
Teatro;Ficheros;Data
COREA;RSC\Art\_FHD\Main.rsc;Art\_FHD\Main.rsc
BALCANES;LckTxtRc.irc + LckTxtRc\Cambios_BALCANES.irc;Add-On Balkans\Art\_FHD\LckTxtRc.irc
```

- **Teatro:** COREA, TVT, BALCANES, GRECIA, ISRAEL o la clave de un teatro nuevo (`Add-On Malvinas` → `MALVINAS`).
- **Ficheros:** ruta dentro de la carpeta `Ficheros` del idioma.
- **Data:** ruta relativa a `Falcon BMS 4.38\Data`. Si empieza por `..\`, es relativa a la carpeta de Falcon BMS.
- **«base + cambios»:** instala la base con las líneas `[ADDTEXT]` del fichero de cambios aplicadas encima. Así, un texto común se traduce una vez para todos los teatros.

El editor mantiene este fichero solo: al guardar algo, añade su línea si falta.

---

## Instalador

1. **Cierra Falcon BMS** (con el juego abierto no instala ni restaura).
2. Ejecuta **`Instalar.bat`**.
3. Comprueba la carpeta de Falcon BMS (la detecta sola; si no, pulsa **Cambiar**).
4. Elige el idioma con **Idioma**, marca los teatros y pulsa **Instalar** (el botón lleva el nombre del idioma).

Para volver al inglés, pulsa **Restaurar inglés**.

Cómo funciona:

- **Guarda los originales:** antes de sustituir un fichero, guarda el original en inglés en `Data_ORIGINAL`. No hace falta descargar nada aparte para volver al inglés.
- **Solo copia lo que cambia:** los ficheros que ya están igual aparecen como «ya estaba».
- **Sabe qué hay instalado:** muestra el estado de cada teatro (*idioma*, *inglés*, *mezcla* u *otro idioma*). **Comprobar** revisa `Archivos.csv` y las carpetas sin copiar nada.
- **Cambia de idioma limpiamente:** al instalar un idioma, lo que otro hubiera instalado en esos teatros y este no trae vuelve antes al original.
- **Detecta actualizaciones de BMS:** si una actualización cambia un fichero traducido, guarda el nuevo original y avisa de que esa traducción puede estar desfasada.
- **Reconoce teatros nuevos:** cualquier carpeta `Data\Add-On <Nombre>` con pinta de teatro aparece en la lista.
- **Deja registro:** la última operación queda en `Instalador\Registro.log`.
- **Abrir editor** lanza el editor; al volver, el instalador recalcula el estado.

`Revisar_redundantes.bat` lista los ficheros traducidos que son idénticos al original (no hace falta instalarlos) y `Retirar_redundantes.bat` los aparta a `Ficheros\_retirados` y quita su línea de `Archivos.csv`, guardando antes una copia.

Si Falcon BMS está en una carpeta protegida (por ejemplo, «Archivos de programa»), abre `Instalar.bat` con clic derecho → **Ejecutar como administrador**.

---

## Editor

`Editor_BMS\Editor_BMS.bat` (o **Abrir editor** en el instalador) abre el editor en el navegador. Detecta solo Falcon BMS y el instalador, y lo que guardas va directamente al idioma del instalador: el fichero editado a `Ficheros`, el original a `Data_ORIGINAL` y la línea a `Archivos.csv`. Los ficheros idénticos al original no se copian. Solo puede haber un editor abierto a la vez.

### Crear un idioma

En la barra superior, el desplegable **Traducción** elige qué idioma se edita (el mismo que el instalador).

- **＋ Nuevo idioma…** crea `Idiomas\<código>` partiendo de los **originales en inglés** (`Data_ORIGINAL`, o el juego si no tiene una traducción instalada), con la misma lista de ficheros que los demás idiomas.
- **⚙** abre los ajustes del idioma: idioma de la voz, codificación, cómo se leen los números, las siglas y los decimales, la frase de prueba y las pronunciaciones. Hay plantillas para español, portugués, francés, italiano y alemán.

El interruptor **ES | EN** cambia el idioma de la interfaz del editor. Los textos del juego se muestran siempre tal cual.

### Pestañas

| Pestaña | Para qué sirve |
|---|---|
| **Editor SCF** | Vista previa de las pantallas del juego. Permite mover elementos, cambiar textos e imágenes y saltar al editor RSC con el recurso que usa cada elemento. |
| **Editor RSC** | Recursos de los `.rsc`: imágenes (exportar e importar con control de color y transparencia), textos, sonidos y créditos. Indica en qué `.scf` se usa cada recurso. |
| **Campañas** | Textos de campañas, enfrentamientos tácticos y entrenamientos: nombres de objetivos (en los `.cam`/`.tac` y en el `CampObjData.XML` a la vez), bandos, descripciones y textos de los `.run`. |
| **Teatros** | Lo que se ve al elegir teatro y campaña: nombre y descripción (`.tdf`), portada (`.tga`) y, del `Theater.irc`, países, bandos y cada campaña. |
| **Textos** | `Campaign\Strings.txt` de todos los teatros a la vez. Cada texto inglés se traduce una vez y se aplica en todos los teatros donde aparece. Avisa si faltan marcadores `#0`/`%s`. |
| **Fichas** | Base de datos táctica (`TerrData\TacRefDB.xml`) de todos los teatros: nombre, categorías, descripción y radar de cada ficha. Exportar/importar a `.csv` (Excel) o `.txt` con marcas `[[ID]]` (traductor automático). |
| **Ayuda y menús** | Textos de la interfaz (`LckTxtRc.irc`), guía (`GuideTxt.irc`), ayudas emergentes (`HelpText.irc`) y menú de radio (`Menu.dat`). |
| **Voces** | Voces de radio: escuchar original y traducción, corregir textos (también los subtítulos `F4Talk.csv`), generar con IA y montar el `Falcon.tlk`. |
| **Ajuste de voces** | Ajustar y probar cada una de las 14 voces y sus frases de referencia. |

Las listas de Textos, Fichas y Voces tienen filtros (comunes, propios, variantes, sin traducir, cambiados…). **Pretraducir** rellena lo que sigue en inglés en un teatro nuevo con la traducción que ese mismo texto ya tiene en los otros teatros, y lo marca para revisarlo.

### Voces de radio (opcional)

Las voces se generan en local con uno de estos dos motores, a elegir en la rueda (⚙) de la pestaña **Voces**:

- **[Chatterbox Multilingual](https://huggingface.co/ResembleAI/chatterbox)** (Resemble AI, licencia **MIT**). Es el motor por defecto.
- **[XTTS-v2](https://huggingface.co/coqui/XTTS-v2)** ([coqui-tts](https://github.com/idiap/coqui-ai-TTS)), licencia no comercial.

Cada una de las 14 voces originales se clona a partir de sus propias frases del `Falcon.tlk` en inglés, y se sintetiza el texto traducido del `F4Talk.csv` del idioma.

1. **Preparar entorno…** (pestaña Voces): instala en `Editor_BMS\Voces` Python 3.11, el motor elegido, ffmpeg y el modelo. También crea las **referencias de voz** (`Voces\ref`) con las frases más largas y limpias de cada voz del `Falcon.tlk` original de Corea; para eso el juego tiene que estar en inglés o tener su copia en `Data_ORIGINAL`.
2. **Ajuste de voces:** prueba y ajusta cada voz.
3. **Voces → Generar pendientes** (o **Generar todos los teatros**): genera los audios. Se puede cortar y reanudar, y admite varios procesos en paralelo.
4. **Revisar audios:** marca los audios que duran mucho menos o mucho más de lo que deberían, para regenerarlos.
5. **Montar Falcon.tlk** y **Guardar en instalador:** el `Falcon.tlk` montado pasa a `Ficheros` del idioma, como cualquier otro fichero traducido.

Los audios intermedios de cada idioma se guardan en `Voces\Idiomas\<código>\`. Más detalles en `Editor_BMS\Voces\LEEME.txt`.

---

## Repartir tu traducción

- **`Editor_BMS\Crear_distribucion.bat`** crea `Traduccion_BMS_<versión>.zip` junto a la carpeta, con el instalador, el editor y los idiomas de `Idiomas`. Deja fuera lo propio de tu equipo: `Data_ORIGINAL`, copias de seguridad, registros, el entorno de voces, cachés, audios intermedios y tus ajustes. No cambia nada de tu carpeta.
- Para repartir solo la traducción, basta con su carpeta de `Idiomas` (por ejemplo `Idiomas\ES`): quien la reciba la copia en su `Idiomas`.
- **`Editor_BMS\Crear_paquete.bat`** crea un zip solo con el editor.

Si en la carpeta del instalador hay un `version.txt`, el instalador muestra su primera línea junto al título (por ejemplo, la versión de tu traducción).

---

## Licencias y avisos

- **Falcon BMS** es obra de **Benchmark Sims**. Esta herramienta no es oficial ni está respaldada por ellos. Los ficheros del juego, sus textos, imágenes y sonidos, así como el logotipo de Falcon BMS (`Instalador\logo.png`), pertenecen a sus autores. La herramienta no incluye ficheros del juego; los mapas de clips del kit de voces (`Voces\Mapas`) llevan el texto en inglés de cada clip para poder cruzarlo con la traducción.
- **Chatterbox** (Resemble AI) se distribuye bajo licencia **MIT**. Todo el audio que genera lleva una marca de agua inaudible (PerTh) que permite identificarlo como sintético.
- **XTTS-v2** (solo si se elige ese motor) se distribuye bajo la **Coqui Public Model License (CPML)**, de **uso no comercial**. Cada usuario lo descarga y acepta su licencia al preparar el entorno. Las voces generadas con él no deben usarse con fines comerciales.
- **ffmpeg** se descarga de [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) y tiene su propia licencia.
- El código del instalador y del editor puede usarse y modificarse libremente para fines no comerciales relacionados con Falcon BMS.
