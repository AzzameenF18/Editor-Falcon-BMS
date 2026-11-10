# -*- coding: utf-8 -*-
"""
Monta un Falcon.tlk nuevo: los clips que tengan wav_es\\<tlkId>.wav se codifican en Speex
(8 kHz, calidad 8, igual que el original) y el resto se copian tal cual del Falcon.tlk original.

Necesita ffmpeg con libspeex (build "full" de gyan.dev).

Uso:
  python montar_tlk.py --teatro Corea --tlk "<ruta al Falcon.tlk ORIGINAL en ingles de ese teatro>" [--base "<Falcon.tlk del instalador>"]
  Con --base, los clips sin wav se toman de ese tlk (lo ya traducido no se pierde aunque falte wav_es)
  y solo se recodifican los wav nuevos o cambiados (montado_<Teatro>.json guarda que se monto).
  -> crea Falcon_Corea.tlk con los wav de wav_es\\Corea
"""
import argparse, os, struct, subprocess, sys, tempfile, wave, shutil, csv, json, hashlib
from concurrent.futures import ThreadPoolExecutor

AQUI = os.path.dirname(os.path.abspath(__file__))

def paquetes_ogg(d):
    pk, cur, i = [], b'', 0
    while i < len(d):
        if d[i:i + 4] != b'OggS': raise ValueError('Ogg mal formado')
        ns = d[i + 26]; lac = d[i + 27:i + 27 + ns]; p = i + 27 + ns
        for L in lac:
            cur += d[p:p + L]; p += L
            if L < 255: pk.append(cur); cur = b''
        i = p
    return pk

def codificar(ffmpeg, wavpath, tmpdir, pre_ms=0, post_ms=0):
    w = wave.open(wavpath, 'rb')
    if w.getframerate() != 8000 or w.getnchannels() != 1 or w.getsampwidth() != 2:
        raise ValueError(f'{wavpath}: debe ser 8000 Hz mono 16 bits')
    pcm = w.readframes(w.getnframes()); w.close()
    pcm = b'\0' * (16 * pre_ms) + pcm + b'\0' * (16 * post_ms)    # pausa entre fragmentos
    nsamp = len(pcm) // 2
    npk = max(1, -(-nsamp // 160))
    nsamp = npk * 160
    pcm = pcm.ljust(nsamp * 2, b'\0') + b'\0' * 640          # relleno para que no falte el ultimo frame
    base = os.path.join(tmpdir, os.path.basename(wavpath))
    raw = base + '.raw'; spx = base + '.spx'
    open(raw, 'wb').write(pcm)
    subprocess.run([ffmpeg, '-y', '-loglevel', 'error', '-f', 's16le', '-ar', '8000', '-ac', '1', '-i', raw,
                    '-c:a', 'libspeex', '-cbr_quality', '8', '-frames_per_packet', '1', '-vad', '0', '-dtx', '0',
                    spx], check=True)
    aud = paquetes_ogg(open(spx, 'rb').read())[2:]           # 0 = cabecera Speex, 1 = comentarios
    os.remove(raw); os.remove(spx)
    if len(aud) < npk: aud += [aud[-1]] * (npk - len(aud))
    aud = aud[:npk]
    if any(len(x) > 255 for x in aud): raise ValueError('paquete demasiado grande')
    datos = b''.join(bytes([len(x)]) + x for x in aud)
    return struct.pack('<II', nsamp * 2, len(datos)) + datos

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tlk', required=True, help='Falcon.tlk ORIGINAL en ingles')
    ap.add_argument('--teatro', required=True, help='Corea, Balcanes, Grecia o Israel')
    ap.add_argument('--wav', default='')
    ap.add_argument('--salida', default='')
    ap.add_argument('--ffmpeg', default='ffmpeg')
    ap.add_argument('--hilos', type=int, default=8)
    ap.add_argument('--pausa-inicio', type=int, default=50, help='ms de silencio antes de cada clip en espanol')
    ap.add_argument('--pausa-fin', type=int, default=100, help='ms de silencio despues')
    ap.add_argument('--base', default='', help='Falcon.tlk ya traducido (el del instalador): base para lo que no tenga wav')
    ap.add_argument('--manifiesto', default='')
    a = ap.parse_args()

    ff = shutil.which(a.ffmpeg) or a.ffmpeg
    try:
        enc = subprocess.run([ff, '-hide_banner', '-encoders'], capture_output=True, text=True).stdout
    except FileNotFoundError:
        sys.exit('No encuentro ffmpeg. Pasa la ruta con --ffmpeg "C:\\ffmpeg\\bin\\ffmpeg.exe"')
    if 'libspeex' not in enc:
        sys.exit('Este ffmpeg no tiene libspeex. Usa la build "full" de gyan.dev.')

    a.wav = a.wav or os.path.join(AQUI, 'wav_es', a.teatro)
    a.salida = a.salida or os.path.join(AQUI, f'Falcon_{a.teatro}.tlk')
    b = open(a.tlk, 'rb').read()
    cab = b[:12]; n = (struct.unpack('<I', b[12:16])[0] - 12) // 4
    off = struct.unpack(f'<{n}I', b[12:12 + n * 4])
    lista = os.path.join(AQUI, f'Lista_{a.teatro}.csv')
    if os.path.exists(lista):
        maxid = max(int(l.split(';')[0]) for l in open(lista, encoding='utf-8-sig').readlines()[1:]
                    if l.split(';')[3] != 'ID_INVALIDO')
        if maxid >= n: sys.exit(f'Este Falcon.tlk ({n} clips) no es el de {a.teatro} (la lista llega a {maxid}).')
    if os.path.abspath(a.tlk) == os.path.abspath(a.salida): sys.exit('La salida no puede ser el original.')

    nuevos = {}
    for f in os.listdir(a.wav) if os.path.isdir(a.wav) else []:
        if f.lower().endswith('.wav') and f[:-4].isdigit() and int(f[:-4]) < n:
            nuevos[int(f[:-4])] = os.path.join(a.wav, f)
    print(f'Clips nuevos en espanol: {len(nuevos)} de {n}')
    # silencio antes/despues: el de cada voz (pestana Ajuste de voces) o el general
    voz_de = {}
    lista = os.path.join(AQUI, f'Lista_{a.teatro}.csv')
    if os.path.exists(lista):
        for r in list(csv.reader(open(lista, encoding='utf-8-sig'), delimiter=';'))[1:]:
            if len(r) > 2 and r[0].isdigit(): voz_de[int(r[0])] = int(r[2])
    ajv = {}
    fa = os.path.join(AQUI, 'ajustes_voces.json')
    if os.path.exists(fa):
        try: ajv = {int(k): v for k, v in json.load(open(fa, encoding='utf-8-sig')).items()}
        except Exception as e: print('No se pudo leer ajustes_voces.json:', e)
    def pausas(t):
        x = ajv.get(voz_de.get(t, -1), {})
        pi = x.get('pausaInicio'); pf = x.get('pausaFin')
        return (a.pausa_inicio if pi is None else int(pi)), (a.pausa_fin if pf is None else int(pf))

    def md5f(ruta):
        h = hashlib.md5()
        with open(ruta, 'rb') as f:
            for blq in iter(lambda: f.read(1 << 20), b''): h.update(blq)
        return h.hexdigest()

    # base: el Falcon.tlk traducido que ya esta en el instalador
    base = None; boff = None
    if a.base and os.path.exists(a.base) and os.path.abspath(a.base) != os.path.abspath(a.salida or ''):
        bb = open(a.base, 'rb').read()
        nb = (struct.unpack('<I', bb[12:16])[0] - 12) // 4
        if nb == n: base = bb; boff = struct.unpack(f'<{n}I', bb[12:12 + n * 4])
        else: print(f'Aviso: {a.base} tiene {nb} clips (el original {n}): no se usa como base.')
    a.manifiesto = a.manifiesto or os.path.join(AQUI, f'montado_{a.teatro}.json')
    man = {}
    if base is not None and os.path.exists(a.manifiesto):
        try:
            m = json.load(open(a.manifiesto, encoding='utf-8'))
            if m.get('salida_md5') == hashlib.md5(base).hexdigest(): man = m.get('clips', {})
            else: print('La base no es el ultimo montaje registrado: se recodifican todos los wav.')
        except Exception as e: print('No se pudo leer', a.manifiesto, e)

    def clip_de(buf, offs, t):
        o = offs[t]; raw, comp = struct.unpack('<II', buf[o:o + 8]); return buf[o:o + 8 + comp]

    firmas = {}
    for t, ruta in nuevos.items():
        pi, pf = pausas(t); firmas[t] = md5f(ruta) + f'|{pi}|{pf}'
    reusar = {t for t in nuevos if base is not None and man.get(str(t)) == firmas[t]}
    codif = sorted(t for t in nuevos if t not in reusar)
    print(f'Wav en espanol: {len(nuevos)}  ->  a codificar: {len(codif)}, sin cambios (de la base): {len(reusar)}')

    tmp = tempfile.mkdtemp(prefix='tlk_')
    res = {}
    def tarea(t):
        pi, pf = pausas(t)
        res[t] = codificar(ff, nuevos[t], tmp, pi, pf)
    with ThreadPoolExecutor(a.hilos) as ex:
        for i, _ in enumerate(ex.map(tarea, codif), 1):
            if i % 500 == 0: print(f'  codificados {i}/{len(codif)}')
    shutil.rmtree(tmp, ignore_errors=True)

    cuerpo, offs, pos = [], [], 12 + n * 4
    de_base = 0
    for t in range(n):
        if t in res: c = res[t]
        elif base is not None and (t in reusar or t not in nuevos):
            c = clip_de(base, boff, t)
            if t not in nuevos and c != clip_de(b, off, t): de_base += 1
        else: c = clip_de(b, off, t)
        offs.append(pos); cuerpo.append(c); pos += len(c)
    datos = cab + struct.pack(f'<{n}I', *offs) + b''.join(cuerpo)
    tmpf = a.salida + '.tmp'
    with open(tmpf, 'wb') as f: f.write(datos)
    os.replace(tmpf, a.salida)
    json.dump({'salida_md5': hashlib.md5(datos).hexdigest(), 'clips': {str(t): firmas[t] for t in nuevos}},
              open(a.manifiesto, 'w', encoding='utf-8'))
    if de_base: print(f'Clips traducidos tomados de la base (sin wav): {de_base}')
    print(f'Hecho: {a.salida} ({pos/1e6:.1f} MB, original {len(b)/1e6:.1f} MB)')

if __name__ == '__main__':
    main()
