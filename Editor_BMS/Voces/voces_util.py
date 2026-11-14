# -*- coding: utf-8 -*-
"""
Utilidad para el Editor BMS (pestana Voces):
  python voces_util.py extraer --tlk Falcon.tlk --id 1234 --salida clip.wav [--ffmpeg ffmpeg.exe]
     extrae un clip de un Falcon.tlk a .wav (8 kHz mono)
  python voces_util.py candidatos --voz 4 --tlk Falcon.tlk      (frases originales para la referencia, JSON)
  python voces_util.py referencia --voz 4 --tlk Falcon.tlk --ids 10,20,30 | --auto | --inicial
     rehace ref\\vozNN.wav (la primera vez guarda la de serie como vozNN_inicial.wav)
  python voces_util.py limpiar-ref [--voz N] [--quitar]
     limpia ref\\vozNN.wav (o las 14): quita el ruido de fondo y repara la saturacion de los clips de radio;
     la version sin limpiar queda en vozNN_sinlimpiar.wav (--quitar la vuelve a poner)
  python voces_util.py mapa --teatro Corea --fragfile FragFile.xml --f4talk F4Talk.csv --tlk Falcon.tlk [--origen "huella"]
     crea Mapas\\Mapa_Corea.csv (clips del Falcon.tlk: tlkId, fragmento, voz e ingles) desde los ficheros
     del juego: FragFile.xml (que voz dice cada fragmento y en que clip), F4Talk.csv en ingles y la cabecera
     del .tlk (los tlkId que no existen quedan como ID_INVALIDO)
  python voces_util.py lista --teatro Corea --f4talk Corea=F4Talk_KOREA.csv [--salida lista.csv]
     la tabla de clips del teatro (tlkId;frag;voz;estado;ingles;traduccion), hecha al momento con el mapa de
     clips del kit (Mapas\\Mapa_<Teatro>.csv) y los textos de su F4Talk.csv. No se guarda en ningun sitio:
     los textos estan solo en el F4Talk.csv (sin --f4talk del teatro, salen en ingles)
  python voces_util.py generados --teatro Corea --f4talk Corea=F4Talk_KOREA.csv --wav <carpeta wav>
     tlkId con audio generado de su texto actual (JSON)
  python voces_util.py pretraducir --teatro Malvinas --f4talk <json de los F4Talk> --salida pretraducido.json [--respaldo dir]
     rellena lo que sigue en ingles en el F4Talk del teatro con la traduccion que ese mismo ingles tiene en los otros
     teatros (antes guarda una copia para deshacer; en --salida queda lo rellenado, para revisarlo)
  python voces_util.py texto --teatro Corea --id 1234 --es "nuevo texto" --f4talk Corea=... --f4talk Balcanes=...
     cambia el texto de ese clip en su F4Talk.csv y, en los demas teatros, el de los clips con el mismo
     fragmento y voz que tenian el mismo texto; borra sus wav para que se vuelvan a generar
  python voces_util.py normalizar --lectura idioma.json --dic pronunciaciones.txt --es "F-16 a 0-8-7"
     como se leeria el texto (numeros, siglas...) en ese idioma (JSON)
Las carpetas del idioma son Idiomas\\<CODIGO> del kit; --wav la cambia.
El clip se envuelve en un Ogg Speex y lo decodifica ffmpeg.
"""
import argparse, struct, subprocess, sys, os, csv, json

def _crc_tabla():
    t = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else (r << 1)
        t.append(r & 0xFFFFFFFF)
    return t
_T = _crc_tabla()

def _crc(d):
    c = 0
    for b in d: c = ((c << 8) & 0xFFFFFFFF) ^ _T[((c >> 24) & 0xFF) ^ b]
    return c

def _pagina(paquetes, tipo, granulo, serie, sec):
    lac = b''
    for p in paquetes:
        n = len(p)
        lac += b'\xff' * (n // 255) + bytes([n % 255])
    cab = b'OggS' + bytes([0, tipo]) + struct.pack('<qIII', granulo, serie, sec, 0) + bytes([len(lac)]) + lac
    pag = bytearray(cab + b''.join(paquetes))
    struct.pack_into('<I', pag, 22, _crc(pag))
    return bytes(pag)

def clip_a_ogg(datos):
    """datos = paquetes [len][frame] del tlk -> fichero Ogg Speex (8 kHz, 1 frame por paquete)"""
    frames, i = [], 0
    while i < len(datos):
        n = datos[i]; frames.append(datos[i + 1:i + 1 + n]); i += 1 + n
    h = (b'Speex   ' + b'1.2'.ljust(20, b'\0') +
         struct.pack('<11i', 1, 80, 8000, 0, 4, 1, -1, 160, 0, 1, 0) + struct.pack('<2i', 0, 0))
    vendor = b'Falcon BMS'
    com = struct.pack('<I', len(vendor)) + vendor + struct.pack('<I', 0)
    serie = 0x46344254
    out = [_pagina([h], 2, 0, serie, 0), _pagina([com], 0, 0, serie, 1)]
    sec = 2
    for k in range(0, len(frames), 50):
        trozo = frames[k:k + 50]
        ult = k + 50 >= len(frames)
        out.append(_pagina(trozo, 4 if ult else 0, (k + len(trozo)) * 160, serie, sec)); sec += 1
    return b''.join(out)

def leer_clip(tlk, t):
    with open(tlk, 'rb') as f:
        cab = f.read(16)
        n = (struct.unpack('<I', cab[12:16])[0] - 12) // 4
        if t < 0 or t >= n: raise SystemExit(f'id fuera de rango (0-{n - 1})')
        f.seek(12 + 4 * t); o = struct.unpack('<I', f.read(4))[0]
        f.seek(o); raw, comp = struct.unpack('<II', f.read(8))
        return raw, f.read(comp)

AQUI = os.path.dirname(os.path.abspath(__file__))
TEATROS = ['Corea', 'Balcanes', 'Grecia', 'Israel']   # los de siempre; los demas salen de los mapas del kit
def teatros_kit():
    """teatros con mapa de clips en el kit (Corea primero), incluidos los Add-On nuevos"""
    hay = set()
    for d in (os.path.join(AQUI, 'Mapas'), AQUI):
        if os.path.isdir(d): hay |= {f[5:-4] for f in os.listdir(d) if f.startswith('Mapa_') and f.endswith('.csv')}
    return [t for t in TEATROS if t in hay] + sorted(t for t in hay if t not in TEATROS)

def estado(en, es):
    if not es.strip(): return 'SIN_TEXTO_ES'
    return 'IGUAL' if es.strip() == en.strip() else 'TRADUCIR'

def actualizar_f4talk(ruta, celdas, respaldo=None, cp='cp1252'):
    """celdas: [(frag, voz, texto)] -> cambia esas celdas del F4Talk.csv (mismo formato y codificacion)"""
    import io, shutil
    datos = open(ruta, 'rb').read()
    try: txt = datos.decode('utf-8-sig'); enc = 'utf-8-sig' if datos.startswith(b'\xef\xbb\xbf') else 'utf-8'
    except UnicodeDecodeError: txt = datos.decode(cp, errors='replace'); enc = cp
    nl = '\r\n' if '\r\n' in txt else '\n'
    filas = list(csv.reader(io.StringIO(txt)))
    pos = {}
    for i, r in enumerate(filas):
        if len(r) == 1 and ',' in r[0]: filas[i] = r = next(csv.reader([r[0]]))
        if r and r[0].strip().isdigit(): pos[int(r[0])] = i
    n = 0
    for frag, voz, texto in celdas:
        i = pos.get(int(frag))
        if i is None: continue
        r = filas[i]; c = 2 + int(voz)
        while len(r) <= c: r.append('')
        if r[c] != texto: r[c] = texto; n += 1
    if not n: return 0
    if respaldo:
        os.makedirs(os.path.dirname(respaldo), exist_ok=True)
        if not os.path.exists(respaldo): shutil.copyfile(ruta, respaldo)
    b = io.StringIO(); csv.writer(b, lineterminator=nl).writerows(filas)
    out = b.getvalue().encode('utf-8' if enc.startswith('utf-8') else enc, errors='replace')
    if enc == 'utf-8-sig': out = b'\xef\xbb\xbf' + out
    tmp = ruta + '.tmp'; open(tmp, 'wb').write(out); os.replace(tmp, ruta)
    return n

def pretraducir(teatro, f4, salida, cp='cp1252', respaldo=None):
    """rellena lo que sigue en ingles en el F4Talk.csv del teatro con la traduccion que ese mismo ingles (exacto, sin
    contar espacios) tiene en los otros teatros. Antes guarda una copia del F4Talk (para deshacer) y deja en `salida`
    (json) lo rellenado, para revisarlo en la pestana Voces"""
    import shutil, time
    if teatro not in f4: raise SystemExit('el teatro no tiene F4Talk.csv en el instalador')
    limpio = lambda x: ' '.join((x or '').split())
    mem = {}       # ingles -> {traduccion: [veces, teatros]}
    for te in teatros_kit():
        if te == teatro or te not in f4: continue
        for t, fr, v, est, en, tx in filas_teatro(te, f4[te], cp):
            k = limpio(en)
            if est != 'TRADUCIR' or not tx or limpio(tx) == k: continue
            d = mem.setdefault(k, {}); x = d.setdefault(tx, [0, set()]); x[0] += 1; x[1].add(te)
    celdas, info, vistos = [], [], set()
    for t, fr, v, est, en, tx in filas_teatro(teatro, f4[teatro], cp):
        k = limpio(en)
        if est == 'ID_INVALIDO' or (fr, v) in vistos or not any(ch.isalpha() for ch in k): continue
        if tx and limpio(tx) != k: continue                # ya traducido
        d = mem.get(k)
        if not d: continue
        vistos.add((fr, v))
        ops = sorted(d.items(), key=lambda z: -z[1][0])
        celdas.append((int(fr), int(v), ops[0][0]))
        info.append({'frag': int(fr), 'voz': int(v), 'en': en, 'es': ops[0][0], 'de': sorted(ops[0][1][1]),
                     'dudoso': [[x, n[0]] for x, n in ops] if len(ops) > 1 else None})
    copia = None
    if celdas:
        if respaldo:
            os.makedirs(respaldo, exist_ok=True)
            copia = os.path.join(respaldo, f'{os.path.splitext(os.path.basename(f4[teatro]))[0]}_antes_de_pretraducir_{time.strftime("%Y%m%d_%H%M%S")}.csv')
            shutil.copyfile(f4[teatro], copia)
        actualizar_f4talk(f4[teatro], celdas, None, cp)
    r = {'ok': True, 'teatro': teatro, 'f4talk': f4[teatro], 'rellenados': len(celdas),
         'dudosos': sum(1 for x in info if x['dudoso']), 'copia': copia, 'celdas': info, 'fecha': time.strftime('%d/%m %H:%M')}
    if salida and celdas:
        # se suma a lo pretraducido antes (si se pretraduce dos veces), conservando la copia mas antigua
        try: ant = json.load(open(salida, encoding='utf-8'))
        except Exception: ant = None
        if ant and ant.get('copia') and os.path.exists(ant['copia']): r['copia'] = ant['copia']
        if ant: r['celdas'] = [c for c in ant.get('celdas', []) if (c['frag'], c['voz']) not in {(x['frag'], x['voz']) for x in info}] + info
        json.dump(r, open(salida, 'w', encoding='utf-8'), ensure_ascii=False)
    return r

def dirs_wav(dwav):
    """carpeta de wav del motor actual y las de los otros motores del mismo idioma (wav, wav_cb...)"""
    if not dwav: return []
    base = os.path.dirname(os.path.normpath(dwav)); out = [dwav]
    if os.path.isdir(base):
        for d in os.listdir(base):
            p = os.path.join(base, d)
            if (d == 'wav' or d.startswith('wav_')) and os.path.isdir(p) and os.path.normpath(p) != os.path.normpath(dwav): out.append(p)
    return out

def f4_pares(lista):
    """['Corea=ruta', ...] o un .json {"Corea": ruta, ...} (el que pasa el editor) -> {'Corea': ruta}.
    Las rutas que no existen se avisan por stderr y no cuentan"""
    pares = []
    for x in lista or []:
        x = x.strip().strip('"')
        if x.lower().endswith('.json') and os.path.isfile(x):
            try: pares += list(json.load(open(x, encoding='utf-8-sig')).items())
            except Exception as e: print(f'No se pudo leer {x}: {e}', file=sys.stderr)
        else:
            te, _, ruta = x.partition('=')
            pares.append((te, ruta.strip().strip('"')))
    out = {}
    for te, ruta in pares:
        if te and ruta and os.path.isfile(ruta): out[te] = ruta
        elif te: print(f'F4Talk de {te} no encontrado: {ruta!r}', file=sys.stderr)
    # los que falten se buscan en la carpeta Ficheros del idioma (--ficheros): F4Talk\F4Talk_<TEATRO>.csv
    if FICHEROS and os.path.isdir(os.path.join(FICHEROS, 'F4Talk')):
        d = os.path.join(FICHEROS, 'F4Talk')
        norm = lambda x: ''.join(ch for ch in x.upper() if ch.isalnum())
        hay = {norm(f[7:-4]): os.path.join(d, f) for f in os.listdir(d) if f.lower().startswith('f4talk_') and f.lower().endswith('.csv')}
        alias = {'COREA': ['KOREA', 'COREA'], 'BALCANES': ['BALCANES', 'BALKANS'], 'GRECIA': ['GRECIA', 'HELLAS'], 'COREATVT': ['TVT', 'KOREATVT']}
        for te in teatros_kit():
            if te in out: continue
            for c in alias.get(norm(te), []) + [norm(te)]:
                if c in hay: out[te] = hay[c]; break
    return out

FICHEROS = None      # carpeta Ficheros del idioma en el instalador (--ficheros)

def huella_texto(tx):
    import hashlib
    return hashlib.md5(' '.join((tx or '').split()).encode('utf-8')).hexdigest()[:12]

# Registro de con que texto se genero cada audio: <wav>\<Teatro>\_textos.json {tlkId: huella del texto}.
# Si el texto del F4Talk cambia (tambien fuera del editor), el audio de ese clip ya no vale.
def leer_registro(dteatro):
    try: return json.load(open(os.path.join(dteatro, '_textos.json'), encoding='utf-8'))
    except Exception: return {}

def guardar_registro(dteatro, reg):
    os.makedirs(dteatro, exist_ok=True)
    p = os.path.join(dteatro, '_textos.json'); tmp = p + f'.{os.getpid()}.tmp'
    with open(tmp, 'w', encoding='utf-8') as f: json.dump(reg, f, separators=(',', ':'), sort_keys=True)
    for _ in range(20):
        try: os.replace(tmp, p); return
        except PermissionError:
            import time; time.sleep(0.2)

def generados(teatro, filas, dwav):
    """tlkId con wav cuyo texto registrado es el actual (o sin registro: de antes de que existiera)"""
    d = os.path.join(dwav, teatro)
    if not os.path.isdir(d): return []
    reg = leer_registro(d); txt = {r[0]: r[5] for r in filas}
    out = []
    for f in os.listdir(d):
        if not f.lower().endswith('.wav') or not f[:-4].isdigit(): continue
        t = f[:-4]
        if t in reg and t in txt and reg[t] != huella_texto(txt[t]): continue
        out.append(int(t))
    return sorted(out)

def cambiar_texto(teatro, tid, nuevo, f4, dwav, cp='cp1252', respaldo=None):
    """cambia el texto del clip en su F4Talk.csv y, en los demas teatros, el de los clips con el mismo fragmento
    y voz que tenian el mismo texto; borra sus wav (de todos los motores)"""
    nuevo = ' '.join(nuevo.split())
    if teatro not in teatros_kit(): raise SystemExit('teatro sin mapa de clips')
    filas = {te: filas_teatro(te, f4.get(te), cp) for te in teatros_kit()}
    fila = next((r for r in filas[teatro] if r[0] == str(tid)), None)
    if not fila: raise SystemExit('id no encontrado')
    if fila[3] == 'ID_INVALIDO': raise SystemExit('id no valido')
    if teatro not in f4: raise SystemExit('este teatro no tiene F4Talk.csv en el instalador')
    frag, voz, viejo = fila[1], fila[2], fila[5]
    cambios, res = [], []
    for te, fs in filas.items():
        if te not in f4: continue
        celdas = set()
        for r in fs:
            if r[1] == frag and r[2] == voz and r[3] != 'ID_INVALIDO' and (r[5] == viejo or (te == teatro and r[0] == str(tid))):
                if r[5] == nuevo: continue
                celdas.add((int(r[1]), int(r[2])))
                for d in dirs_wav(dwav):      # el clip viejo, de todos los motores
                    w = os.path.join(d, te, r[0] + '.wav')
                    if os.path.exists(w): os.remove(w)
                cambios.append({'t': te, 'id': int(r[0]), 'estado': estado(r[4], nuevo), 'frag': int(r[1]), 'voz': int(r[2])})
        if celdas:
            resp = os.path.join(respaldo, te, os.path.basename(f4[te])) if respaldo else None
            try: res.append({'t': te, 'ruta': f4[te], 'celdas': actualizar_f4talk(f4[te], [(a, b, nuevo) for a, b in celdas], resp, cp)})
            except Exception as e: res.append({'t': te, 'ruta': f4[te], 'error': str(e)})
    return cambios, res

def leer_f4talk(ruta, cp='cp1252'):
    """F4Talk.csv -> {fragmento: fila}"""
    import io
    datos = open(ruta, 'rb').read()
    try: txt = datos.decode('utf-8-sig')
    except UnicodeDecodeError: txt = datos.decode(cp, errors='replace')
    R = {}
    for r in csv.reader(io.StringIO(txt)):
        if len(r) == 1 and ',' in r[0]: r = next(csv.reader([r[0]]))
        if r and r[0].strip().isdigit(): R[int(r[0])] = r
    return R

def mapa_de(teatro):
    """Mapa de clips del teatro (tlkId;frag;voz;estado;ingles): Mapas\\Mapa_<Teatro>.csv del kit"""
    for p in (os.path.join(AQUI, 'Mapas', f'Mapa_{teatro}.csv'), os.path.join(AQUI, f'Mapa_{teatro}.csv')):
        if os.path.exists(p): return p
    raise SystemExit(f'No esta Mapa_{teatro}.csv en el kit de voces (Mapas)')

def _parece_traducido(textos):
    """el F4Talk/mapa en ingles no tiene letras fuera de ASCII; una traduccion (a, e, n con tilde...) si"""
    import re
    t = [x for x in textos if x and x.strip()]
    return bool(t) and sum(1 for x in t if re.search(r'[^\x00-\x7f]', x)) > len(t) * 0.01

def construir_mapa(teatro, fragfile, f4talk, tlk, cp='cp1252', origen=None):
    """Mapas\\Mapa_<Teatro>.csv desde FragFile.xml + F4Talk.csv (ingles) + cabecera del .tlk"""
    import xml.etree.ElementTree as ET
    with open(tlk, 'rb') as f: n = (struct.unpack('<I', f.read(16)[12:16])[0] - 12) // 4
    EN = leer_f4talk(f4talk, cp)
    if _parece_traducido([c for r in EN.values() for c in r[2:16]]):
        raise SystemExit(f'{f4talk} no esta en ingles (es una traduccion): no sirve para el mapa de clips; se deja el que hay')
    at = lambda e, k: next((v for a, v in e.attrib.items() if a.lower() == k.lower()), None)
    filas, vistos = [], set()
    for fe in ET.parse(fragfile).getroot().iter():
        if fe.tag.lower() != 'frag' or at(fe, 'id') is None: continue
        fr = int(at(fe, 'id'))
        for sp in fe.iter():
            if sp.tag.lower() != 'speaker' or at(sp, 'tlkId') is None: continue
            v, t = int(at(sp, 'voice')), int(at(sp, 'tlkId'))
            if t in vistos: continue
            vistos.add(t); r = EN.get(fr)
            en = (r[2 + v] if r and 2 + v < len(r) else '').strip()
            filas.append([t, fr, v, 'ID_INVALIDO' if t >= n else '', en])
    if not filas: raise SystemExit('FragFile.xml sin fragmentos: ' + fragfile)
    filas.sort()
    d = os.path.join(AQUI, 'Mapas'); os.makedirs(d, exist_ok=True)
    p = os.path.join(d, f'Mapa_{teatro}.csv'); tmp = p + '.tmp'
    with open(tmp, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';'); w.writerow(['tlkId', 'frag', 'voz', 'estado', 'ingles']); w.writerows(filas)
    os.replace(tmp, p)
    if origen is not None:
        with open(os.path.join(d, f'Mapa_{teatro}.origen.txt'), 'w', encoding='utf-8') as f: f.write(origen)
    return {'teatro': teatro, 'mapa': p, 'clips': len(filas), 'invalidos': sum(1 for x in filas if x[3]), 'tlk': n}

def filas_teatro(teatro, f4talk=None, cp='cp1252'):
    """clips del teatro: [tlkId, frag, voz, estado, ingles, traduccion] (todo texto), del mapa del kit y del
    F4Talk.csv del idioma (sin el, la traduccion es el ingles)"""
    base = list(csv.reader(open(mapa_de(teatro), encoding='utf-8-sig', newline=''), delimiter=';'))
    if _parece_traducido([r[4] for r in base[1:] if len(r) > 4]):
        raise SystemExit(f'El mapa de clips {mapa_de(teatro)} tiene la columna en ingles traducida (se hizo con un F4Talk traducido): '
                         'sustituyelo por el del kit (Voces\\Mapas) y borra su .origen.txt')
    F = leer_f4talk(f4talk, cp) if f4talk and os.path.exists(f4talk) else None
    out = []
    for r in base[1:]:
        if len(r) < 5: continue
        t, fr, v, est, en = r[:5]
        if est == 'ID_INVALIDO': tx = ''
        else:
            if F is None: tx = ' '.join(en.split())
            else:
                fila = F.get(int(fr)); c = 2 + int(v)
                tx = ' '.join((fila[c] if fila and c < len(fila) else '').split())
                if tx.startswith('Placeholder'): tx = ''
            est = estado(en, tx)
        out.append([t, fr, v, est, en, tx])
    return out

def decodificar(tlk, t, ffmpeg):
    import numpy as np
    raw, datos = leer_clip(tlk, t)
    r = subprocess.run([ffmpeg, '-loglevel', 'error', '-f', 'ogg', '-i', 'pipe:0', '-f', 's16le', '-ar', '8000', '-ac', '1', 'pipe:1'],
                       input=clip_a_ogg(datos), capture_output=True)
    return np.frombuffer(r.stdout, '<i2').astype(np.float64)

def _filas_voz(v):
    p = mapa_de('Corea')
    vistos = set()
    for r in list(csv.reader(open(p, encoding='utf-8-sig', newline=''), delimiter=';'))[1:]:
        if len(r) >= 5 and r[2] == str(v) and r[3] != 'ID_INVALIDO' and len(r[4].split()) >= 3 and r[4] not in vistos:
            vistos.add(r[4]); yield int(r[0]), r[4]

# ---------- limpieza de las referencias ----------
# Los clips originales son audio de radio: soplido/estatica de fondo (unos -27 dB bajo la voz) y saturacion en
# bastantes frases. Si la referencia los lleva, el motor los toma como parte de la voz y luego el efecto de radio
# se aplica encima (doble). Limpiar = reparar los picos recortados y quitar el ruido de fondo (sin tocar la banda).
def _tramos(a, minimo=500):
    """trozos de voz de la referencia (separados por huecos de ceros de >= minimo muestras)"""
    import numpy as np
    z = np.concatenate([[0], (a == 0).astype(int), [0]]); d = np.diff(z)
    ini, fin = np.where(d == 1)[0], np.where(d == -1)[0]
    cortes = [(i, f) for i, f in zip(ini, fin) if f - i >= minimo]
    out, pos = [], 0
    for i, f in cortes:
        if i > pos: out.append((pos, i))
        pos = f
    if pos < len(a): out.append((pos, len(a)))
    return out

def reparar_saturacion(x, iters=60, corte=0.85):
    """picos recortados: al descomprimir, el speex satura en +-32767 (muestras sueltas o en grupos). En la
    referencia cada frase tiene su propio volumen, asi que el nivel de recorte es el maximo del trozo cuando
    varias muestras lo tocan. Se reconstruyen con Papoulis-Gerchberg: limitando banda (corte = fraccion de
    Nyquist) y sin bajar nunca del nivel recortado"""
    import numpy as np
    x = x.astype(np.float64); m = np.abs(x).max()
    if m <= 0: return x, 0
    c = np.abs(x) >= 0.995 * m
    if c.sum() < 2: return x, 0           # un solo pico maximo: natural, no saturacion
    nivel = 0.995 * m; idx = np.where(c)[0]
    grupos, a0, p = [], idx[0], idx[0]
    for k in idx[1:]:
        if k - p > 16: grupos.append((a0, p)); a0 = k
        p = k
    grupos.append((a0, p))
    y = x.copy()
    for a0, p in grupos:
        a, b = max(0, a0 - 48), min(len(x), p + 49)
        seg = x[a:b]; cm = c[a:b]; sg = np.sign(seg); N = len(seg)
        alta = np.fft.rfftfreq(N) > 0.5 * corte
        z = seg.copy()
        for _ in range(iters):
            Z = np.fft.rfft(z); Z[alta] = 0; z2 = np.fft.irfft(Z, N)
            z = np.where(cm, np.where(sg * z2 > nivel, z2, sg * nivel), seg)
        y[a:b] = z
    return y, int(c.sum())

def quitar_ruido(tramos, n=256, h=64, fuerza=1.0):
    """reduccion de ruido espectral: el perfil del ruido sale de los momentos mas callados de las frases"""
    import numpy as np
    w = np.sqrt(np.hanning(n + 1)[:-1])
    def stft(x):
        x = np.concatenate([np.zeros(n), x, np.zeros(n)])
        k = 1 + (len(x) - n) // h
        return np.fft.rfft(np.stack([x[i * h:i * h + n] * w for i in range(k)]), axis=1), len(x)
    S = [stft(x) for x in tramos]
    P = np.concatenate([np.abs(F) ** 2 for F, _ in S]); e = P.sum(1)
    ok = e > e.max() * 1e-7
    if ok.sum() < 20: return tramos
    ruido = np.median(P[ok][e[ok] <= np.percentile(e[ok], 12)], axis=0) + 1e-9
    suelo = 10 ** (-20 / 20)
    out = []
    for (F, L), x in zip(S, tramos):
        G = np.maximum(1 - 1.8 * fuerza * ruido / (np.abs(F) ** 2 + 1e-9), suelo)
        # suavizado de la ganancia (evita el "ruido musical")
        Gp = np.pad(G, 1, mode='edge')
        G = sum(Gp[1 + i:1 + i + G.shape[0], 1 + j:1 + j + G.shape[1]] for i in (-1, 0, 1) for j in (-1, 0, 1)) / 9
        y = np.zeros(L); nrm = np.zeros(L); fr = np.fft.irfft(F * G, n=n, axis=1)
        for i in range(fr.shape[0]): y[i * h:i * h + n] += fr[i] * w; nrm[i * h:i * h + n] += w ** 2
        y = y / np.maximum(nrm, 1e-6)
        out.append(y[n:n + len(x)])
    return out

def limpiar_audio(a):
    import numpy as np
    a = a.astype(np.float64); tr = _tramos(a)
    if not tr: return a, {'saturadas': 0, 'ruido_db': None}
    trozos, sat = [], 0
    for i, f in tr:
        y, k = reparar_saturacion(a[i:f]); trozos.append(y); sat += k
    limpios = quitar_ruido(trozos)
    b = np.zeros_like(a)
    for (i, f), y in zip(tr, limpios):
        y = y / np.sqrt((y ** 2).mean() + 1e-9) * 3500      # mismo volumen por frase que crear_referencia
        pk = np.abs(y).max()
        if pk > 30000: y *= 30000 / pk                       # los picos reconstruidos no pueden volver a saturar
        b[i:f] = y
    def suelo(x):
        fr = x[:len(x) // 160 * 160].reshape(-1, 160); e = np.sqrt((fr ** 2).mean(1)); e = e[e > 0]
        return 20 * np.log10((np.percentile(e, 10) + 1) / (np.percentile(e, 95) + 1)) if len(e) else 0.0
    antes = np.mean([suelo(a[i:f]) for i, f in tr]); despues = np.mean([suelo(b[i:f]) for i, f in tr])
    return np.clip(b, -32000, 32000), {'saturadas': int(sat), 'ruido_antes_db': round(float(antes), 1), 'ruido_despues_db': round(float(despues), 1)}

def _leer_wav(p):
    import numpy as np, wave
    w = wave.open(p); a = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(np.float64); sr = w.getframerate(); w.close()
    return a, sr

def _escribir_wav(p, a, sr):
    import numpy as np, wave
    tmp = p + '.tmp'; w = wave.open(tmp, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(np.round(a).astype('<i2').tobytes()); w.close(); os.replace(tmp, p)

def _meta_ref(v, **cambios):
    p = os.path.join(AQUI, 'ref', f'voz{v:02d}.json')
    try: j = json.load(open(p, encoding='utf-8'))
    except Exception: j = {}
    j.update(cambios); json.dump(j, open(p, 'w', encoding='utf-8'))

def limpiar_referencia(v, quitar=False):
    """limpia ref\\vozNN.wav (la version sin limpiar queda en vozNN_sinlimpiar.wav); quitar=True la deshace"""
    import shutil
    d = os.path.join(AQUI, 'ref'); wr = os.path.join(d, f'voz{v:02d}.wav'); sin = os.path.join(d, f'voz{v:02d}_sinlimpiar.wav')
    if quitar:
        if os.path.exists(sin):
            os.replace(sin, wr); os.utime(wr, None)     # fecha nueva: las huellas de los motores se rehacen
        _meta_ref(v, limpia=False)
        return {'ok': True, 'limpia': False}
    if not os.path.exists(sin): shutil.copyfile(wr, sin)
    a, sr = _leer_wav(sin)          # siempre desde la version sin limpiar (no se limpia dos veces)
    b, info = limpiar_audio(a)
    _escribir_wav(wr, b, sr); _meta_ref(v, limpia=True)
    return dict({'ok': True, 'limpia': True}, **info)

def ref_limpia(v):
    return os.path.exists(os.path.join(AQUI, 'ref', f'voz{v:02d}_sinlimpiar.wav'))

def _ref_ids(v):
    p = os.path.join(AQUI, 'ref', f'voz{v:02d}.json')
    try: return set(json.load(open(p, encoding='utf-8')).get('ids', []))
    except Exception: return set()

def candidatos(tlk, v, ffmpeg, n=45):
    import numpy as np
    with open(tlk, 'rb') as f:
        cab = f.read(16); tot = (struct.unpack('<I', cab[12:16])[0] - 12) // 4
        f.seek(12); off = struct.unpack(f'<{tot}I', f.read(4 * tot))
        lst = []
        for t, en in _filas_voz(v):
            if t >= tot: continue
            f.seek(off[t]); raw = struct.unpack('<I', f.read(4))[0]
            lst.append((raw / 16000, t, en))
    lst.sort(reverse=True)
    usados = _ref_ids(v)
    sel = [x for x in lst if x[1] in usados] + [x for x in lst if x[1] not in usados][:n]
    out = []
    for dur, t, en in sel:
        a = decodificar(tlk, t, ffmpeg)
        if not len(a): continue
        out.append({'id': t, 'en': en, 'dur': round(len(a) / 8000, 2), 'sat': round(float(np.mean(np.abs(a) > 30000) * 100), 2),
                    'usado': t in usados})
    return out

def crear_referencia(tlk, v, ffmpeg, ids=None, auto=False, inicial=False, limpiar=False):
    import numpy as np, wave, shutil
    d = os.path.join(AQUI, 'ref'); os.makedirs(d, exist_ok=True)
    wr = os.path.join(d, f'voz{v:02d}.wav'); ini = os.path.join(d, f'voz{v:02d}_inicial.wav')
    lat = os.path.join(d, f'voz{v:02d}.latentes.pt'); js = os.path.join(d, f'voz{v:02d}.json')
    sin = os.path.join(d, f'voz{v:02d}_sinlimpiar.wav')
    # la de serie se guarda la primera vez (sin limpiar, si estaba limpiada)
    if not os.path.exists(ini):
        if os.path.exists(sin): shutil.copyfile(sin, ini)
        elif os.path.exists(wr): shutil.copyfile(wr, ini)
    if inicial:
        if not os.path.exists(ini): raise SystemExit('no hay referencia inicial guardada')
        shutil.copyfile(ini, wr)
        if os.path.exists(sin): os.remove(sin)
        for f in (lat, js):
            if os.path.exists(f): os.remove(f)
        return {'ok': True, 'segundos': None, 'frases': None}
    if auto:
        c = sorted(candidatos(tlk, v, ffmpeg, 80), key=lambda x: -x['dur'])
        ids = [x['id'] for x in c if x['sat'] < 0.3]
    trozos, tot, usados = [], 0.0, []
    for t in ids:
        a = decodificar(tlk, int(t), ffmpeg)
        if not len(a) or np.abs(a).max() < 1500: continue
        m = np.where(np.abs(a) > np.abs(a).max() * 0.03)[0]; a = a[max(0, m[0] - 80):m[-1] + 160]
        trozos += [a / np.sqrt((a ** 2).mean()) * 3500, np.zeros(2000)]; tot += len(a) / 8000; usados.append(int(t))
        if tot >= 30: break
    if tot < 6: raise SystemExit(f'Muy poca voz para la referencia ({tot:.1f} s). Marca mas frases (minimo ~6 s, ideal 15-30 s).')
    out = np.clip(np.concatenate(trozos), -32000, 32000).astype('<i2')
    if os.path.exists(sin): os.remove(sin)      # referencia nueva: la limpieza anterior ya no vale
    w = wave.open(wr, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(out.tobytes()); w.close()
    # sin referencia de serie (paquete sin ref\): la primera que se crea pasa a ser la de serie
    if not os.path.exists(ini): shutil.copyfile(wr, ini)
    if os.path.exists(lat): os.remove(lat)
    json.dump({'ids': usados}, open(js, 'w', encoding='utf-8'))
    r = {'ok': True, 'segundos': round(tot, 1), 'frases': len(usados), 'limpia': False}
    if limpiar: r.update(limpiar_referencia(v)); r['ok'] = True
    return r

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('orden', choices=['extraer', 'texto', 'candidatos', 'referencia', 'limpiar-ref', 'lista', 'generados', 'mapa', 'normalizar', 'pretraducir'])
    ap.add_argument('--idioma', default='ES', help='codigo del idioma: carpetas por defecto en Idiomas\\<CODIGO> del kit')
    ap.add_argument('--wav', default='', help='carpeta de los wav generados del idioma (por teatro)')
    ap.add_argument('--codificacion', default='cp1252', help='codificacion del F4Talk.csv si no es UTF-8')
    ap.add_argument('--lectura', default='')
    ap.add_argument('--dic', default='')
    ap.add_argument('--tlk')
    ap.add_argument('--id', type=int)
    ap.add_argument('--voz', type=int)
    ap.add_argument('--ids', default='')
    ap.add_argument('--auto', action='store_true')
    ap.add_argument('--inicial', action='store_true')
    ap.add_argument('--limpiar', action='store_true', help='referencia: quitar ruido de fondo y reparar saturacion')
    ap.add_argument('--quitar', action='store_true', help='limpiar-ref: volver a la referencia sin limpiar')
    ap.add_argument('--salida')
    ap.add_argument('--teatro')
    ap.add_argument('--es', default=None)
    ap.add_argument('--es-fichero', default=None, help='lee el texto nuevo de este fichero (UTF-8)')
    ap.add_argument('--f4talk', action='append', default=[], help='Teatro=ruta del F4Talk.csv que se actualiza tambien (subtitulos)')
    ap.add_argument('--ficheros', default=None, help='carpeta Ficheros del idioma en el instalador (busca ahi F4Talk\\F4Talk_<TEATRO>.csv)')
    ap.add_argument('--respaldo', default=None, help='carpeta donde se guarda una copia del F4Talk.csv antes del primer cambio')
    ap.add_argument('--ffmpeg', default='ffmpeg')
    ap.add_argument('--fragfile', default=None)
    ap.add_argument('--origen', default=None, help='huella de los ficheros de origen (se guarda junto al mapa)')
    a = ap.parse_args()
    if a.codificacion.isdigit(): a.codificacion = 'cp' + a.codificacion
    global FICHEROS; FICHEROS = a.ficheros
    base = os.path.join(AQUI, 'Idiomas', a.idioma.upper())
    a.wav = a.wav or os.path.join(base, 'wav')
    if a.orden == 'mapa':
        if not (a.fragfile and a.f4talk and a.tlk and a.teatro): raise SystemExit('faltan --teatro, --fragfile, --f4talk o --tlk')
        print(json.dumps({'ok': True, 'resultado': construir_mapa(a.teatro, a.fragfile, a.f4talk[0], a.tlk, a.codificacion, a.origen)})); return
    if a.orden == 'pretraducir':
        r = pretraducir(a.teatro, f4_pares(a.f4talk), a.salida, a.codificacion, a.respaldo)
        r = dict(r); r['celdas'] = len(r['celdas']); print(json.dumps(r, ensure_ascii=False)); return
    if a.orden in ('lista', 'generados'):
        f4 = f4_pares(a.f4talk)
        filas = filas_teatro(a.teatro, f4.get(a.teatro), a.codificacion)
        if a.orden == 'generados': print(json.dumps(generados(a.teatro, filas, a.wav))); return
        cab = ['tlkId', 'frag', 'voz', 'estado', 'ingles', 'traduccion']
        if a.salida:
            tmp = a.salida + '.tmp'
            with open(tmp, 'w', encoding='utf-8-sig', newline='') as f: csv.writer(f, delimiter=';').writerows([cab] + filas)
            os.replace(tmp, a.salida)
            cuenta = {}
            for r in filas: cuenta[r[3]] = cuenta.get(r[3], 0) + 1
            print(json.dumps({'ok': True, 'teatro': a.teatro, 'f4talk': f4.get(a.teatro), 'estados': cuenta}))
        else:
            w = csv.writer(sys.stdout, delimiter=';', lineterminator='\n'); w.writerows([cab] + filas)
        return
    if a.orden == 'normalizar':
        sys.path.insert(0, AQUI)
        import lectura as LEC
        if a.es_fichero: a.es = open(a.es_fichero, encoding='utf-8-sig').read()
        L = LEC.cargar(a.lectura); dic = LEC.cargar_diccionario(a.dic)   # sin "voz" en el json: plantilla es
        print(json.dumps({'ok': True, 'lineas': [{'texto': x, 'lectura': L.normalizar(x, dic)} for x in (a.es or '').splitlines() if x.strip()]}))
        return
    if a.orden == 'candidatos':
        print(json.dumps({'ok': True, 'candidatos': candidatos(a.tlk, a.voz, a.ffmpeg), 'limpia': ref_limpia(a.voz)})); return
    if a.orden == 'limpiar-ref':
        vs = range(14) if a.voz is None else [a.voz]
        print(json.dumps({'ok': True, 'voces': {str(v): limpiar_referencia(v, a.quitar) for v in vs}})); return
    if a.orden == 'referencia':
        ids = [int(x) for x in a.ids.split(',') if x.strip()]
        print(json.dumps(crear_referencia(a.tlk, a.voz, a.ffmpeg, ids, a.auto, a.inicial, a.limpiar))); return
    if a.orden == 'texto':
        if a.es_fichero: a.es = open(a.es_fichero, encoding='utf-8-sig').read()
        nuevo = ' '.join((a.es or '').split())
        cambios, f4 = cambiar_texto(a.teatro, a.id, nuevo, f4_pares(a.f4talk), a.wav, a.codificacion, a.respaldo)
        print(json.dumps({'ok': True, 'cambios': cambios, 'f4talk': f4}))
        return
    raw, datos = leer_clip(a.tlk, a.id)
    ogg = clip_a_ogg(datos)
    r = subprocess.run([a.ffmpeg, '-y', '-loglevel', 'error', '-f', 'ogg', '-i', 'pipe:0',
                        '-ar', '8000', '-ac', '1', '-c:a', 'pcm_s16le', a.salida], input=ogg)
    sys.exit(r.returncode)

if __name__ == '__main__':
    main()
