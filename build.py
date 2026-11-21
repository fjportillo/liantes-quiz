"""Genera la web de un quiz a partir de plantilla.html (el motor común).

  python3 build.py                 → Liantes Quiz Metalero (index.html en esta carpeta)
  python3 build.py sabelotodo      → quizzes/sabelotodo/config.json (lo genera en su carpeta "salida")

La plantilla tiene dos tipos de marcas:
  <!--#marca:NOMBRE--> … <!--#/marca-->  (o /*#marca:NOMBRE*/ … /*#/marca*/ en CSS): bloque de HTML/CSS
      que cada quiz puede sustituir con config["bloques"][NOMBRE]. Si no, se queda el de Liantes.
  /*#cfg:CLAVE*/<valor JSON>: constante de JavaScript que cada quiz puede cambiar con config["cfg"][CLAVE].
"""
import hashlib, json, os, re, shutil, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
VALOR = r'("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|\[[^\]]*\]|\{[^{}]*\}|true|false|-?\d+(?:\.\d+)?)'

def leer(ruta, defecto=None):
    if not os.path.exists(ruta):
        if defecto is not None: return defecto
        raise FileNotFoundError(ruta)
    return open(ruta, encoding="utf-8").read()

def version(ruta):
    return hashlib.md5(open(ruta, "rb").read()).hexdigest()[:8]

def generar(cfg, base, salida):
    t = leer(os.path.join(AQUI, "plantilla.html"))
    bloques, consts = cfg.get("bloques", {}), cfg.get("cfg", {})
    def bloque(m):
        nombre, defecto = m.group(2), m.group(3)
        return bloques.get(nombre, defecto)
    t = re.sub(r'<!--#marca:(()[\w-]+)-->([\s\S]*?)<!--#/marca-->', lambda m: bloques.get(m.group(1), m.group(3)), t)
    t = re.sub(r'/\*#marca:([\w-]+)\*/([\s\S]*?)/\*#/marca\*/', lambda m: bloques.get(m.group(1), m.group(2)), t)
    def const(m):
        k = m.group(1)
        return json.dumps(consts[k], ensure_ascii=False) if k in consts else m.group(2)
    t = re.sub(r'/\*#cfg:(\w+)\*/' + VALOR, const, t)
    faltan = set(re.findall(r'/\*#cfg:(\w+)\*/', t))
    if faltan: raise SystemExit("Marcas cfg sin valor reconocible: %s" % faltan)
    preguntas = leer(os.path.join(base, cfg.get("preguntas", "preguntas.csv")))
    t = t.replace('/*__PREGUNTAS_CSV__*/""', json.dumps(preguntas, ensure_ascii=False))
    esp = leer(os.path.join(base, "retos_especiales.csv"), "")
    t = t.replace('/*__RETOS_ESPECIALES__*/""', json.dumps(esp, ensure_ascii=False))
    # versión en los scripts de traducción (para que el navegador no use copias antiguas)
    t = re.sub(r'src="i18n/(ui|i18n)\.js(\?v=\w+)?"', lambda m: f'src="i18n/{m.group(1)}.js?v={version(os.path.join(AQUI, "i18n", m.group(1) + ".js"))}"', t)
    os.makedirs(salida, exist_ok=True)
    open(os.path.join(salida, "index.html"), "w", encoding="utf-8").write(t)
    return t

def liantes():
    generar({}, AQUI, AQUI)
    for f in ("evento.html", "jugar.html"):
        ruta = os.path.join(AQUI, f); s = leer(ruta)
        s = re.sub(r'src="i18n/(ui|i18n)\.js(\?v=\w+)?"', lambda m: f'src="i18n/{m.group(1)}.js?v={version(os.path.join(AQUI, "i18n", m.group(1) + ".js"))}"', s)
        open(ruta, "w", encoding="utf-8").write(s)
    print("index.html generado")

def evento(cfg, salida):
    """Modo evento (evento.html = pantalla del presentador, jugar.html = móvil del jugador) para otro quiz:
    mismas páginas que Liantes, con su Supabase, su prefijo de almacenamiento, sus colores y sus textos."""
    ev = cfg.get("evento")
    if not ev: return
    c = cfg["cfg"]; pre = c.get("STORE_PREFIX", "")
    # traducciones de los textos propios del quiz (categorías, marca y textos del modo evento) para las páginas sueltas
    marca = c.get("MARCA", {})
    extra = {"ca": dict(marca.get("ca", {})), "en": dict(marca.get("en", {}))}
    for es, (ca, en) in ev.get("textos", {}).items():
        extra["ca"][es] = ca; extra["en"][es] = en
    js = ("/* Generado por build.py: textos propios de este quiz para evento.html y jugar.html */\n"
          "(function(){ const X = " + json.dumps(extra, ensure_ascii=False) + ";\n"
          "  window.I18N = window.I18N || {}; for (const l in X) window.I18N[l] = Object.assign(window.I18N[l] || {}, X[l]); })();\n")
    open(os.path.join(salida, "i18n", "marca.js"), "w", encoding="utf-8").write(js)
    i18n = leer(os.path.join(AQUI, "i18n", "i18n.js")).replace('"rmq-lang"', '"%srmq-lang"' % pre)
    open(os.path.join(salida, "i18n", "i18n.js"), "w", encoding="utf-8").write(i18n)
    v = hashlib.md5(js.encode()).hexdigest()[:8]
    for f in ("concurso.js", "sonido.js"):
        shutil.copy(os.path.join(AQUI, f), os.path.join(salida, f))
    for pagina in ("evento.html", "jugar.html"):
        t = leer(os.path.join(AQUI, pagina))
        t = re.sub(r'const SUPABASE_URL = "[^"]*";', 'const SUPABASE_URL = %s;' % json.dumps(c["SUPABASE_URL"]), t)
        t = re.sub(r'const SUPABASE_KEY = "[^"]*";', 'const SUPABASE_KEY = %s;' % json.dumps(c["SUPABASE_KEY"]), t)
        for k in ("ev-host", "ev-player", "ev-ultima", "ev-nombre", "ev-usadas"):
            t = t.replace('"%s"' % k, '"%s%s"' % (pre, k))
        t = t.replace('"ev-ans-"', '"%sev-ans-"' % pre)
        t = t.replace('<script src="i18n/i18n.js', '<script src="i18n/marca.js?v=%s"></script>\n<script src="i18n/i18n.js' % v, 1)
        for a, b in ev.get("reemplazos", []):
            t = t.replace(a, b)
        t = t.replace("</style>", ev.get("css", "") + "\n</style>", 1)
        open(os.path.join(salida, pagina), "w", encoding="utf-8").write(t)

def otro(nombre):
    base = os.path.join(AQUI, "quizzes", nombre)
    cfg = json.loads(leer(os.path.join(base, "config.json")))
    salida = os.path.abspath(os.path.join(base, cfg.get("salida", "dist")))
    generar(cfg, base, salida)
    # archivos que acompañan a la web: traducciones de la interfaz (comunes) y los propios del quiz
    os.makedirs(os.path.join(salida, "i18n"), exist_ok=True)
    shutil.copy(os.path.join(AQUI, "i18n", "ui.js"), os.path.join(salida, "i18n", "ui.js"))
    for f in cfg.get("copiar", []):
        origen = os.path.join(base, f); destino = os.path.join(salida, f)
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        if os.path.isdir(origen):
            shutil.copytree(origen, destino, dirs_exist_ok=True)
        else:
            shutil.copy(origen, destino)
    evento(cfg, salida)
    # service worker con su propia caché
    sw = leer(os.path.join(AQUI, "sw.js")).replace('const CACHE = "liantes-quiz-', 'const CACHE = "%s-' % nombre)
    # en la caché sin conexión, solo los archivos que existen en este quiz
    m = re.search(r'const SHELL = \[([\s\S]*?)\];', sw)
    lista = [x for x in re.findall(r'"([^"]+)"', m.group(1)) if x == "./" or os.path.exists(os.path.join(salida, x))]
    sw = sw[:m.start()] + "const SHELL = " + json.dumps(lista) + ";" + sw[m.end():]
    sw = sw.replace("Service worker de Liantes Quiz Metalero", "Service worker de " + cfg.get("nombre", nombre))
    open(os.path.join(salida, "sw.js"), "w", encoding="utf-8").write(sw)
    print("%s generado en %s" % (nombre, salida))

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] != "liantes": otro(sys.argv[1])
    else: liantes()
