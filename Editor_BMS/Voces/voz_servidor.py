# -*- coding: utf-8 -*-
"""
Servidor local de pruebas de voz para la pestana "Ajuste de voces" del Editor BMS.
Carga el modelo (Chatterbox o XTTS-v2, motores.py) una sola vez y sintetiza frases de prueba al momento.
Solo escucha en 127.0.0.1 y exige el token que le pasa el editor. Se cierra solo tras 20 min sin uso.

  python voz_servidor.py --puerto 8899 --token XXXX [--motor chatterbox|xtts] [--variante v3|es-es]
"""
import argparse, io, json, os, sys, threading, time, wave, traceback
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import generar_voces as G
import motores as M

ESTADO = {'listo': False, 'error': '', 'dispositivo': '', 'fase': 'arrancando'}
MODELO = {}
LAT = {}
CANDADO = threading.Lock()
ULTIMO = [time.time()]

def cargar():
    try:
        ESTADO['fase'] = 'cargando ' + ('XTTS-v2' if ARGS.motor == 'xtts' else 'Chatterbox')
        import torch
        MODELO['m'] = M.cargar(ARGS.motor, ARGS.variante, aviso=lambda t: print(t, flush=True))
        ESTADO['dispositivo'] = torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'
        ESTADO['motor'] = ARGS.motor + (' ' + ARGS.variante if ARGS.motor == 'chatterbox' else '')
        ESTADO['listo'] = True; ESTADO['fase'] = 'listo'
        print('Listo en', ESTADO['dispositivo'], '-', ESTADO['motor'], flush=True)
    except BaseException as e:
        ESTADO['error'] = str(e); ESTADO['fase'] = 'error'
        traceback.print_exc()

REF = os.path.join(AQUI, 'ref')

def a_wav(pcm, sr):
    b = io.BytesIO(); w = wave.open(b, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(np.asarray(pcm, dtype='<i2').tobytes()); w.close(); return b.getvalue()

LECS = {}
def lectura_de(ruta, idv):
    """lectura (numeros, letras...) del idioma.json del idioma; recargada si cambia"""
    if not ruta or not os.path.exists(ruta): return G.LEC.Lectura(None, idv)
    m = os.path.getmtime(ruta)
    if (ruta, idv) not in LECS or LECS[(ruta, idv)][0] != m: LECS[(ruta, idv)] = (m, G.LEC.cargar(ruta, idv))
    return LECS[(ruta, idv)][1]

def sintetizar(p):
    idv = str(p.get('idioma') or G.LEC.idioma_voz(str(p.get('lectura') or ''), 'es'))
    lec = lectura_de(str(p.get('lectura') or ''), idv)
    dic = str(p.get('dic') or '')
    v = int(p.get('voz', 0)); texto = str(p.get('texto', '')).strip() or (lec.cfg['frasePrueba'] + ' ' + str(v))
    pv = M.params(ARGS.motor, float(p.get('temperatura', 0.65)), float(p.get('velocidad', 1.0)),
                  float(p.get('cbTemperatura', 0.8)), float(p.get('expresividad', 0.5)), float(p.get('cfg', 0.5)))
    rms = float(p.get('rms', 6000)); radio = int(p.get('radio', 1))
    suav = float(p.get('suavizado', 0)); limp = float(p.get('limpieza', 0))
    txt = lec.normalizar(texto, G.cargar_diccionario(dic))
    frase = txt[0].upper() + txt[1:]
    if frase[-1] not in '.?!': frase += '.'
    x = MODELO['m'].decir(v, frase, idv, REF, partir=True, **pv)
    if p.get('sin_filtro'): return a_wav(G.crudo_a_pcm(x), 24000)
    pre = int(p.get('pausaInicio', 25)); post = int(p.get('pausaFin', 15))
    return a_wav(G.filtro_radio(x, 24000, rms, radio, pre, post, semilla=v, suavizado=suav, limpieza=limp, esperado=G.esperado_de(txt, M.ritmo(ARGS.motor, pv))), 8000)

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _cab(self, code, tipo='application/json', largo=None):
        self.send_response(code)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Type', tipo)
        if largo is not None: self.send_header('Content-Length', str(largo))
        self.end_headers()
    def _json(self, code, obj):
        b = json.dumps(obj).encode('utf-8'); self._cab(code, 'application/json', len(b)); self.wfile.write(b)
    def _ok_token(self):
        from urllib.parse import urlparse, parse_qs
        q = parse_qs(urlparse(self.path).query)
        return q.get('k', [''])[0] == ARGS.token
    def do_OPTIONS(self):
        self._cab(204, 'text/plain', 0)
    def do_GET(self):
        if not self._ok_token(): return self._json(403, {'error': 'token'})
        ULTIMO[0] = time.time()
        if self.path.startswith('/estado'): return self._json(200, ESTADO)
        if self.path.startswith('/salir'):
            self._json(200, {'ok': True}); threading.Thread(target=lambda: (time.sleep(0.3), os._exit(0))).start(); return
        self._json(404, {'error': 'no existe'})
    def do_POST(self):
        if not self._ok_token(): return self._json(403, {'error': 'token'})
        ULTIMO[0] = time.time()
        if not self.path.startswith('/probar'): return self._json(404, {'error': 'no existe'})
        if not ESTADO['listo']: return self._json(503, {'error': 'el modelo aun se esta cargando'})
        try:
            n = int(self.headers.get('Content-Length', 0)); p = json.loads(self.rfile.read(n) or b'{}')
            t0 = time.time()
            with CANDADO: datos = sintetizar(p)
            print(f"voz {int(p.get('voz', 0)):02d}  {time.time() - t0:.1f} s  {str(p.get('texto', ''))[:60]}", flush=True)
            self._cab(200, 'audio/wav', len(datos)); self.wfile.write(datos)
        except Exception as e:
            traceback.print_exc(); self._json(500, {'error': str(e)})
        ULTIMO[0] = time.time()

def vigilante():
    while True:
        time.sleep(30)
        if time.time() - ULTIMO[0] > 20 * 60:
            print('20 minutos sin uso: se cierra.', flush=True); os._exit(0)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--puerto', type=int, default=8899)
    ap.add_argument('--token', required=True)
    ap.add_argument('--motor', default='chatterbox', choices=list(M.MOTORES))
    ap.add_argument('--variante', default='v3', choices=['v3', 'es-es'])
    ARGS = ap.parse_args()
    srv = ThreadingHTTPServer(('127.0.0.1', ARGS.puerto), H)
    print(f'Servidor de pruebas de voz en 127.0.0.1:{ARGS.puerto} (se cierra solo tras 20 min sin uso)', flush=True)
    threading.Thread(target=cargar, daemon=True).start()
    threading.Thread(target=vigilante, daemon=True).start()
    srv.serve_forever()
