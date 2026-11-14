# -*- coding: utf-8 -*-
"""
Motores de voz del kit (los usan generar_voces.py y voz_servidor.py):

  chatterbox  Chatterbox Multilingual (Resemble AI), licencia MIT. Por defecto.
              Variante 'v3' (multilingue) o 'es-es' (afinado para espanol de Espana).
              Se instala en Voces\\venv_cb (PyTorch 2.6, chatterbox-tts).
  xtts        XTTS-v2 (Coqui), licencia CPML (uso no comercial). Se instala en Voces\\venv.

Los dos clonan cada una de las 14 voces desde ref\\vozNN.wav y devuelven audio mono a 24 kHz (float).
Lo que cada voz necesita del modelo se guarda junto a su referencia (vozNN.latentes.pt para XTTS,
vozNN.chatterbox.pt para Chatterbox) y se rehace si la referencia cambia.
"""
import os, time, logging, warnings
# consola limpia: sin barras de progreso por frase ("Sampling: ...") ni avisos internos de las librerias
# (la barra de descarga del modelo la muestra Preparar_voces, que no usa este modulo)
os.environ.setdefault('TQDM_DISABLE', '1')
os.environ.setdefault('TRANSFORMERS_VERBOSITY', 'error')
os.environ.setdefault('HF_HUB_DISABLE_PROGRESS_BARS', '1')
warnings.filterwarnings('ignore', category=FutureWarning)
warnings.filterwarnings('ignore', category=UserWarning)
for _n in ('chatterbox', 'huggingface_hub', 'transformers', 'diffusers'):
    logging.getLogger(_n).setLevel(logging.ERROR)
import numpy as np

MOTORES = ('chatterbox', 'xtts')
SR = 24000
IDIOMAS_CB = {'ar', 'da', 'de', 'el', 'en', 'es', 'fi', 'fr', 'he', 'hi', 'it', 'ja', 'ko', 'ms', 'nl', 'no',
              'pl', 'pt', 'ru', 'sv', 'sw', 'tr', 'zh'}

def _dispositivo(torch):
    return 'cuda' if torch.cuda.is_available() else 'cpu'

def _guardar_atomico(guardar, f):
    """guarda en un temporal y lo pone en su sitio. En Windows os.replace falla (acceso denegado) si otro
    proceso tiene el fichero abierto en ese momento: se reintenta y, si sigue ocupado, se deja el del otro
    proceso (es lo mismo, sale de la misma referencia) y esta copia solo se usa en memoria"""
    tmp = f + f'.{os.getpid()}.tmp'; guardar(tmp)
    for _ in range(40):
        try: os.replace(tmp, f); return True
        except PermissionError: time.sleep(0.25)
    try: os.remove(tmp)
    except OSError: pass
    return False

def _cargar_o_hacer(f, wr, rehacer, cargar, hacer, aviso, v):
    """lo de una voz (latentes / condicionales): del fichero si esta al dia; si no, lo hace UN proceso
    (cerrojo vozNN.*.pt.lock) y los demas esperan a que lo guarde y lo cargan, en vez de hacerlo los 4 a la vez"""
    marca = os.path.getmtime(wr)
    def al_dia():
        if rehacer or not os.path.exists(f) or os.path.getmtime(f) < marca: return None
        for _ in range(3):
            try: return cargar(f)
            except Exception: time.sleep(0.5)       # a medio escribir por otro proceso
        return None
    x = al_dia()
    if x is not None: return x
    cerrojo = f + '.lock'; mio = False; avisado = False
    for _ in range(600):                              # hasta ~5 min esperando a otro proceso
        try:
            os.close(os.open(cerrojo, os.O_CREAT | os.O_EXCL | os.O_WRONLY)); mio = True; break
        except FileExistsError:
            if not avisado:
                aviso(f'  Voz {v:02d}: esperando a que otro proceso la prepare (o a que caduque el cerrojo {os.path.basename(cerrojo)})...'); avisado = True
            try:
                if time.time() - os.path.getmtime(cerrojo) > 300: os.remove(cerrojo); continue   # cerrojo huerfano
            except OSError: pass
            time.sleep(0.5)
            if not rehacer:
                x = al_dia()
                if x is not None: return x
    try:
        if not rehacer:
            x = al_dia()                              # lo ha hecho otro mientras se esperaba
            if x is not None: return x
        aviso(f'  Estandarizando voz {v:02d} con {os.path.basename(wr)}...')
        x = hacer(); _guardar_atomico(lambda t: guardar_de(x, t), f)
        return x
    finally:
        if mio:
            try: os.remove(cerrojo)
            except OSError: pass

def guardar_de(x, ruta):
    if hasattr(x, 'save'): x.save(ruta)
    else:
        import torch; torch.save(x, ruta)

class XTTS:
    nombre = 'xtts'
    def __init__(self, variante=None, aviso=print):
        import torch
        from TTS.api import TTS
        self.torch = torch; self.aviso = aviso
        aviso('Cargando XTTS-v2...')
        self.m = TTS('tts_models/multilingual/multi-dataset/xtts_v2').to(_dispositivo(torch)).synthesizer.tts_model
        self.lat = {}

    def voz(self, v, refdir, rehacer=False):
        torch = self.torch
        f = os.path.join(refdir, f'voz{v:02d}.latentes.pt'); wr = os.path.join(refdir, f'voz{v:02d}.wav')
        marca = os.path.getmtime(wr)
        if not rehacer and v in self.lat and self.lat[v][0] == marca: return self.lat[v][1]
        x = _cargar_o_hacer(f, wr, rehacer, torch.load,
                            lambda: self.m.get_conditioning_latents(audio_path=[wr], gpt_cond_len=30, max_ref_length=60),
                            self.aviso, v)
        self.lat[v] = (marca, x)
        return x

    def decir(self, v, frase, idioma, refdir, temperatura=0.65, velocidad=1.0, partir=False, **_):
        g, s = self.voz(v, refdir)
        out = self.m.inference(frase, idioma, g, s, temperature=temperatura, speed=velocidad, enable_text_splitting=partir)
        return np.asarray(out['wav'], dtype=np.float64)

def _parchear_alineador():
    """Chatterbox multilingue: su vigilante de alineacion (corta repeticiones al final) falla con frases muy cortas
    ("9-5", "8-4": IndexError en max() de una matriz vacia) y tumba el proceso. Si falla, ese paso se deja tal cual."""
    try:
        from chatterbox.models.t3.inference import alignment_stream_analyzer as asa
    except Exception:
        return
    cls = getattr(asa, 'AlignmentStreamAnalyzer', None)
    if cls is None or getattr(cls.step, '_bms', False): return
    orig = cls.step
    def step(self, logits, *args, **kw):
        try:
            return orig(self, logits, *args, **kw)
        except (IndexError, RuntimeError):
            # Solo pasa con el texto ya dicho entero (self.complete). Sin el vigilante el modelo seguiria hablando hasta
            # el maximo de tokens (frases de 40 s y tres reintentos: muy lento), asi que se hace lo que haria el:
            # dejar un respiro y cerrar la frase (unos 8 pasos ~ 0,3 s despues de terminar el texto)
            try:
                if getattr(self, 'curr_frame_pos', None) is not None: self.curr_frame_pos += 1
                if getattr(self, 'complete', False) and getattr(self, 'eos_idx', None) is not None:
                    self._bms_tras = getattr(self, '_bms_tras', 0) + 1
                    if self._bms_tras >= 8:
                        import torch
                        logits = -(2 ** 15) * torch.ones_like(logits)
                        logits[..., self.eos_idx] = 2 ** 15
            except Exception:
                pass
            return logits
    step._bms = True
    cls.step = step

class Chatterbox:
    nombre = 'chatterbox'
    def __init__(self, variante='v3', aviso=print):
        import torch
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        _parchear_alineador()
        self.torch = torch; self.aviso = aviso
        dev = _dispositivo(torch)
        aviso('Cargando Chatterbox Multilingual...')
        import inspect
        if 't3_model' in inspect.signature(ChatterboxMultilingualTTS.from_pretrained).parameters:
            m = ChatterboxMultilingualTTS.from_pretrained(device=dev, t3_model='v3')
        else:      # versiones de chatterbox-tts sin V3
            aviso('  (esta version de chatterbox-tts no tiene V3: se usa su modelo multilingue)')
            m = ChatterboxMultilingualTTS.from_pretrained(device=dev)
        if variante == 'es-es': self._afinado(m, 'ResembleAI/Chatterbox-Multilingual-es-es', 't3_es_es.safetensors', dev)
        self.m = m; self.dev = dev; self.sr = int(getattr(m, 'sr', SR)); self.conds = {}

    def _afinado(self, m, repo, fich, dev):
        """modelo afinado para un idioma: misma arquitectura que el multilingue, se cambian los pesos de T3"""
        try:
            from huggingface_hub import hf_hub_download
            from safetensors.torch import load_file
            sd = load_file(hf_hub_download(repo, fich)); propias = set(m.t3.state_dict())
            if set(sd) != propias:      # a veces las claves vienen con "model." delante
                sd = {(k[6:] if k.startswith('model.') else k): x for k, x in sd.items()}
            if set(sd) != propias: raise ValueError('no encaja con el modelo multilingue')
            m.t3.load_state_dict(sd, strict=True)
            m.t3.to(dev).eval()
            self.aviso(f'  Modelo afinado: {repo}')
        except Exception as e:
            self.aviso(f'  No se pudo cargar {repo} ({e}); se usa el multilingue.')

    def voz(self, v, refdir, rehacer=False):
        from chatterbox.mtl_tts import Conditionals
        f = os.path.join(refdir, f'voz{v:02d}.chatterbox.pt'); wr = os.path.join(refdir, f'voz{v:02d}.wav')
        marca = os.path.getmtime(wr)
        if not rehacer and v in self.conds and self.conds[v][0] == marca: return self.conds[v][1]
        def hacer():
            self.m.prepare_conditionals(wr, exaggeration=0.5); return self.m.conds
        c = _cargar_o_hacer(f, wr, rehacer, lambda r: Conditionals.load(r).to(self.dev), hacer, self.aviso, v)
        self.conds[v] = (marca, c)
        return c

    def _limitar_tokens(self):
        """Chatterbox genera hasta 1000 tokens de voz (~40 s) si no ve el final de la frase: con frases cortas
        ("Roger", "4-5") eso era lo que mas tiempo se llevaba. Se limita cada llamada a lo que puede durar la frase"""
        t3 = getattr(self.m, 't3', None)
        if t3 is None or getattr(t3.inference, '_bms', False): return
        orig = t3.inference
        def inference(*args, **kw):
            lim = getattr(self, '_tokens_max', None)
            if lim:
                kw['max_new_tokens'] = min(int(kw.get('max_new_tokens') or 1000), lim)
            return orig(*args, **kw)
        inference._bms = True
        t3.inference = inference

    def decir(self, v, frase, idioma, refdir, temperatura=0.8, expresividad=0.5, cfg=0.5, max_seg=None, **_):
        idioma = {'zh-cn': 'zh'}.get(idioma, idioma)
        if idioma not in IDIOMAS_CB: raise SystemExit(f'Chatterbox no tiene el idioma "{idioma}" (usa XTTS para ese idioma)')
        self.m.conds = self.voz(v, refdir)
        self._limitar_tokens()
        self._tokens_max = int(max_seg * 25) + 10 if max_seg else None     # 25 tokens de voz por segundo
        w = self.m.generate(frase, language_id=idioma, exaggeration=float(expresividad), cfg_weight=float(cfg), temperature=float(temperatura))
        x = w.squeeze().detach().cpu().numpy().astype(np.float64)
        if self.sr != SR:
            from scipy.signal import resample_poly
            from math import gcd
            g = gcd(self.sr, SR); x = resample_poly(x, SR // g, self.sr // g)
        return x

def cargar(motor='chatterbox', variante='v3', aviso=print):
    if motor == 'xtts': return XTTS(variante, aviso)
    if motor == 'chatterbox': return Chatterbox(variante, aviso)
    raise SystemExit(f'Motor desconocido: {motor} (chatterbox o xtts)')

# parametros de voz de cada motor (los de sonido -radio, volumen, pausas...- son comunes)
def params(motor, temperatura=0.65, velocidad=1.0, cb_temperatura=0.8, expresividad=0.5, cfg=0.5):
    if motor == 'xtts': return {'temperatura': temperatura, 'velocidad': velocidad}
    return {'temperatura': cb_temperatura, 'expresividad': expresividad, 'cfg': cfg}

# ritmo aproximado (para detectar lo que el modelo se inventa al final): XTTS tiene velocidad;
# en Chatterbox, mas expresividad acelera y menos cfg ralentiza
def ritmo(motor, p):
    if motor == 'xtts': return float(p.get('velocidad', 1.0))
    return max(0.6, min(1.5, 1.0 + 0.4 * (float(p.get('expresividad', 0.5)) - 0.5) + 0.4 * (float(p.get('cfg', 0.5)) - 0.5)))
