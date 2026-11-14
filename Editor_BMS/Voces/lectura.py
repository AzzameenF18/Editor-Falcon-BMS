# -*- coding: utf-8 -*-
"""
Como se leen en voz alta los textos de la radio en cada idioma: numeros, siglas, letras y decimales.

La configuracion de cada idioma esta en Idiomas\\<CODIGO>\\idioma.json, clave "lectura" (se edita en el
Editor BMS: Traduccion -> Ajustes del idioma). Todo son textos para que se puedan editar a mano:
  basicos      del 0 al 19, separados por comas
  decenas      20, 30 ... 90, separados por comas
  union        entre decena y unidad (" y ", " e ", "-", "und"...)
  unidadPrimero  true si la unidad va delante (aleman: "ein" + "und" + "zwanzig")
  excepciones  una por linea, numero=texto (veintiuno, soixante et onze...): mandan sobre las reglas
  centenas     100, 200 ... 900, separados por comas
  cien         el 100 solo (cien, cem, cent...)
  unionCentena entre centena y resto
  mil / milSolo        "mil" detras de un numero / el 1000 solo
  millon / millones    el 1.000.000 solo / detras de un numero
  antesDeMil   cambios en el numero que va delante de mil o millones, una por linea (uno=un)
  decimal      la coma decimal (coma, virgula, virgule...)
  letras       una por linea, A=a, B=be... (para siglas: F-16, SAM, QNH)
  frasePrueba  frase para probar las voces (se le añade el numero de voz)
Lo que no se indique (la clave no existe) se toma de la plantilla del idioma de la voz
(plantillas_lectura.json); una clave vacia es vacia. Sin plantilla, los numeros se dejan en cifras.
"""
import json, os, re

CLAVES = ('basicos', 'decenas', 'union', 'unidadPrimero', 'excepciones', 'centenas', 'cien', 'unionCentena',
          'mil', 'milSolo', 'millon', 'millones', 'antesDeMil', 'decimal', 'letras', 'frasePrueba')
PLANTILLAS_FICH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'plantillas_lectura.json')


def plantillas():
    """Plantillas de lectura por idioma de voz (es, pt, fr, it, de...): plantillas_lectura.json del kit"""
    try: return json.load(open(PLANTILLAS_FICH, encoding='utf-8-sig'))
    except Exception: return {}


def _lista(s):
    return [x.strip() for x in str(s).split(',')]


def _mapa(s):
    d = {}
    for l in str(s).replace(';', '\n').splitlines():
        if '=' in l:
            a, b = l.split('=', 1)
            if a.strip(): d[a.strip()] = b.strip()
    return d


class Lectura:
    def __init__(self, cfg=None, voz='es'):
        c = {'union': ' ', 'unidadPrimero': False, 'excepciones': '', 'unionCentena': ' ', 'antesDeMil': '', 'letras': '',
             'decimal': ',', 'frasePrueba': 'Test'}
        c.update(plantillas().get(voz, {}))
        for k, v in (cfg or {}).items():
            if k in CLAVES and v is not None: c[k] = v
        self.cfg = c
        self.bas = _lista(c.get('basicos', ''))
        self.dec = _lista(c.get('decenas', ''))
        self.cen = _lista(c.get('centenas', ''))
        # sin numeros completos (ni plantilla ni configuracion): se dejan en cifras
        self.cifras = len(self.bas) < 20 or len(self.dec) < 8 or len(self.cen) < 9
        for k in ('cien', 'mil', 'milSolo', 'millon', 'millones'): c.setdefault(k, '')
        self.exc = {int(k): v for k, v in _mapa(c['excepciones']).items() if k.isdigit()}
        self.antes = sorted(_mapa(c['antesDeMil']).items(), key=lambda x: -len(x[0]))
        self.letras = {k.upper(): v for k, v in _mapa(c['letras']).items() if len(k) == 1}
        self.uprim = str(c['unidadPrimero']).lower() in ('true', '1', 'si', 'sí', 'yes')

    def n999(self, n):
        if n in self.exc: return self.exc[n]
        if n < 20: return self.bas[n]
        if n < 100:
            d, u = divmod(n, 10)
            dw = self.dec[d - 2]
            if u == 0: return dw
            uw = self.bas[u]
            return (uw + self.cfg['union'] + dw) if self.uprim else (dw + self.cfg['union'] + uw)
        if n == 100: return self.cfg['cien'] or self.cen[0]
        c, r = divmod(n, 100)
        return self.cen[c - 1] if r == 0 else self.cen[c - 1] + self.cfg['unionCentena'] + self.n999(r)

    def _antes(self, s):
        for a, b in self.antes:
            s = re.sub(r'(?<!\w)' + re.escape(a) + r'(?!\w)', b, s)
        return s

    def numero(self, n):
        n = int(n)
        if self.cifras: return str(n)
        if n in self.exc: return self.exc[n]
        if n < 1000: return self.n999(n)
        if n < 1000000:
            m, r = divmod(n, 1000)
            pre = self.cfg['milSolo'] if m == 1 else self._antes(self.n999(m)) + ' ' + self.cfg['mil']
            return pre + ('' if r == 0 else ' ' + self.n999(r))
        m, r = divmod(n, 1000000)
        pre = self.cfg['millon'] if m == 1 else self._antes(self.numero(m)) + ' ' + self.cfg['millones']
        return pre + ('' if r == 0 else ' ' + self.numero(r))

    def digito(self, c):
        return c if self.cifras else self.bas[int(c)]

    def deletrear(self, s):
        return ' '.join(self.letras.get(c, c) for c in s.upper())

    def cifra(self, tok):
        """'0-8-7' -> cero ocho siete ; '1-1' -> uno uno ; '14000' -> catorce mil ; '087' -> cero ocho siete"""
        out = []
        for p in re.split(r'[-\s]+', tok.strip('-')):
            if not p: continue
            if len(p) > 1 and p.startswith('0'): out += [self.digito(c) for c in p]
            else: out.append(self.numero(p))
        return ' '.join(out)

    def normalizar(self, texto, dic):
        t = ' ' + texto.strip() + ' '
        for a, b in dic:  # diccionario de pronunciaciones primero (palabra completa, respeta mayusculas)
            t = re.sub(r'(?<![\w-])' + re.escape(a) + r'(?![\w-])', ' ' + b + ' ', t)
        # sigla/letras + numero: F-16, SA-6, Su-27, MiG-29, SA-3s, OH-58s
        def sig(m):
            let, num = m.group(1), m.group(2)
            let = self.deletrear(let) if let.isupper() and len(let) <= 4 else let.lower()
            return f' {let} {self.cifra(num)} '
        t = re.sub(r'(?<![\w])([A-Za-z]{1,4})-(\d+)s?(?![\w])', sig, t)
        # decimales: Mach 1.7 -> uno coma siete
        t = re.sub(r'(?<![\w.])(\d+)[.,](\d+)(?![\w])',
                   lambda m: f' {self.numero(m.group(1))} {self.cfg["decimal"]} {self.cifra(m.group(2))} ', t)
        # grupos de cifras: 1-1-4, 2 4, 0-8-7, 14000
        t = re.sub(r'(?<![\w])\d+(?:[-\s]\d+)*(?![\w])', lambda m: ' ' + self.cifra(m.group(0)) + ' ', t)
        # siglas sueltas en mayusculas (2-4 letras): ECM, GBU, QNH
        t = re.sub(r'(?<![\w])([A-Z]{2,4})s?(?![\w])', lambda m: ' ' + self.deletrear(m.group(1)) + ' ', t)
        return re.sub(r'\s+', ' ', t.replace('/', ' ')).strip()


def cargar(ruta, voz=None):
    """Lectura de un idioma.json: su "lectura" sobre la plantilla de su idioma de voz ("voz")."""
    cfg = None; v = voz
    if ruta and os.path.exists(ruta):
        try:
            j = json.load(open(ruta, encoding='utf-8-sig'))
            if isinstance(j, dict):
                cfg = j.get('lectura', j)
                v = v or j.get('voz')
        except Exception as e:
            print('No se pudo leer la lectura de', ruta, e)
    return Lectura(cfg, v or 'es')


def idioma_voz(ruta, defecto='es'):
    """Idioma de XTTS del idioma.json ("voz"), p. ej. es, pt, fr, it, de."""
    if ruta and os.path.exists(ruta):
        try:
            v = json.load(open(ruta, encoding='utf-8-sig')).get('voz')
            if v: return str(v)
        except Exception: pass
    return defecto


def cargar_diccionario(ruta):
    d = []
    if ruta and os.path.exists(ruta):
        for l in open(ruta, encoding='utf-8-sig'):
            l = l.rstrip('\n')
            if not l.strip() or l.lstrip().startswith('#') or '=' not in l: continue
            a, b = l.split('=', 1); d.append((a.strip(), b.strip()))
    d.sort(key=lambda x: -len(x[0]))
    return d
