# -*- coding: utf-8 -*-
"""
Servidor local de pruebas de voz para la pestana "Ajuste de voces" del Editor BMS.
Carga XTTS-v2 una sola vez y sintetiza frases de prueba al momento.
Solo escucha en 127.0.0.1 y exige el token que le pasa el editor. Se cierra solo tras 20 min sin uso.

  python voz_servidor.py --puerto 8899 --token XXXX
"""
import argparse, io, json, os, sys, threading, time, wave, traceback
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import generar_voces as G

ESTADO = {'listo': False, 'error': '', 'dispositivo': '', 'fase': 'arrancando'}
MODELO = {}
LAT = {}
CANDADO = threading.Lock()
ULTIMO = [time.time()]

def cargar():
    try:
        ESTADO['fase'] = 'cargando XTTS-v2'
        import torch
        from TTS.api import TTS
        dev = 'cuda' if torch.cuda.is_available() else 'cpu'
        tts = TTS('tts_models/multilingual/multi-dataset/xtts_v2').to(dev)
        MODELO['m'] = tts.synthesizer.tts_model; MODELO['torch'] = torch
        ESTADO['dispositivo'] = torch.cuda.get_device_name(0) if dev == 'cuda' else 'CPU'
        ESTADO['listo'] = True; ESTADO['fase'] = 'listo'
        print('Listo en', ESTADO['dispositivo'], flush=True)
    except Exception as e:
        ESTADO['error'] = str(e); ESTADO['fase'] = 'error'
        traceback.print_exc()

def latentes(v):
    torch = MODELO['torch']; m = MODELO['m']
    f = os.path.join(AQUI, 'ref', f'voz{v:02d}.latentes.pt'); wr = os.path.join(AQUI, 'ref', f'voz{v:02d}.wav')
    marca = os.path.getmtime(wr)
    if v in LAT and LAT[v][0] == marca: return LAT[v][1]
    if os.path.exists(f) and os.path.getmtime(f) >= marca:
        LAT[v] = (marca, torch.load(f))
    else:
        print(f'Estandarizando voz {v:02d}...', flush=True)
        g, s = m.get_conditioning_latents(audio_path=[wr], gpt_cond_len=30, max_ref_length=60)
        torch.save((g, s), f); LAT[v] = (marca, (g, s))
    return LAT[v][1]

def a_wav(pcm, sr):
    b = io.BytesIO(); w = wave.open(b, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(np.asarray(pcm, dtype='<i2').tobytes()); w.close(); return b.getvalue()

def sintetizar(p):
    v = int(p.get('voz', 0)); texto = str(p.get('texto', '')).strip() or 'Esto es una prueba de audio.'
    temp = float(p.get('temperatura', 0.65)); vel = float(p.get('velocidad', 1.0))
    rms = float(p.get('rms', 6000)); radio = int(p.get('radio', 1))
    suav = float(p.get('suavizado', 0)); limp = float(p.get('limpieza', 0))
    txt = G.normalizar(texto, G.cargar_diccionario(os.path.join(AQUI, 'pronunciaciones.txt')))
    frase = txt[0].upper() + txt[1:]
    if frase[-1] not in '.?!': frase += '.'
    g, s = latentes(v)
    out = MODELO['m'].inference(frase, 'es', g, s, temperature=temp, speed=vel, enable_text_splitting=True)
    x = np.asarray(out['wav'], dtype=np.float64)
    if p.get('sin_filtro'): return a_wav(G.crudo_a_pcm(x), 24000)
    pre = int(p.get('pausaInicio', 50)); post = int(p.get('pausaFin', 100))
    return a_wav(G.filtro_radio(x, 24000, rms, radio, pre, post, semilla=v, suavizado=suav, limpieza=limp), 8000)

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
    ARGS = ap.parse_args()
    srv = ThreadingHTTPServer(('127.0.0.1', ARGS.puerto), H)
    print(f'Servidor de pruebas de voz en 127.0.0.1:{ARGS.puerto} (se cierra solo tras 20 min sin uso)', flush=True)
    threading.Thread(target=cargar, daemon=True).start()
    threading.Thread(target=vigilante, daemon=True).start()
    srv.serve_forever()
