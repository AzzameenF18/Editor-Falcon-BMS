# -*- coding: utf-8 -*-
"""
Genera las voces de radio de Falcon BMS con Chatterbox (MIT, por defecto) o XTTS-v2 en el idioma de una traduccion.
El audio parte siempre del ingles: cada voz (voz00..voz13) se clona de su referencia ref\\vozNN.wav
(~30 s de frases del Falcon.tlk original) una sola vez; la "huella" se guarda en ref\\vozNN.latentes.pt.

Cada idioma trabaja en Idiomas\\<CODIGO>\\ del kit (lo prepara el Editor BMS):
  wav\\<Teatro>\\<tlkId>.wav  generados (y _textos.json: con que texto se genero cada uno)
  cache\\              salida del modelo por (voz, texto)            prueba\\   pruebas
Los textos salen del F4Talk.csv traducido de cada teatro (--f4talk Teatro=ruta, lo pasa el editor) y los
clips (que voz dice que fragmento en cada tlkId) del mapa del kit, Mapas\\Mapa_<Teatro>.csv. Si el texto de
un clip cambia en el F4Talk.csv, su audio se vuelve a generar.
Lo que se lee (numeros, siglas...) sale de --lectura (idioma.json) y el idioma de la voz de --idioma-voz.

Uso (el editor pasa todas las rutas):
  python generar_voces.py --idioma PT --lectura ...\\idioma.json --f4talk Corea=...\\F4Talk_KOREA.csv ... --prueba 30
  python generar_voces.py --idioma PT --f4talk ... --teatro Corea   (Corea, Balcanes, Grecia, Israel, otro Add-On o todos)
  Se puede cortar con Ctrl+C y relanzar: sigue donde iba.

Clips con el texto igual que en ingles (estado IGUAL: indicativos, nombres, numeros):
  --igual todo (por defecto) con la voz clonada, para no mezclar voces; numeros: solo los que
  llevan numeros; nada: se quedan con el audio original en ingles.
"""
import argparse, csv, os, re, random, sys, time, shutil, hashlib
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- numeros y siglas
# Como se lee cada idioma (numeros, letras, decimales): lectura.py, configurable en idioma.json
sys.path.insert(0, AQUI)
import lectura as LEC
import motores as M
import voces_util as VU
LECTURA = LEC.Lectura()          # se cambia en main() por la del idioma (--lectura / --idioma-voz)
cargar_diccionario = LEC.cargar_diccionario
def normalizar(texto, dic): return LECTURA.normalizar(texto, dic)
def numero(n): return LECTURA.numero(n)

# ---------------------------------------------------------------- audio
RADIO = {  # nivel: (compresion, ruido en dB respecto a la voz)
    0: (0.0, None),     # solo banda de radio 300-3400 Hz
    1: (1.6, -32),      # suave: compresion ligera y algo de soplido
    2: (3.0, -24),      # fuerte: mas saturacion y ruido
}

def limpiar(a, sr, cantidad):
    """reduccion de ruido/aspereza por sustraccion espectral (0 = nada, 1 = fuerte)"""
    from scipy.signal import stft, istft
    if cantidad <= 0 or len(a) < sr // 10: return a
    n = 512 if sr > 16000 else 256
    f, t, Z = stft(a, sr, nperseg=n)
    M = np.abs(Z); P = np.angle(Z)
    e = M.mean(axis=0)
    suelo = np.percentile(M[:, e <= np.percentile(e, 15)], 50, axis=1, keepdims=True) if (e <= np.percentile(e, 15)).any() else M.min(axis=1, keepdims=True)
    k = 1.0 + 3.0 * cantidad
    G = np.clip(1 - k * suelo / (M + 1e-12), 0.08 + 0.5 * (1 - cantidad), 1)
    from scipy.ndimage import uniform_filter
    G = uniform_filter(G, size=(3, 5))                      # evita el efecto "burbujas"
    _, x = istft(G * M * np.exp(1j * P), sr, nperseg=n)
    return x[:len(a)]

def esperado_de(txt, vel=1.0):
    """duracion esperada (s) de lo que se dice, para detectar lo que el modelo se inventa al final"""
    return (0.15 + 0.075 * len(txt)) / max(float(vel), 0.5)

def cortar_cola(a, sr, esperado):
    """El modelo (sobre todo XTTS), con textos cortos, a veces dice la frase, se calla y "alucina" otro sonido (o repite).
    Si tras un silencio largo ya se ha dicho casi todo lo esperado, se corta ahi."""
    fr = int(0.02 * sr); n = len(a) // fr
    if n < 5 or not esperado: return a
    e = np.sqrt((a[:n * fr].reshape(n, fr) ** 2).mean(1)); v = e > e.max() * 0.06
    hab, i = 0.0, 0
    while i < n:
        if v[i]: hab += 0.02; i += 1; continue
        j = i
        while j < n and not v[j]: j += 1
        hueco = (j - i) * 0.02
        if j < n and hab > 0 and ((hueco >= 0.25 and hab >= 0.8 * esperado) or (hueco >= 0.4 and hab >= 0.55 * esperado)):
            return a[:min(len(a), (i + 3) * fr)]
        i = j
    return a

def dur_util(a, sr, esperado=None):
    """segundos de voz de verdad: sin silencios al principio y al final y sin lo que cortar_cola quitaria"""
    a = np.asarray(a, dtype=np.float64)
    if esperado: a = cortar_cola(a, sr, esperado)
    fr = int(0.02 * sr); n = len(a) // fr
    if n < 2: return len(a) / sr
    e = np.sqrt((a[:n * fr].reshape(n, fr) ** 2).mean(1)); v = np.where(e > e.max() * 0.06)[0]
    return (v[-1] - v[0] + 1) * 0.02 if len(v) else 0.0

def filtro_radio(wav, sr, rms_obj, nivel=1, pre_ms=0, post_ms=0, semilla=0, suavizado=0.0, limpieza=0.0, esperado=None):
    """recorta silencios, pasa a 8 kHz con banda de radio, efectos y volumen.
    suavizado (0-1): quita agudos asperos (corte de 3400 a 2200 Hz); limpieza (0-1): quita ruido/grano.
    pre_ms/post_ms: silencio que se anade (en el Falcon.tlk lo pone montar_tlk.py)
    esperado: duracion esperada del texto (s): corta lo que el modelo se invente al final (cortar_cola)"""
    from scipy.signal import butter, sosfiltfilt, resample_poly
    from math import gcd
    a = np.asarray(wav, dtype=np.float64)
    if limpieza > 0: a = limpiar(a, sr, float(limpieza))
    if esperado: a = cortar_cola(a, sr, esperado)
    env = np.abs(a); umbral = max(env.max() * 0.01, 1e-6)
    idx = np.where(env > umbral)[0]
    if len(idx): a = a[max(0, idx[0] - int(0.02 * sr)): idx[-1] + int(0.04 * sr)]
    g = gcd(sr, 8000); a = resample_poly(a, 8000 // g, sr // g)
    sos = butter(4, [300, 3400], btype='band', fs=8000, output='sos'); a = sosfiltfilt(sos, a)
    if suavizado > 0:
        corte = 3400 - 1200 * min(1.0, float(suavizado))
        a = sosfiltfilt(butter(2, corte, btype='low', fs=8000, output='sos'), a)
    a = a / (np.abs(a).max() + 1e-12)
    comp, ruido = RADIO.get(nivel, RADIO[1])
    if comp: a = np.tanh(comp * a) / np.tanh(comp)                 # compresion tipo radio
    if ruido is not None:
        act = a[np.abs(a) > 0.05]; r = np.sqrt((act ** 2).mean()) if len(act) else 0.1
        n = np.random.default_rng(semilla).standard_normal(len(a))
        n = sosfiltfilt(sos, n); n = n / (np.sqrt((n ** 2).mean()) + 1e-12) * r * 10 ** (ruido / 20)
        a = a + n
        a = sosfiltfilt(sos, a)
    act = a[np.abs(a) > np.abs(a).max() * 0.05]
    rms = np.sqrt((act ** 2).mean()) + 1e-12 if len(act) else 1.0
    a = a / rms * rms_obj
    pico = np.abs(a).max()
    if pico > 31000: a = a * (31000.0 / pico)      # sin saturar: se baja todo si un pico se pasa
    f = min(40, len(a) // 4)                        # fundido de 5 ms en los bordes (sin clics)
    if f: a[:f] *= np.linspace(0, 1, f); a[-f:] *= np.linspace(1, 0, f)
    a = np.concatenate([np.zeros(int(8 * pre_ms)), a, np.zeros(int(8 * post_ms))])
    return a.astype('<i2')

def guardar_wav(ruta, pcm, sr=8000):
    import wave
    d = os.path.dirname(ruta)
    if d: os.makedirs(d, exist_ok=True)
    w = wave.open(ruta, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(np.asarray(pcm, dtype='<i2').tobytes()); w.close()

def crudo_a_pcm(w):
    return np.clip(np.asarray(w, dtype=np.float64) * 32767, -32768, 32767).astype('<i2')

def leer_wav(ruta):
    import wave
    w = wave.open(ruta, 'rb'); sr = w.getframerate(); d = np.frombuffer(w.readframes(w.getnframes()), '<i2'); w.close()
    return d.astype(np.float64) / 32767, sr

# ---------------------------------------------------------------- principal
def _dur(seg):
    seg = int(round(seg))
    if seg < 90: return f'{seg} s'
    if seg < 5400: return f'{seg / 60:.0f} min'
    return f'{seg // 3600} h {seg % 3600 // 60:02d} min'

def resumen(etq, a, teatros, t_carga, t_total, hechos, est, faltan):
    """tiempos de la pasada y, en las pruebas, cuanto tardaria generar lo que falta de los teatros"""
    if not hechos: return
    mot = a.motor + (' ' + a.variante if a.motor == 'chatterbox' else '')
    por = t_total / hechos; mod = est['modelo'] / max(est['n'], 1); aud = est['audio'] / max(est['n'], 1)
    p = print
    p(f'{etq}---------- Resumen de tiempos ({mot}) ----------')
    p(f'{etq}Audios generados: {hechos} en {_dur(t_total)}  (carga del modelo y de las voces: {_dur(t_carga)}, aparte)')
    p(f'{etq}Por audio: {por:.2f} s de media ({hechos / max(t_total, 1e-6) * 60:.0f} audios/min); el modelo solo, {mod:.2f} s')
    p(f'{etq}Voz generada: {aud:.1f} s por audio de media  ->  {aud / max(mod, 1e-6):.1f} s de voz por segundo de cálculo')
    if est['reintentos']: p(f'{etq}Reintentos por audio demasiado largo (alucinación): {est["reintentos"]} ({est["reintentos"] / est["n"] * 100:.0f} %)')
    if faltan is not None:
        claves = {(w[2], w[4]) for w in faltan}
        nombre = ', '.join(teatros) if len(teatros) < 4 else 'los teatros'
        if not claves: p(f'{etq}Estimación: ya está todo generado con {a.motor} ({nombre}).')
        else:
            t1 = len(claves) * por
            p(f'{etq}Estimación ({nombre}): faltan {len(claves)} audios distintos por generar con {a.motor}  ->  ~{_dur(t1)} con 1 proceso')
            N = max(1, min(8, a.procesos))
            if N > 1: p(f'{etq}  con {N} procesos en paralelo (tu ajuste): menos, sin llegar a ~{_dur(t1 / N)} (comparten la GPU)')
            p(f'{etq}  (con {hechos} audios de muestra la cifra es aproximada; lo común a varios teatros se genera una sola vez)')
    p(f'{etq}-------------------------------------------------', flush=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--teatro', default='todos', help='Corea, Balcanes, Grecia, Israel, otro teatro (con mapa en el kit) o todos')
    ap.add_argument('--idioma', default='ES', help='codigo del idioma: carpetas por defecto en Idiomas\\<CODIGO> del kit')
    ap.add_argument('--cache', default='', help='salida limpia del modelo (24 kHz), una por (voz, texto)')
    ap.add_argument('--ref', default=os.path.join(AQUI, 'ref'))
    ap.add_argument('--salida', default='', help='wav generados, por teatro')
    ap.add_argument('--dic', default='', help='pronunciaciones del idioma (palabra = como se dice)')
    ap.add_argument('--igual', default='todo', choices=['numeros', 'todo', 'nada'],
                    help='clips con el texto igual en ingles (indicativos, nombres, numeros): todo = con la voz clonada (por defecto, asi no se mezclan voces), numeros = solo los que llevan numeros, nada = audio original')
    ap.add_argument('--voces', default='')
    ap.add_argument('--prueba', type=int, default=0)
    ap.add_argument('--ids', default='', help='solo estos tlkId (separados por comas)')
    ap.add_argument('--forzar', action='store_true', help='vuelve a generar aunque ya exista (con --ids)')
    ap.add_argument('--ids-de', default='', help='con --ids: los tlkId son de este teatro; se rehacen tambien los clips de los otros '
                    'teatros con la misma voz y el mismo texto (comparten audio)')
    ap.add_argument('--sospechosos', action='store_true',
                    help='solo informa (JSON): audios generados del teatro que duran mucho menos (cortados) o mucho mas (cola) de lo que deberian')
    ap.add_argument('--motor', default='chatterbox', choices=['chatterbox', 'xtts'],
                    help='chatterbox (MIT, por defecto) o xtts (XTTS-v2, licencia no comercial)')
    ap.add_argument('--variante', default='v3', choices=['v3', 'es-es'], help='Chatterbox: v3 (multilingue) o es-es (afinado para espanol de Espana)')
    ap.add_argument('--cb-temperatura', type=float, default=0.8, help='Chatterbox: temperatura')
    ap.add_argument('--expresividad', type=float, default=0.5, help='Chatterbox: expresividad (exaggeration); mas = mas intenso y algo mas rapido')
    ap.add_argument('--cfg', type=float, default=0.5, help='Chatterbox: cfg_weight; menos = ritmo mas pausado')
    ap.add_argument('--temperatura', type=float, default=0.65)
    ap.add_argument('--velocidad', type=float, default=1.0, help='1.0 = natural; otros valores ensucian la voz')
    ap.add_argument('--rms', type=float, default=6000, help='volumen (los originales rondan 7000)')
    ap.add_argument('--pausa-inicio', type=int, default=25, help='ms de silencio antes (solo en prueba; en el tlk lo pone montar_tlk.py)')
    ap.add_argument('--pausa-fin', type=int, default=15, help='ms de silencio despues (idem)')
    ap.add_argument('--radio', type=int, default=1, choices=[0, 1, 2], help='efecto de radio: 0 limpio, 1 suave, 2 fuerte')
    ap.add_argument('--suavizado', type=float, default=0.0, help='0-1: quita agudos asperos')
    ap.add_argument('--limpieza', type=float, default=0.0, help='0-1: quita ruido/grano de la voz')
    ap.add_argument('--crudo', action='store_true', help='en prueba, guarda tambien la salida del modelo sin filtro de radio')
    ap.add_argument('--refiltrar', action='store_true', help='vuelve a aplicar radio/volumen a todo lo generado (sin GPU)')
    ap.add_argument('--comparar', type=int, default=0, help='N frases con 4 ajustes distintos en prueba\\comparar')
    ap.add_argument('--rehacer-latentes', action='store_true')
    ap.add_argument('--rehacer', action='store_true', help='vuelve a generar TODO lo de las voces indicadas con --voces')
    ap.add_argument('--desfasadas', action='store_true',
                    help='solo informa (JSON): voces cuya referencia o ajustes han cambiado desde que se generaron y cuanto falta')
    ap.add_argument('--regenerar-voces', default='', help='voces (0-13, con comas) a generar de nuevo en los teatros elegidos, ademas de lo que falte')
    ap.add_argument('--procesos', type=int, default=1, help='procesos del modelo en paralelo en la GPU (1-8)')
    ap.add_argument('--trabajador', default='', help=argparse.SUPPRESS)   # k/N: uso interno con --procesos
    ap.add_argument('--ajustes-voces', default=os.path.join(AQUI, 'ajustes_voces.json'),
                    help='ajustes guardados por voz en la pestana "Ajuste de voces" (tienen prioridad)')
    ap.add_argument('--solo-texto', action='store_true', help='solo muestra como se normalizan los textos')
    ap.add_argument('--f4talk', action='append', default=[], help='Teatro=ruta del F4Talk.csv traducido (uno por teatro)')
    ap.add_argument('--ficheros', default=None, help='carpeta Ficheros del idioma en el instalador (busca ahi F4Talk\\F4Talk_<TEATRO>.csv)')
    ap.add_argument('--codificacion', default='cp1252', help='codificacion de los F4Talk.csv si no son UTF-8')
    ap.add_argument('--lectura', default='', help='idioma.json del idioma (numeros, letras...); sin el, la plantilla de --idioma-voz')
    ap.add_argument('--idioma-voz', default='', help='idioma de la voz (es, pt, fr, it, de...); por defecto el de --lectura o es')
    ap.add_argument('--prueba-dir', default='', help='carpeta de --prueba y --comparar')
    a = ap.parse_args()
    base = os.path.join(AQUI, 'Idiomas', a.idioma.upper())
    suf = '' if a.motor == 'xtts' else '_cb'      # lo de cada motor va aparte (wav\ y cache\ son de XTTS)
    a.salida = a.salida or os.path.join(base, 'wav' + suf); a.cache = a.cache or os.path.join(base, 'cache' + suf)
    a.prueba_dir = a.prueba_dir or os.path.join(base, 'prueba'); a.dic = a.dic or os.path.join(base, 'pronunciaciones.txt')
    global LECTURA
    IDV = a.idioma_voz or LEC.idioma_voz(a.lectura, 'es')
    LECTURA = LEC.cargar(a.lectura, IDV) if a.lectura else LEC.Lectura(None, IDV)
    if IDV != 'es' or a.lectura: print('Idioma de la voz:', IDV, flush=True)

    dic = cargar_diccionario(a.dic)
    AJV = {}
    if os.path.exists(a.ajustes_voces) and not a.comparar:
        try:
            import json
            AJV = {int(k): v for k, v in json.load(open(a.ajustes_voces, encoding='utf-8-sig')).items()}
            if AJV: print('Ajustes propios para las voces:', ', '.join(f'{k:02d}' for k in sorted(AJV)))
        except Exception as e: print('No se pudo leer', a.ajustes_voces, e)
    def par(v, k):
        defecto = {'temperatura': a.temperatura, 'velocidad': a.velocidad, 'rms': a.rms, 'radio': a.radio,
                   'suavizado': a.suavizado, 'limpieza': a.limpieza, 'cbTemperatura': a.cb_temperatura,
                   'expresividad': a.expresividad, 'cfg': a.cfg}[k]
        x = AJV.get(v, {}).get(k)
        return defecto if x is None else (int(x) if k == 'radio' else float(x))
    def pvoz(v):
        """parametros de voz (del motor) de la voz v"""
        return M.params(a.motor, par(v, 'temperatura'), par(v, 'velocidad'), par(v, 'cbTemperatura'), par(v, 'expresividad'), par(v, 'cfg'))
    def ritmo(v): return M.ritmo(a.motor, pvoz(v))
    if a.ids_de: a.teatro = 'todos'          # para encontrar los mismos clips en los otros teatros
    if a.teatro.lower() == 'todos':
        # todos los teatros con lista en la carpeta del idioma (tambien los Add-On nuevos)
        teatros = VU.teatros_kit()
    else: teatros = [a.teatro]
    voces = {int(x) for x in a.voces.split(',') if x.strip()} if a.voces else set(range(14))
    ids = {int(x) for x in a.ids.split(',') if x.strip()}

    trabajo = []  # (teatro, tlkId, voz, texto_es, texto_tts)
    filas = []
    VU.FICHEROS = a.ficheros
    F4 = VU.f4_pares(a.f4talk)
    if a.codificacion.isdigit(): a.codificacion = 'cp' + a.codificacion
    for te in list(teatros):
        try: fs = VU.filas_teatro(te, F4.get(te), a.codificacion)
        except SystemExit as e: print(e); teatros.remove(te); continue
        if te not in F4: print(f'Aviso: {te} sin F4Talk.csv traducido: sus textos salen en inglés.', flush=True)
        filas += [[te] + r for r in fs]
    for te, t, fr, v, est, en, es in filas:
        v = int(v)
        if ids and int(t) not in ids and not a.ids_de: continue
        if v not in voces or not es.strip() or es.strip().startswith('('): continue
        if est == 'IGUAL':
            if a.igual == 'nada': continue
            if a.igual == 'numeros' and not re.search(r'\d', es): continue
        elif est != 'TRADUCIR': continue
        tts = normalizar(es, dic)
        if not re.search(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]', tts): continue
        trabajo.append((te, int(t), v, es, tts))
    if a.ids_de:
        # los clips pedidos (de ese teatro) y los de los otros teatros con la misma voz y el mismo texto
        claves = {(w[2], w[4]) for w in trabajo if w[0] == a.ids_de and w[1] in ids}
        trabajo = [w for w in trabajo if (w[2], w[4]) in claves]
        ids = {w[1] for w in trabajo}

    if a.solo_texto:
        vistos = set()
        for te, t, v, es, tts in trabajo:
            if es != tts and es not in vistos: vistos.add(es); print(f'{es!r:45} -> {tts}')
        print(len(trabajo), 'clips'); return

    trabajo_todo = trabajo
    if a.comparar:
        a.prueba = a.comparar; a.crudo = True
        largos = [w for w in trabajo if len(w[4]) >= 18] or trabajo
        random.seed(); trabajo = random.sample(largos, min(a.comparar, len(largos)))
        a.salida = os.path.join(a.prueba_dir, 'comparar')
        if os.path.isdir(a.salida): shutil.rmtree(a.salida, ignore_errors=True)
    elif a.prueba:
        random.seed(); trabajo = random.sample(trabajo, min(a.prueba, len(trabajo)))
        if not a.comparar:
            a.salida = a.prueba_dir
            if os.path.isdir(a.salida): shutil.rmtree(a.salida, ignore_errors=True)
    def destino(w):
        te, t, v, es, txt = w
        if a.prueba:
            import unicodedata     # nombre solo con letras sin tilde (los nombres con tildes daban problemas al abrirlos)
            sin = unicodedata.normalize('NFKD', es).encode('ascii', 'ignore').decode('ascii')
            limpio = re.sub(r'[^A-Za-z0-9]+', '_', sin).strip('_')[:40]
            return os.path.join(a.salida, f'voz{v:02d}_{t}_{limpio}.wav')
        return os.path.join(a.salida, te, f'{t}.wav')
    def encache(w):
        h = hashlib.md5(w[4].encode('utf-8')).hexdigest()[:16]
        return os.path.join(a.cache, f'voz{w[2]:02d}', h + '.wav')
    if not a.prueba:
        for te in teatros: os.makedirs(os.path.join(a.salida, te), exist_ok=True)
    # registro de con que texto se genero cada audio (wav\<Teatro>\_textos.json): si el texto del F4Talk
    # cambia, el audio deja de valer
    REG = {}
    def reg(te):
        if te not in REG: REG[te] = VU.leer_registro(os.path.join(a.salida, te))
        return REG[te]
    def vigente(w):
        if not os.path.exists(destino(w)): return False
        r = reg(w[0]).get(str(w[1]))
        if r is not None: return r == VU.huella_texto(w[3])
        return os.path.exists(encache(w))      # de antes del registro: vale si la cache tiene el texto actual
    def sellar(ws):
        cambiados = set()
        for w in ws:
            h = VU.huella_texto(w[3]); r = reg(w[0])
            if r.get(str(w[1])) != h: r[str(w[1])] = h; cambiados.add(w[0])
        for te in cambiados: VU.guardar_registro(os.path.join(a.salida, te), reg(te))
    if a.refiltrar:
        n = 0; hechos_ref = {}; escritos = []
        for w in trabajo:
            c = encache(w)
            if not os.path.exists(c): continue
            if c not in hechos_ref:
                x, sr = leer_wav(c); hechos_ref[c] = filtro_radio(x, sr, par(w[2], 'rms'), par(w[2], 'radio'), semilla=w[1],
                                                           suavizado=par(w[2], 'suavizado'), limpieza=par(w[2], 'limpieza'),
                                                           esperado=esperado_de(w[4], ritmo(w[2])))
            guardar_wav(destino(w), hechos_ref[c]); n += 1; escritos.append(w)
            if n % 2000 == 0: print(f'  {n} clips...')
        sellar(escritos)
        print(f'Refiltrados {n} clips.'); return
    if a.rehacer and a.voces and not a.prueba:
        borrados = 0
        for w in trabajo:
            for f in (destino(w), encache(w)):
                if os.path.exists(f): os.remove(f); borrados += 1
        print(f'Rehacer voces {a.voces}: {borrados} ficheros borrados para generarlos de nuevo.')
    if a.forzar and ids and not a.prueba:
        for w in trabajo:
            for f in (destino(w), encache(w)):
                if os.path.exists(f): os.remove(f)
    # ---- huella de cada voz: referencia + motor + ajustes de voz con los que se generaron sus audios ----
    # (si cambia, lo ya generado de esa voz esta "desfasado": el editor pregunta si regenerarlo)
    import json as _json
    ffirmas = os.path.join(a.cache, 'firmas.json')
    def firma(v):
        try: h = hashlib.md5(open(os.path.join(a.ref, f'voz{v:02d}.wav'), 'rb').read()).hexdigest()
        except Exception: h = ''
        d = {'ref': h, 'motor': a.motor, 'idioma': IDV, 'voz': {k: round(float(x), 4) for k, x in pvoz(v).items()}}
        if a.motor == 'chatterbox': d['variante'] = a.variante
        return hashlib.md5(_json.dumps(d, sort_keys=True).encode()).hexdigest()[:16]
    try: FIRMAS = {int(k): x for k, x in _json.load(open(ffirmas, encoding='utf-8')).items()}
    except Exception: FIRMAS = {}
    hechas = {w[2] for w in trabajo if os.path.exists(destino(w)) or os.path.exists(encache(w))}
    desfasadas = sorted(v for v in hechas if v in FIRMAS and FIRMAS[v] != firma(v))
    if a.sospechosos:
        # duracion de la voz de cada audio generado frente a lo que deberia durar su texto, comparando con lo normal de
        # esa voz (cada voz habla a su ritmo): muy corto = frase cortada; muy largo = cola o repeticion
        datos = []
        for w in trabajo:
            if w[0] != teatros[0] or not vigente(w): continue
            try: x, sr = leer_wav(destino(w))
            except Exception: continue
            esp = esperado_de(w[4], M.ritmo(a.motor, pvoz(w[2])))
            datos.append((w, dur_util(x, sr), esp))
        med = {}
        for v in {d[0][2] for d in datos}:
            rs = sorted(d[1] / d[2] for d in datos if d[0][2] == v and d[2] >= 0.8)
            med[v] = rs[len(rs) // 2] if rs else 1.0
        out = []
        for w, dur, esp in datos:
            e = esp * med.get(w[2], 1.0)
            tipo = 'largo' if dur > e * 1.7 + 0.5 else 'corto' if (esp >= 1.0 and dur < e * 0.5) else None
            if tipo: out.append({'id': w[1], 'voz': w[2], 'es': w[3], 'dur': round(dur, 2), 'esperado': round(e, 2), 'tipo': tipo})
        print(_json.dumps({'ok': True, 'teatro': teatros[0], 'revisados': len(datos), 'sospechosos': out}, ensure_ascii=False))
        return
    if a.desfasadas:
        sin = {(w[2], w[4]) for w in trabajo if not vigente(w) and not os.path.exists(encache(w))}
        copiar = sum(1 for w in trabajo if not vigente(w) and os.path.exists(encache(w)))
        regen = {v: len({w[4] for w in trabajo if w[2] == v}) for v in desfasadas}
        print(_json.dumps({'ok': True, 'teatros': teatros, 'clips': len(trabajo), 'por_sintetizar': len(sin), 'por_copiar': copiar,
                           'desfasadas': desfasadas, 'audios_desfasadas': regen}))
        return
    regenerar = {int(x) for x in a.regenerar_voces.split(',') if x.strip()} if not a.prueba else set()
    if regenerar:
        borrados = 0
        for w in trabajo:
            if w[2] not in regenerar: continue
            for f in (destino(w), encache(w)):
                if os.path.exists(f): os.remove(f); borrados += 1
        print(f"Regenerar voces {', '.join(f'{v:02d}' for v in sorted(regenerar))}: {borrados} ficheros borrados para generarlos de nuevo.", flush=True)
    if not a.prueba and not a.trabajador and not a.refiltrar:
        # se apunta la huella actual salvo en las voces desfasadas que no se regeneran (lo suyo sigue siendo lo viejo)
        nuevas = dict(FIRMAS)
        for v in {w[2] for w in trabajo}:
            if v in desfasadas and v not in regenerar: continue
            nuevas[v] = firma(v)
        if nuevas != FIRMAS:
            os.makedirs(a.cache, exist_ok=True)
            _json.dump({str(k): x for k, x in sorted(nuevas.items())}, open(ffirmas, 'w', encoding='utf-8'))
        quedan = [v for v in desfasadas if v not in regenerar]
        if quedan:
            print(f"Aviso: las voces {', '.join(f'{v:02d}' for v in quedan)} han cambiado (referencia o ajustes) desde que se "
                  "generaron; lo ya generado de ellas no se rehace.", flush=True)

    def filtrar_a(w, x, sr, ruta, pre=0, post=0):
        guardar_wav(ruta, filtro_radio(x, sr, par(w[2], 'rms'), par(w[2], 'radio'), pre, post, semilla=w[1],
                                       suavizado=par(w[2], 'suavizado'), limpieza=par(w[2], 'limpieza'),
                                       esperado=esperado_de(w[4], ritmo(w[2]))))
    def de_cache(w):
        c = encache(w)
        if not os.path.exists(c): return False
        try: x, sr = leer_wav(c)
        except Exception: return False
        if sr != 24000: return False            # cache de una version anterior (ya filtrada): se rehace
        filtrar_a(w, x, sr, destino(w)); return True

    if not a.prueba and not a.trabajador:
        # audios generados con un texto que ya no es el del F4Talk: se borran para generarlos de nuevo
        viejos = [w for w in trabajo if os.path.exists(destino(w)) and not vigente(w)]
        for w in viejos:
            try: os.remove(destino(w))
            except OSError: pass
        if viejos: print(f'{len(viejos)} audios generados con un texto anterior (el F4Talk ha cambiado): se vuelven a generar.', flush=True)
        sellar([w for w in trabajo if os.path.exists(destino(w))])
    pend = [w for w in trabajo if a.prueba or not os.path.exists(destino(w))]
    if not a.prueba:
        pend = [w for w in pend if not de_cache(w)]   # lo que ya esta en la cache solo hay que filtrarlo
    # trabajador k/N: solo su parte de los audios distintos (reparto alterno, así todos acaban a la vez)
    etiqueta = ''
    if a.trabajador and not a.prueba:
        # el coordinador deja en un fichero las claves (voz, texto) de este trabajador
        kn, _, fich = a.trabajador.partition(':')
        k = int(kn.split('/')[0])
        import json
        mias = {(int(v), t) for v, t in json.load(open(fich, encoding='utf-8'))}
        pend = [w for w in pend if (w[2], w[4]) in mias]
        etiqueta = f'[p{k + 1}] '
    unicos = len({(w[2], w[4]) for w in pend})
    print(f'{etiqueta}Clips pendientes: {len(pend)} de {len(trabajo)}  ->  audios distintos a sintetizar: {unicos}', flush=True)
    if not pend:
        if not a.trabajador:
            print(f'No hay nada que generar: los {len(trabajo)} clips de {", ".join(teatros)} ya están generados con {a.motor} '
                  f'({a.salida}).\nPara rehacer una voz: «Regenerar voz» en Ajuste de voces; para rehacerlo todo: '
                  'Limpiar voces → audios generados de este motor.', flush=True)
        return
    # coordinador: lanza N trabajadores en esta misma consola y espera
    N = max(1, min(8, a.procesos))
    if N > 1 and not a.trabajador and not a.prueba and unicos >= N * 4:
        import subprocess
        print(f'Generando con {N} procesos en paralelo (cada uno carga el modelo en la GPU)...', flush=True)
        import json, tempfile
        base = [sys.executable, os.path.abspath(__file__)] + sys.argv[1:]
        claves = sorted({(w[2], w[4]) for w in pend})
        fichs = []
        for k in range(N):
            fd, ruta = tempfile.mkstemp(prefix=f'voces_p{k + 1}_', suffix='.json'); os.close(fd)
            json.dump(claves[k::N], open(ruta, 'w', encoding='utf-8')); fichs.append(ruta)
        hijos = [subprocess.Popen(base + ['--trabajador', f'{k}/{N}:{fichs[k]}']) for k in range(N)]
        t0 = time.time()
        try:
            codigos = [h.wait() for h in hijos]
        except KeyboardInterrupt:
            for h in hijos:
                try: h.terminate()
                except Exception: pass
            sellar([w for w in trabajo if os.path.exists(destino(w))])
            print('Cortado. Lo generado queda guardado: al relanzar sigue donde iba.'); raise SystemExit(1)
        for f in fichs:
            try: os.remove(f)
            except Exception: pass
        # lo que comparten varios teatros: se rellenan los destinos que falten desde la cache
        faltan = [w for w in trabajo if not os.path.exists(destino(w))]
        hechos_c = sum(1 for w in faltan if de_cache(w))
        sellar([w for w in trabajo if os.path.exists(destino(w))])
        seg = time.time() - t0; mins = seg / 60
        print(f'Terminado en {mins:.0f} min con {N} procesos' + (f' (+{hechos_c} copiados de la cache)' if hechos_c else '') +
              ('' if all(c == 0 for c in codigos) else '  ·  ALGÚN PROCESO HA FALLADO: revisa los mensajes de arriba'))
        print(f'En conjunto: {unicos} audios en {_dur(seg)}  ->  {seg / max(unicos, 1):.2f} s por audio con {N} procesos '
              f'({unicos / max(seg, 1e-6) * 60:.0f} audios/min). El detalle de cada proceso está arriba ([p1], [p2]...).', flush=True)
        raise SystemExit(0 if all(c == 0 for c in codigos) else 1)

    t_carga = time.time()
    mot = M.cargar(a.motor, a.variante, aviso=lambda t: print(etiqueta + t, flush=True))
    print(f"{etiqueta}Motor: {a.motor}{' ' + a.variante if a.motor == 'chatterbox' else ''}", flush=True)
    vs = sorted({w[2] for w in pend})
    print(f"{etiqueta}Cargando las voces {', '.join(f'{v:02d}' for v in vs)}...", flush=True)
    for v in vs: mot.voz(v, a.ref, rehacer=a.rehacer_latentes)
    t_carga = time.time() - t_carga
    EST = {'modelo': 0.0, 'audio': 0.0, 'reintentos': 0, 'n': 0}

    def sintetizar(v, txt, p):
        frase = txt[0].upper() + txt[1:]
        if frase[-1] not in '.?!': frase += '.'
        # con textos muy cortos el modelo a veces "alucina": se limita la duracion y se reintenta
        # (se mide la voz util: sin silencios ni la cola que se va a cortar igualmente; el modelo no puede pasar del
        # doble de lo razonable, asi una frase que no termina no cuesta 40 s de calculo)
        maxdur = (0.6 + 0.085 * len(txt)) / M.ritmo(a.motor, p)
        esp = esperado_de(txt, M.ritmo(a.motor, p))
        mejor = None; mdur = None; t1 = time.time()
        for intento in range(3):
            if intento: EST['reintentos'] += 1
            x = mot.decir(v, frase, IDV, a.ref, max_seg=maxdur * 2 + 1.0, **p); dur = dur_util(x, 24000, esp)
            if mejor is None or dur < mdur: mejor, mdur = x, dur
            if dur <= maxdur * 1.25: break
        EST['modelo'] += time.time() - t1; EST['audio'] += len(mejor) / 24000; EST['n'] += 1
        return mejor

    if a.comparar:
        os.makedirs(a.salida, exist_ok=True)
        if a.motor == 'xtts':
            ajustes = [({'temperatura': t_, 'velocidad': v_}, f'temp{t_:.2f}_vel{v_:.1f}') for t_, v_ in ((0.65, 1.0), (0.5, 1.0), (0.8, 1.0), (0.65, 1.1))]
        else:
            ajustes = [({'temperatura': t_, 'expresividad': e_, 'cfg': c_}, f'temp{t_:.2f}_exp{e_:.2f}_cfg{c_:.2f}')
                       for t_, e_, c_ in ((0.8, 0.5, 0.5), (0.6, 0.5, 0.5), (0.8, 0.5, 0.3), (0.8, 0.7, 0.4))]
        for k, w in enumerate(pend, 1):
            te, t, v, es, txt = w
            import unicodedata
            base = f'{k:02d}_voz{v:02d}_' + re.sub(r'[^A-Za-z0-9]+', '_', unicodedata.normalize('NFKD', es).encode('ascii', 'ignore').decode('ascii')).strip('_')[:30]
            for n_, (p, et) in enumerate(ajustes):
                x = sintetizar(v, txt, p); vel = M.ritmo(a.motor, p)
                if n_ == 0:
                    guardar_wav(os.path.join(a.salida, f'{base}__{et}__0_sin_filtro.wav'), crudo_a_pcm(x), 24000)
                    for nv in (0, 1, 2):
                        guardar_wav(os.path.join(a.salida, f'{base}__{et}__radio{nv}.wav'),
                                    filtro_radio(x, 24000, a.rms, nv, a.pausa_inicio, a.pausa_fin, semilla=t, esperado=esperado_de(txt, vel)))
                else:
                    guardar_wav(os.path.join(a.salida, f'{base}__{et}__radio{a.radio}.wav'),
                                filtro_radio(x, 24000, a.rms, a.radio, a.pausa_inicio, a.pausa_fin, semilla=t, esperado=esperado_de(txt, vel)))
            print(f'  {k}/{len(pend)}  [{v:02d}] {es}')
        print('Terminado ->', a.salida); return

    t0 = time.time(); hechos = 0; t_aviso = t0; fallidos = []; seguidos = 0
    import gc, collections
    recientes = collections.deque(maxlen=30)      # tiempos de los ultimos audios: velocidad de ahora, no la media
    def gpu_gb():
        try: return mot.torch.cuda.memory_reserved() / 2**30
        except Exception: return None
    def liberar():
        # PyTorch se queda con la memoria de video que va usando (cada frase pide un tamano distinto) y en Windows,
        # cuando la GPU se llena, el driver pasa a usar RAM del sistema sin avisar: todo va cada vez mas lento.
        # Se devuelve cada poco
        gc.collect()
        try: mot.torch.cuda.empty_cache()
        except Exception: pass
    pend.sort(key=lambda w: (w[2], w[4]))
    print(f'{etiqueta}Generando... (en las pruebas se ve cada audio; si no, cada 25 o cada 10 s)', flush=True)
    for i, w in enumerate(pend, 1):
        te, t, v, es, txt = w
        if not a.prueba and de_cache(w): continue     # otro teatro ya lo genero en esta pasada
        try:
            t1 = time.time()
            x = sintetizar(v, txt, pvoz(v)); seguidos = 0
            recientes.append(time.time() - t1)
        except Exception as e:
            # un audio que falla no tumba el proceso (y con el lo que le quedaba): se salta y se reintenta en la
            # proxima pasada. Si fallan muchos seguidos (p. ej. sin memoria de video), si se para
            fallidos.append(w); seguidos += 1
            print(f'{etiqueta}  ERROR en [{v:02d}] {es!r}: {type(e).__name__}: {e}', flush=True)
            if seguidos >= 10: print(f'{etiqueta}10 errores seguidos: se para este proceso.', flush=True); raise
            if 'out of memory' in str(e).lower():
                try: mot.torch.cuda.empty_cache()
                except Exception: pass
            continue
        if a.prueba:
            pi = AJV.get(v, {}).get('pausaInicio'); pf = AJV.get(v, {}).get('pausaFin')
            filtrar_a(w, x, 24000, destino(w), a.pausa_inicio if pi is None else int(pi), a.pausa_fin if pf is None else int(pf))
            if a.crudo: guardar_wav(destino(w)[:-4] + '__sin_filtro.wav', crudo_a_pcm(x), 24000)
        else:
            c = encache(w); os.makedirs(os.path.dirname(c), exist_ok=True)
            guardar_wav(c, crudo_a_pcm(x), 24000)
            filtrar_a(w, x, 24000, destino(w))
        hechos += 1
        if hechos % 20 == 0: liberar()
        if a.prueba or hechos % 25 == 0 or i == len(pend) or time.time() - t_aviso >= 10:
            t_aviso = time.time()
            por = sum(recientes) / len(recientes) if recientes else (time.time() - t0) / hechos
            quedan = (unicos - hechos) * por / 60
            g = gpu_gb()
            rei = EST['reintentos'] * 100 / max(EST['n'], 1)
            print(f'{etiqueta}  {hechos}/{unicos}  ({por:.1f} s/audio ahora, faltan ~{quedan:.0f} min'
                  + (f', GPU {g:.1f} GB' if g is not None else '') + f', {rei:.0f} reintentos por cada 100)  ultimo: [{v:02d}] {es}', flush=True)
    if not a.prueba and not a.trabajador: sellar([w for w in trabajo if os.path.exists(destino(w))])
    if fallidos:
        print(f'{etiqueta}{len(fallidos)} audios no se pudieron generar (se reintentan al volver a pulsar Generar):', flush=True)
        for w in fallidos[:20]: print(f'{etiqueta}  [{w[2]:02d}] {w[0]} {w[1]}: {w[3]}')
    print('Terminado ->', a.salida)
    resumen(etiqueta, a, teatros, t_carga, time.time() - t0, hechos, EST,
            [w for w in trabajo_todo if not os.path.exists(encache(w))] if a.prueba else None)

if __name__ == '__main__':
    main()
