"""Comprueba si hay una version nueva del motor de voz y lo actualiza sin reinstalar todo.

  python actualizar_motor.py --motor chatterbox --comprobar     (JSON: instalada, ultima, PyTorch...)
  python actualizar_motor.py --motor chatterbox --actualizar    (pip, sin tocar PyTorch)

Se ejecuta con el Python del entorno de ese motor (venv_cb\\ para Chatterbox, venv\\ para XTTS).
Al actualizar, PyTorch se queda como esta (con CUDA): si la version nueva del motor pide otro PyTorch,
pip no instala nada y lo dice; entonces hay que usar «Restaurar entorno».
Los modelos (pesos) no dependen de esto: se descargan de Hugging Face y se ponen al dia solos al cargarlos.
"""
import argparse, json, os, subprocess, sys, tempfile

PAQUETE = {'chatterbox': 'chatterbox-tts', 'xtts': 'coqui-tts'}
CUDA = 'https://download.pytorch.org/whl/cu126'


def instalada(p):
    from importlib import metadata
    try: return metadata.version(p)
    except metadata.PackageNotFoundError: return None


def ultima(p):
    import urllib.request
    with urllib.request.urlopen(f'https://pypi.org/pypi/{p}/json', timeout=20) as r:
        j = json.load(r)
    v = j['info']['version']
    torch = [x for x in (j['info'].get('requires_dist') or []) if x.split(';')[0].strip().lower().startswith(('torch ', 'torch=', 'torch<', 'torch>', 'torch~', 'torch!'))]
    fecha = ''
    try: fecha = j['releases'][v][0]['upload_time'][:10]
    except Exception: pass
    return v, fecha, torch


def mayor(a, b):
    """a > b (versiones tipo 0.1.4 / 0.1.10)"""
    def t(x):
        out = []
        for p in x.replace('-', '.').split('.'):
            n = ''.join(ch for ch in p if ch.isdigit())
            out.append(int(n) if n else 0)
        return out
    return t(a) > t(b)


def tiene_v3():
    try:
        import inspect
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        return 't3_model' in inspect.signature(ChatterboxMultilingualTTS.from_pretrained).parameters
    except Exception:
        return None


def comprobar(motor):
    p = PAQUETE[motor]
    r = {'ok': True, 'motor': motor, 'paquete': p, 'instalada': instalada(p), 'torch': instalada('torch')}
    try:
        r['ultima'], r['fecha'], r['torch_pide'] = ultima(p)
    except Exception as e:
        r.update(ok=False, error=f'No se pudo consultar PyPI (¿sin internet?): {e}')
        return r
    r['desfasada'] = bool(r['instalada'] and mayor(r['ultima'], r['instalada']))
    if motor == 'chatterbox': r['v3'] = tiene_v3()
    return r


def actualizar(motor):
    p = PAQUETE[motor]
    antes = instalada(p); tv = instalada('torch'); ta = instalada('torchaudio')
    print(f'{p}: instalada {antes}; PyTorch {tv} (se queda como esta)')
    if not tv: sys.exit('No hay PyTorch en este entorno: usa «Restaurar entorno».')
    # PyTorch fijo (el de CUDA): si la version nueva pide otro, pip no instala nada
    cons = os.path.join(tempfile.gettempdir(), f'bms_torch_{os.getpid()}.txt')
    with open(cons, 'w') as f:
        f.write(f'torch=={tv}\n' + (f'torchaudio=={ta}\n' if ta else ''))
    cmd = [sys.executable, '-m', 'pip', 'install', '--upgrade', p, '-c', cons, '--extra-index-url', CUDA]
    print('>', ' '.join(cmd), flush=True)
    rc = subprocess.call(cmd)
    os.remove(cons)
    if rc != 0:
        sys.exit(f'\nNo se ha actualizado (pip termino con codigo {rc}). Si la version nueva pide otra version de PyTorch, '
                 'usa «Restaurar entorno» de ese motor. Lo que habia sigue igual.')
    despues = instalada(p)
    try:
        import importlib
        if motor == 'chatterbox': importlib.import_module('chatterbox.mtl_tts')
        else: importlib.import_module('TTS.api')
        import torch
        cuda = torch.cuda.is_available()
    except Exception as e:
        sys.exit(f'\nActualizado a {despues}, pero no se puede cargar: {e}\nUsa «Restaurar entorno» de ese motor.')
    print(f'\n{p}: {antes} -> {despues}' + ('' if antes != despues else ' (ya era la ultima)'))
    print('PyTorch con CUDA: ' + ('si' if cuda else 'NO (revisa el driver de NVIDIA)'))
    if motor == 'chatterbox':
        print('Modelo V3: ' + ('disponible' if tiene_v3() else 'esta version aun no lo tiene: se sigue usando el multilingue'))
    print('Las voces preparadas se rehacen solas si hace falta. Conviene lanzar «Prueba (30)» para comprobar.')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--motor', choices=list(PAQUETE), default='chatterbox')
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--comprobar', action='store_true')
    g.add_argument('--actualizar', action='store_true')
    a = ap.parse_args()
    if a.comprobar: print(json.dumps(comprobar(a.motor), ensure_ascii=False))
    else: actualizar(a.motor)


if __name__ == '__main__':
    main()
