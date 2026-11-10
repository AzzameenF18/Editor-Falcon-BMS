# -*- coding: utf-8 -*-
"""
Utilidad para el Editor BMS (pestana Voces): extrae un clip de un Falcon.tlk a .wav (8 kHz mono).
  python voces_util.py extraer --tlk Falcon.tlk --id 1234 --salida clip.wav [--ffmpeg ffmpeg.exe]
  python voces_util.py candidatos --voz 4 --tlk Falcon.tlk      (frases originales para la referencia, JSON)
  python voces_util.py referencia --voz 4 --tlk Falcon.tlk --ids 10,20,30 | --auto | --inicial
     rehace ref\vozNN.wav (la primera vez guarda la de serie como vozNN_inicial.wav)
  python voces_util.py texto --teatro Corea --id 1234 --es "nuevo texto"
     cambia el texto en espanol de ese clip y, en los 4 teatros, el de los clips con el mismo
     fragmento y voz que tenian el mismo texto; borra sus wav para que se vuelvan a generar.
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
TEATROS = ['Corea', 'Balcanes', 'Grecia', 'Israel']

def estado(en, es):
    if not es.strip(): return 'SIN_TEXTO_ES'
    return 'IGUAL' if es.strip() == en.strip() else 'TRADUCIR'

def actualizar_f4talk(ruta, celdas, respaldo=None):
    """celdas: [(frag, voz, texto)] -> cambia esas celdas del F4Talk.csv (mismo formato y codificacion)"""
    import io, shutil
    datos = open(ruta, 'rb').read()
    try: txt = datos.decode('utf-8-sig'); enc = 'utf-8-sig' if datos.startswith(b'\xef\xbb\xbf') else 'utf-8'
    except UnicodeDecodeError: txt = datos.decode('cp1252'); enc = 'cp1252'
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
    out = b.getvalue().encode('cp1252' if enc == 'cp1252' else 'utf-8', errors='replace')
    if enc == 'utf-8-sig': out = b'\xef\xbb\xbf' + out
    tmp = ruta + '.tmp'; open(tmp, 'wb').write(out); os.replace(tmp, ruta)
    return n

def cambiar_texto(teatro, tid, nuevo):
    nuevo = ' '.join(nuevo.split())
    listas = {}
    for te in TEATROS:
        p = os.path.join(AQUI, f'Lista_{te}.csv')
        if os.path.exists(p): listas[te] = list(csv.reader(open(p, encoding='utf-8-sig', newline=''), delimiter=';'))
    if teatro not in listas: raise SystemExit('lista no encontrada')
    fila = next((r for r in listas[teatro][1:] if r[0] == str(tid)), None)
    if not fila: raise SystemExit('id no encontrado')
    if fila[3] == 'ID_INVALIDO': raise SystemExit('id no valido')
    frag, voz, viejo = fila[1], fila[2], fila[5]
    cambios = []
    for te, filas in listas.items():
        mod = False
        for r in filas[1:]:
            if r[1] == frag and r[2] == voz and r[3] != 'ID_INVALIDO' and (r[5] == viejo or (te == teatro and r[0] == str(tid))):
                if r[5] == nuevo: continue
                r[5] = nuevo; r[3] = estado(r[4], nuevo); mod = True
                w = os.path.join(AQUI, 'wav_es', te, r[0] + '.wav')
                if os.path.exists(w): os.remove(w)
                cambios.append({'t': te, 'id': int(r[0]), 'estado': r[3], 'frag': int(r[1]), 'voz': int(r[2])})
        if mod:
            p = os.path.join(AQUI, f'Lista_{te}.csv'); tmp = p + '.tmp'
            with open(tmp, 'w', encoding='utf-8-sig', newline='') as f: csv.writer(f, delimiter=';').writerows(filas)
            os.replace(tmp, p)
    return cambios

def decodificar(tlk, t, ffmpeg):
    import numpy as np
    raw, datos = leer_clip(tlk, t)
    r = subprocess.run([ffmpeg, '-loglevel', 'error', '-f', 'ogg', '-i', 'pipe:0', '-f', 's16le', '-ar', '8000', '-ac', '1', 'pipe:1'],
                       input=clip_a_ogg(datos), capture_output=True)
    return np.frombuffer(r.stdout, '<i2').astype(np.float64)

def _filas_voz(v):
    p = os.path.join(AQUI, 'Lista_Corea.csv')
    vistos = set()
    for r in list(csv.reader(open(p, encoding='utf-8-sig', newline=''), delimiter=';'))[1:]:
        if len(r) >= 6 and r[2] == str(v) and r[3] != 'ID_INVALIDO' and len(r[4].split()) >= 3 and r[4] not in vistos:
            vistos.add(r[4]); yield int(r[0]), r[4]

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

def crear_referencia(tlk, v, ffmpeg, ids=None, auto=False, inicial=False):
    import numpy as np, wave, shutil
    d = os.path.join(AQUI, 'ref'); wr = os.path.join(d, f'voz{v:02d}.wav'); ini = os.path.join(d, f'voz{v:02d}_inicial.wav')
    if os.path.exists(wr) and not os.path.exists(ini): shutil.copyfile(wr, ini)
    lat = os.path.join(d, f'voz{v:02d}.latentes.pt'); js = os.path.join(d, f'voz{v:02d}.json')
    if inicial:
        if not os.path.exists(ini): raise SystemExit('no hay referencia inicial guardada')
        shutil.copyfile(ini, wr)
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
    w = wave.open(wr, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(out.tobytes()); w.close()
    if os.path.exists(lat): os.remove(lat)
    json.dump({'ids': usados}, open(js, 'w', encoding='utf-8'))
    return {'ok': True, 'segundos': round(tot, 1), 'frases': len(usados)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('orden', choices=['extraer', 'texto', 'candidatos', 'referencia'])
    ap.add_argument('--tlk')
    ap.add_argument('--id', type=int)
    ap.add_argument('--voz', type=int)
    ap.add_argument('--ids', default='')
    ap.add_argument('--auto', action='store_true')
    ap.add_argument('--inicial', action='store_true')
    ap.add_argument('--salida')
    ap.add_argument('--teatro')
    ap.add_argument('--es', default=None)
    ap.add_argument('--es-fichero', default=None, help='lee el texto nuevo de este fichero (UTF-8)')
    ap.add_argument('--f4talk', action='append', default=[], help='Teatro=ruta del F4Talk.csv que se actualiza tambien (subtitulos)')
    ap.add_argument('--respaldo', default=None, help='carpeta donde se guarda una copia del F4Talk.csv antes del primer cambio')
    ap.add_argument('--ffmpeg', default='ffmpeg')
    a = ap.parse_args()
    if a.orden == 'candidatos':
        print(json.dumps({'ok': True, 'candidatos': candidatos(a.tlk, a.voz, a.ffmpeg)})); return
    if a.orden == 'referencia':
        ids = [int(x) for x in a.ids.split(',') if x.strip()]
        print(json.dumps(crear_referencia(a.tlk, a.voz, a.ffmpeg, ids, a.auto, a.inicial))); return
    if a.orden == 'texto':
        if a.es_fichero: a.es = open(a.es_fichero, encoding='utf-8-sig').read()
        nuevo = ' '.join((a.es or '').split())
        cambios = cambiar_texto(a.teatro, a.id, nuevo)
        f4 = []
        for x in a.f4talk:
            te, _, ruta = x.partition('=')
            celdas = [(c['frag'], c['voz'], nuevo) for c in cambios if c['t'] == te]
            if not celdas or not os.path.exists(ruta): continue
            resp = os.path.join(a.respaldo, te, os.path.basename(ruta)) if a.respaldo else None
            try: f4.append({'t': te, 'ruta': ruta, 'celdas': actualizar_f4talk(ruta, celdas, resp)})
            except Exception as e: f4.append({'t': te, 'ruta': ruta, 'error': str(e)})
        print(json.dumps({'ok': True, 'cambios': cambios, 'f4talk': f4}))
        return
    raw, datos = leer_clip(a.tlk, a.id)
    ogg = clip_a_ogg(datos)
    r = subprocess.run([a.ffmpeg, '-y', '-loglevel', 'error', '-f', 'ogg', '-i', 'pipe:0',
                        '-ar', '8000', '-ac', '1', '-c:a', 'pcm_s16le', a.salida], input=ogg)
    sys.exit(r.returncode)

if __name__ == '__main__':
    main()
