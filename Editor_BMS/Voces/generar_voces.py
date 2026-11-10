# -*- coding: utf-8 -*-
"""
Genera las voces de radio en espanol de Falcon BMS con XTTS-v2 (coqui-tts).

Cada voz (voz00..voz13) se "estandariza" UNA sola vez a partir de su referencia larga
(ref\\vozNN.wav, ~30 s de frases largas del propio Falcon.tlk). Los latentes resultantes
se guardan en ref\\vozNN.latentes.pt y se reutilizan para todos los fragmentos, de forma
que la voz suena igual en "uno" que en una frase larga.

Uso:
  python generar_voces.py --prueba 30          -> 30 fragmentos al azar en .\\prueba (para escuchar)
  python generar_voces.py                      -> los 4 teatros, en .\\wav_es\\<Teatro>\\<tlkId>.wav
  python generar_voces.py --teatro Corea       -> solo un teatro (Corea, Balcanes, Grecia, Israel)
  Se puede cortar con Ctrl+C y relanzar: sigue donde iba. Cada (voz, texto) se genera UNA vez
  en .\\cache y se reutiliza en todos los teatros.
  python generar_voces.py --voces 0,4,12       -> solo esas voces
  python generar_voces.py --rehacer-latentes   -> recalcula la "huella" de cada voz

Opciones de que generar (columna estado de la lista):
  TRADUCIR  -> siempre
  IGUAL     -> por defecto solo si lleva numeros (1-1, 0-8-7, F-16...), para que se lean en espanol.
               --igual todo   : tambien indicativos y nombres (Cheetah, Kunsan...) con la voz clonada
               --igual nada   : deja todos los IGUAL con el audio original en ingles
"""
import argparse, csv, os, re, random, sys, time, shutil, hashlib
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- numeros y siglas
UNI = ['cero','uno','dos','tres','cuatro','cinco','seis','siete','ocho','nueve','diez','once','doce','trece',
       'catorce','quince','dieciséis','diecisiete','dieciocho','diecinueve','veinte','veintiuno','veintidós',
       'veintitrés','veinticuatro','veinticinco','veintiséis','veintisiete','veintiocho','veintinueve']
DEC = ['','','','treinta','cuarenta','cincuenta','sesenta','setenta','ochenta','noventa']
CEN = ['','ciento','doscientos','trescientos','cuatrocientos','quinientos','seiscientos','setecientos','ochocientos','novecientos']

def _n999(n):
    if n < 30: return UNI[n]
    if n < 100: d, u = divmod(n, 10); return DEC[d] + ('' if u == 0 else ' y ' + UNI[u])
    if n == 100: return 'cien'
    c, r = divmod(n, 100); return CEN[c] + ('' if r == 0 else ' ' + _n999(r))

def numero(n):
    n = int(n)
    if n < 1000: return _n999(n)
    if n < 1000000:
        m, r = divmod(n, 1000)
        pre = 'mil' if m == 1 else _n999(m).replace('veintiuno', 'veintiún').replace('uno', 'un') + ' mil'
        return pre + ('' if r == 0 else ' ' + _n999(r))
    m, r = divmod(n, 1000000)
    pre = 'un millón' if m == 1 else numero(m).replace('uno', 'un') + ' millones'
    return pre + ('' if r == 0 else ' ' + numero(r))

LETRA = dict(A='a', B='be', C='ce', D='de', E='e', F='efe', G='ge', H='hache', I='i', J='jota', K='ka', L='ele',
             M='eme', N='ene', O='o', P='pe', Q='cu', R='erre', S='ese', T='te', U='u', V='uve', W='uve doble',
             X='equis', Y='i griega', Z='zeta')

def deletrear(s): return ' '.join(LETRA.get(c, c) for c in s.upper())

def cifra(tok):
    """'0-8-7' -> cero ocho siete ; '1-1' -> uno uno ; '14000' -> catorce mil ; '087' -> cero ocho siete"""
    partes = re.split(r'[-\s]+', tok.strip('-'))
    out = []
    for p in partes:
        if not p: continue
        if len(p) > 1 and p.startswith('0'): out += [UNI[int(c)] for c in p]
        else: out.append(numero(p))
    return ' '.join(out)

def cargar_diccionario(ruta):
    d = []
    if os.path.exists(ruta):
        for l in open(ruta, encoding='utf-8-sig'):
            l = l.rstrip('\n')
            if not l.strip() or l.lstrip().startswith('#') or '=' not in l: continue
            a, b = l.split('=', 1); d.append((a.strip(), b.strip()))
    d.sort(key=lambda x: -len(x[0]))
    return d

def normalizar(texto, dic):
    t = ' ' + texto.strip() + ' '
    for a, b in dic:  # diccionario del usuario primero (palabra completa, respeta mayusculas)
        t = re.sub(r'(?<![\w-])' + re.escape(a) + r'(?![\w-])', ' ' + b + ' ', t)
    # sigla/letras + numero: F-16, SA-6, Su-27, MiG-29, SA-3s, OH-58s
    def sig(m):
        let, num = m.group(1), m.group(2)
        let = deletrear(let) if let.isupper() and len(let) <= 4 else let.lower()
        return f' {let} {cifra(num)} '
    t = re.sub(r'(?<![\w])([A-Za-z]{1,4})-(\d+)s?(?![\w])', sig, t)
    # decimales: Mach 1.7 -> uno coma siete
    t = re.sub(r'(?<![\w.])(\d+)[.,](\d+)(?![\w])', lambda m: f' {numero(m.group(1))} coma {cifra(m.group(2))} ', t)
    # grupos de cifras: 1-1-4, 2 4, 0-8-7, 14000
    t = re.sub(r'(?<![\w])\d+(?:[-\s]\d+)*(?![\w])', lambda m: ' ' + cifra(m.group(0)) + ' ', t)
    # siglas sueltas en mayusculas (2-4 letras): ECM, GBU, QNH
    t = re.sub(r'(?<![\w])([A-Z]{2,4})s?(?![\w])', lambda m: ' ' + deletrear(m.group(1)) + ' ', t)
    t = re.sub(r'\s+', ' ', t.replace('/', ' ')).strip()
    return t

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

def filtro_radio(wav, sr, rms_obj, nivel=1, pre_ms=0, post_ms=0, semilla=0, suavizado=0.0, limpieza=0.0):
    """recorta silencios, pasa a 8 kHz con banda de radio, efectos y volumen.
    suavizado (0-1): quita agudos asperos (corte de 3400 a 2200 Hz); limpieza (0-1): quita ruido/grano.
    pre_ms/post_ms: silencio que se anade (en el Falcon.tlk lo pone montar_tlk.py)"""
    from scipy.signal import butter, sosfiltfilt, resample_poly
    from math import gcd
    a = np.asarray(wav, dtype=np.float64)
    if limpieza > 0: a = limpiar(a, sr, float(limpieza))
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
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--teatro', default='todos', help='Corea, Balcanes, Grecia, Israel o todos')
    ap.add_argument('--cache', default=os.path.join(AQUI, 'cache'), help='salida limpia de XTTS (24 kHz), una por (voz, texto)')
    ap.add_argument('--ref', default=os.path.join(AQUI, 'ref'))
    ap.add_argument('--salida', default=os.path.join(AQUI, 'wav_es'))
    ap.add_argument('--dic', default=os.path.join(AQUI, 'pronunciaciones.txt'))
    ap.add_argument('--igual', default='numeros', choices=['numeros', 'todo', 'nada'])
    ap.add_argument('--voces', default='')
    ap.add_argument('--prueba', type=int, default=0)
    ap.add_argument('--ids', default='', help='solo estos tlkId (separados por comas)')
    ap.add_argument('--forzar', action='store_true', help='vuelve a generar aunque ya exista (con --ids)')
    ap.add_argument('--temperatura', type=float, default=0.65)
    ap.add_argument('--velocidad', type=float, default=1.0, help='1.0 = natural; otros valores ensucian la voz')
    ap.add_argument('--rms', type=float, default=6000, help='volumen (los originales rondan 7000)')
    ap.add_argument('--pausa-inicio', type=int, default=50, help='ms de silencio antes (solo en prueba; en el tlk lo pone montar_tlk.py)')
    ap.add_argument('--pausa-fin', type=int, default=100, help='ms de silencio despues (idem)')
    ap.add_argument('--radio', type=int, default=1, choices=[0, 1, 2], help='efecto de radio: 0 limpio, 1 suave, 2 fuerte')
    ap.add_argument('--suavizado', type=float, default=0.0, help='0-1: quita agudos asperos')
    ap.add_argument('--limpieza', type=float, default=0.0, help='0-1: quita ruido/grano de la voz')
    ap.add_argument('--crudo', action='store_true', help='en prueba, guarda tambien la salida de XTTS sin filtro de radio')
    ap.add_argument('--refiltrar', action='store_true', help='vuelve a aplicar radio/volumen a todo lo generado (sin GPU)')
    ap.add_argument('--comparar', type=int, default=0, help='N frases con 4 ajustes distintos en prueba\\comparar')
    ap.add_argument('--rehacer-latentes', action='store_true')
    ap.add_argument('--rehacer', action='store_true', help='vuelve a generar TODO lo de las voces indicadas con --voces')
    ap.add_argument('--procesos', type=int, default=1, help='procesos de XTTS en paralelo en la GPU (1-4)')
    ap.add_argument('--trabajador', default='', help=argparse.SUPPRESS)   # k/N: uso interno con --procesos
    ap.add_argument('--ajustes-voces', default=os.path.join(AQUI, 'ajustes_voces.json'),
                    help='ajustes guardados por voz en la pestana "Ajuste de voces" (tienen prioridad)')
    ap.add_argument('--solo-texto', action='store_true', help='solo muestra como se normalizan los textos')
    a = ap.parse_args()

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
                   'suavizado': a.suavizado, 'limpieza': a.limpieza}[k]
        x = AJV.get(v, {}).get(k)
        return defecto if x is None else (int(x) if k == 'radio' else float(x))
    teatros = ['Corea', 'Balcanes', 'Grecia', 'Israel'] if a.teatro.lower() == 'todos' else [a.teatro]
    voces = {int(x) for x in a.voces.split(',') if x.strip()} if a.voces else set(range(14))
    ids = {int(x) for x in a.ids.split(',') if x.strip()}

    trabajo = []  # (teatro, tlkId, voz, texto_es, texto_tts)
    filas = []
    for te in teatros:
        for r in list(csv.reader(open(os.path.join(AQUI, f'Lista_{te}.csv'), encoding='utf-8-sig'), delimiter=';'))[1:]:
            filas.append([te] + r)
    for te, t, fr, v, est, en, es in filas:
        v = int(v)
        if ids and int(t) not in ids: continue
        if v not in voces or not es.strip() or es.strip().startswith('('): continue
        if est == 'IGUAL':
            if a.igual == 'nada': continue
            if a.igual == 'numeros' and not re.search(r'\d', es): continue
        elif est != 'TRADUCIR': continue
        tts = normalizar(es, dic)
        if not re.search(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]', tts): continue
        trabajo.append((te, int(t), v, es, tts))

    if a.solo_texto:
        vistos = set()
        for te, t, v, es, tts in trabajo:
            if es != tts and es not in vistos: vistos.add(es); print(f'{es!r:45} -> {tts}')
        print(len(trabajo), 'clips'); return

    if a.comparar:
        a.prueba = a.comparar; a.crudo = True
        largos = [w for w in trabajo if len(w[4]) >= 18] or trabajo
        random.seed(); trabajo = random.sample(largos, min(a.comparar, len(largos)))
        a.salida = os.path.join(AQUI, 'prueba', 'comparar')
        if os.path.isdir(a.salida): shutil.rmtree(a.salida, ignore_errors=True)
    elif a.prueba:
        random.seed(); trabajo = random.sample(trabajo, min(a.prueba, len(trabajo)))
        if not a.comparar:
            a.salida = os.path.join(AQUI, 'prueba')
            if os.path.isdir(a.salida): shutil.rmtree(a.salida, ignore_errors=True)
    def destino(w):
        te, t, v, es, txt = w
        if a.prueba:
            limpio = re.sub(r'[^\w]+', '_', es)[:40]
            return os.path.join(a.salida, f'voz{v:02d}_{t}_{limpio}.wav')
        return os.path.join(a.salida, te, f'{t}.wav')
    def encache(w):
        h = hashlib.md5(w[4].encode('utf-8')).hexdigest()[:16]
        return os.path.join(a.cache, f'voz{w[2]:02d}', h + '.wav')
    if not a.prueba:
        for te in teatros: os.makedirs(os.path.join(a.salida, te), exist_ok=True)
    if a.refiltrar:
        n = 0; hechos_ref = {}
        for w in trabajo:
            c = encache(w)
            if not os.path.exists(c): continue
            if c not in hechos_ref:
                x, sr = leer_wav(c); hechos_ref[c] = filtro_radio(x, sr, par(w[2], 'rms'), par(w[2], 'radio'), semilla=w[1],
                                                           suavizado=par(w[2], 'suavizado'), limpieza=par(w[2], 'limpieza'))
            guardar_wav(destino(w), hechos_ref[c]); n += 1
            if n % 2000 == 0: print(f'  {n} clips...')
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
    def filtrar_a(w, x, sr, ruta, pre=0, post=0):
        guardar_wav(ruta, filtro_radio(x, sr, par(w[2], 'rms'), par(w[2], 'radio'), pre, post, semilla=w[1],
                                       suavizado=par(w[2], 'suavizado'), limpieza=par(w[2], 'limpieza')))
    def de_cache(w):
        c = encache(w)
        if not os.path.exists(c): return False
        try: x, sr = leer_wav(c)
        except Exception: return False
        if sr != 24000: return False            # cache de una version anterior (ya filtrada): se rehace
        filtrar_a(w, x, sr, destino(w)); return True

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
    if not pend: return
    # coordinador: lanza N trabajadores en esta misma consola y espera
    N = max(1, min(4, a.procesos))
    if N > 1 and not a.trabajador and not a.prueba and unicos >= N * 4:
        import subprocess
        print(f'Generando con {N} procesos en paralelo (cada uno carga XTTS en la GPU)...', flush=True)
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
            print('Cortado. Lo generado queda guardado: al relanzar sigue donde iba.'); raise SystemExit(1)
        for f in fichs:
            try: os.remove(f)
            except Exception: pass
        # lo que comparten varios teatros: se rellenan los destinos que falten desde la cache
        faltan = [w for w in trabajo if not os.path.exists(destino(w))]
        hechos_c = sum(1 for w in faltan if de_cache(w))
        mins = (time.time() - t0) / 60
        print(f'Terminado en {mins:.0f} min con {N} procesos' + (f' (+{hechos_c} copiados de la cache)' if hechos_c else '') +
              ('' if all(c == 0 for c in codigos) else '  ·  ALGÚN PROCESO HA FALLADO: revisa los mensajes de arriba'))
        raise SystemExit(0 if all(c == 0 for c in codigos) else 1)

    import torch
    from TTS.api import TTS
    print(f'{etiqueta}Cargando XTTS-v2...', flush=True)
    tts = TTS('tts_models/multilingual/multi-dataset/xtts_v2').to('cuda' if torch.cuda.is_available() else 'cpu')
    modelo = tts.synthesizer.tts_model

    lat = {}
    for v in sorted({w[2] for w in pend}):
        f = os.path.join(a.ref, f'voz{v:02d}.latentes.pt'); wavref = os.path.join(a.ref, f'voz{v:02d}.wav')
        if os.path.exists(f) and not a.rehacer_latentes and os.path.getmtime(f) >= os.path.getmtime(wavref):
            lat[v] = torch.load(f)
        else:
            print(f'{etiqueta}  Estandarizando voz {v:02d} con {os.path.basename(wavref)}...', flush=True)
            g, s = modelo.get_conditioning_latents(audio_path=[wavref], gpt_cond_len=30, max_ref_length=60)
            lat[v] = (g, s)
            tmpf = f + f'.{os.getpid()}.tmp'; torch.save(lat[v], tmpf); os.replace(tmpf, f)   # varios procesos a la vez

    def sintetizar(v, txt, temp, vel):
        g, s = lat[v]
        frase = txt[0].upper() + txt[1:]
        if frase[-1] not in '.?!': frase += '.'
        # XTTS a veces "alucina" en textos muy cortos: se limita la duracion y se reintenta
        maxdur = (0.6 + 0.085 * len(txt)) / vel
        mejor = None
        for intento in range(3):
            out = modelo.inference(frase, 'es', g, s, temperature=temp, speed=vel, enable_text_splitting=False)
            x = np.asarray(out['wav'], dtype=np.float64); dur = len(x) / 24000
            if mejor is None or dur < len(mejor) / 24000: mejor = x
            if dur <= maxdur: break
        return mejor

    if a.comparar:
        os.makedirs(a.salida, exist_ok=True)
        ajustes = [(0.65, 1.0), (0.5, 1.0), (0.8, 1.0), (0.65, 1.1)]
        for k, w in enumerate(pend, 1):
            te, t, v, es, txt = w
            base = f'{k:02d}_voz{v:02d}_' + re.sub(r'[^\w]+', '_', es)[:30]
            for temp, vel in ajustes:
                x = sintetizar(v, txt, temp, vel)
                et = f'temp{temp:.2f}_vel{vel:.1f}'
                if (temp, vel) == ajustes[0]:
                    guardar_wav(os.path.join(a.salida, f'{base}__{et}__0_sin_filtro.wav'), crudo_a_pcm(x), 24000)
                    for nv in (0, 1, 2):
                        guardar_wav(os.path.join(a.salida, f'{base}__{et}__radio{nv}.wav'),
                                    filtro_radio(x, 24000, a.rms, nv, a.pausa_inicio, a.pausa_fin, semilla=t))
                else:
                    guardar_wav(os.path.join(a.salida, f'{base}__{et}__radio{a.radio}.wav'),
                                filtro_radio(x, 24000, a.rms, a.radio, a.pausa_inicio, a.pausa_fin, semilla=t))
            print(f'  {k}/{len(pend)}  [{v:02d}] {es}')
        print('Terminado ->', a.salida); return

    t0 = time.time(); hechos = 0
    pend.sort(key=lambda w: (w[2], w[4]))
    for i, w in enumerate(pend, 1):
        te, t, v, es, txt = w
        if not a.prueba and de_cache(w): continue     # otro teatro ya lo genero en esta pasada
        x = sintetizar(v, txt, par(v, 'temperatura'), par(v, 'velocidad'))
        if a.prueba:
            pi = AJV.get(v, {}).get('pausaInicio'); pf = AJV.get(v, {}).get('pausaFin')
            filtrar_a(w, x, 24000, destino(w), a.pausa_inicio if pi is None else int(pi), a.pausa_fin if pf is None else int(pf))
            if a.crudo: guardar_wav(destino(w)[:-4] + '__sin_filtro.wav', crudo_a_pcm(x), 24000)
        else:
            c = encache(w); os.makedirs(os.path.dirname(c), exist_ok=True)
            guardar_wav(c, crudo_a_pcm(x), 24000)
            filtrar_a(w, x, 24000, destino(w))
        hechos += 1
        if hechos % 25 == 0 or i == len(pend):
            vel = hechos / (time.time() - t0); quedan = (unicos - hechos) / max(vel, 1e-6) / 60
            print(f'{etiqueta}  {hechos}/{unicos}  ({vel:.1f} audios/s, faltan ~{quedan:.0f} min)  ultimo: [{v:02d}] {es}', flush=True)
    print('Terminado ->', a.salida)

if __name__ == '__main__':
    main()
