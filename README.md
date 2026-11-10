# Traducción al español de Falcon BMS 4.38

Traducción no oficial al español de **Falcon BMS 4.38** para los cinco teatros: **Corea**, **Corea Equipo vs Equipo (TvT)**, **Balcanes**, **Grecia (Hellas)** e **Israel**.

Incluye un **instalador** que pone y quita la traducción sin tocar nada más del juego, y un **editor** para seguir traduciendo y ajustando la interfaz, los textos, las campañas y las voces de radio.

> Versión actual: **v1.0 · 2026-11-09**

---

## Qué se traduce

| Parte del juego | Ficheros | Teatros |
|---|---|---|
| Menús e interfaz | `.scf`, `.irc` (LckTxtRc y demás) | Todos |
| Textos e imágenes de los recursos | `.rsc` / `.idx` | Todos |
| Créditos | `Credits.rsc` | Corea y Balcanes |
| Campañas, enfrentamientos tácticos y entrenamientos | `.cam`, `.tac`, `.trn`, `.run` | Todos |
| Subtítulos de las comunicaciones de radio | `F4Talk.csv` | Todos |
| Voces de radio en español *(en preparación)* | `Falcon.tlk` | Todos |

---

## Instalación

### Requisitos

- **Falcon BMS 4.38** instalado.
- Windows 10 u 11 (el instalador usa PowerShell 5, incluido en Windows).

### Pasos

1. Descarga la última versión desde **Releases** y descomprímela en cualquier carpeta.
2. **Cierra Falcon BMS** si está abierto.
3. Ejecuta **`Instalar.bat`**.
4. Comprueba la carpeta de Falcon BMS (la detecta sola; si no, pulsa **Cambiar**).
5. Marca los teatros que quieras y pulsa **Instalar español**.

Para volver al inglés, pulsa **Restaurar inglés**.

### Cómo funciona el instalador

- **Guarda los originales:** antes de sustituir un fichero, guarda el original en inglés en `Data_ORIGINAL`. No hace falta descargar nada aparte para volver al inglés.
- **Sabe qué hay instalado:** el estado de cada teatro aparece en pantalla (*español*, *inglés* o *mezcla*). **Comprobar** revisa todo sin copiar nada.
- **Detecta actualizaciones de BMS:** si una actualización cambia un fichero traducido, guarda el nuevo original y avisa de que esa traducción puede estar desfasada.
- **No toca el juego en marcha:** no instala ni restaura con Falcon BMS abierto.
- **Deja registro:** la última operación queda en `Registro.log`.

---

## Estructura del repositorio

```
├── Instalar.bat                  Lanza el instalador
├── version.txt                   Versión de la traducción
├── Instalador/
│   ├── Instalador.ps1            Instalador (interfaz WPF)
│   ├── Archivos.csv              Lista de ficheros: Teatro;Ficheros;Data
│   ├── logo.png
│   ├── Revisar_redundantes.bat   Lista los ficheros idénticos al original
│   └── Retirar_redundantes.bat   Los retira del instalador (con copia de seguridad)
├── Ficheros/                     Ficheros traducidos (se copian al juego)
└── Editor_BMS/                   Editor (ver más abajo)
```

### `Archivos.csv`

Cada línea indica qué fichero traducido va a qué sitio del juego:

```
Teatro;Ficheros;Data
COREA;RSC\Art\_FHD\Main.rsc;Art\_FHD\Main.rsc
BALCANES;LckTxtRc.irc + LckTxtRc\Cambios_BALCANES.irc;Add-On Balkans\Art\_FHD\LckTxtRc.irc
```

- **Ficheros:** ruta dentro de `Ficheros\`.
- **Data:** ruta relativa a `Falcon BMS 4.38\Data`. Si empieza por `..\`, es relativa a la carpeta de Falcon BMS.
- **«base + cambios»:** instala la base con las líneas `[ADDTEXT]` del fichero de cambios aplicadas encima. Así, un texto común se traduce una vez para todos los teatros.

---

## Editor BMS

`Editor_BMS\Editor_BMS.bat` abre en el navegador un editor local con varias pestañas. Lo que guardas va directamente al instalador: el fichero editado a `Ficheros`, el original a `Data_ORIGINAL` y la línea a `Archivos.csv`. Los ficheros idénticos al original no se copian.

| Pestaña | Para qué sirve |
|---|---|
| **Editor SCF** | Vista previa de las pantallas del juego. Permite mover elementos, cambiar textos e imágenes y saltar al editor RSC con el recurso que usa cada elemento. |
| **Editor RSC** | Ver y editar los recursos de los `.rsc`: imágenes (exportar e importar con control de color y transparencia), textos (exportar e importar a `.txt`), sonidos y créditos. Indica en qué `.scf` se usa cada recurso. |
| **Campañas** | Textos de campañas, enfrentamientos tácticos y entrenamientos. |
| **Voces** | Voces de radio en español: escuchar original y traducción, corregir textos (actualiza también los subtítulos `F4Talk.csv`), generar con IA y montar el `Falcon.tlk`. |
| **Ajuste de voces** | Ajustar y probar cada una de las 14 voces: temperatura, velocidad, volumen, suavizado, limpieza, efecto de radio, silencios y frases de referencia. |

El editor detecta solo la instalación de Falcon BMS y el instalador. Solo puede haber uno abierto a la vez.

Para pasar el editor a otra persona, usa **`Crear_paquete.bat`**. Crea una copia limpia, sin el entorno de Python, la caché de voces ni tus rutas.

---

## Voces de radio en español (opcional)

Las voces se generan en local con **[XTTS-v2](https://huggingface.co/coqui/XTTS-v2)** ([coqui-tts](https://github.com/idiap/coqui-ai-TTS)). Cada una de las 14 voces originales se clona a partir de sus propias frases del `Falcon.tlk`, y se sintetiza el texto traducido del `F4Talk.csv`.

### Requisitos

- Tarjeta **NVIDIA** con CUDA, recomendable de 8 GB o más. Sin ella funciona, pero muy lento.
- Unos 6 GB libres e internet la primera vez.

### Preparación

En la pestaña **Voces**, pulsa **Preparar entorno…**. Instala en `Editor_BMS\Voces`:

- Python 3.11, si no está.
- Una venv con PyTorch, coqui-tts y scipy.
- ffmpeg con libspeex.
- El modelo XTTS-v2. Pide aceptar su licencia no comercial.

### Flujo de trabajo

1. **Ajuste de voces:** prueba y ajusta cada voz y guarda sus ajustes.
2. **Voces → Generar pendientes** (o **Generar 4 teatros**): genera los audios. Se puede cortar y reanudar, y admite varios procesos en paralelo en la GPU.
3. **Montar Falcon.tlk:** codifica los audios en Speex, como los originales, y monta el fichero del teatro.
4. **Guardar en instalador.**

Para retocar una frase suelta: corrige el texto (Enter) y pulsa **↻ + montar** en su fila.

---

## Licencias y avisos

- **Falcon BMS** es obra de **Benchmark Sims**. Esta traducción no es oficial ni está respaldada por ellos. Los ficheros del juego, sus textos, imágenes y sonidos, así como el logotipo, pertenecen a sus autores. Este repositorio solo contiene las versiones traducidas necesarias para la traducción.
- **XTTS-v2** se distribuye bajo la **Coqui Public Model License (CPML)**, de **uso no comercial**. El modelo no se incluye en el repositorio: cada usuario lo descarga y acepta su licencia al preparar el entorno. Las voces generadas con él no deben usarse con fines comerciales.
- **ffmpeg** se descarga de [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) y tiene su propia licencia.
- El código del instalador y del editor puede usarse y modificarse libremente para fines no comerciales relacionados con Falcon BMS.

---

## Contribuir

¿Has encontrado un texto mal traducido o sin traducir? Abre una **issue** indicando:

- el **teatro**,
- **dónde aparece** (pantalla, campaña, mensaje de radio…),
- el **texto actual** y la **corrección** que propones.

Para cambios más grandes, usa el **Editor BMS**, que deja los ficheros listos para el instalador, y envía un **pull request** con los ficheros de `Ficheros/` y las líneas de `Archivos.csv`.
