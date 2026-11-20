"""Genera index.html a partir de plantilla.html: mete el banco de preguntas y añade la versión a los scripts de traducción
(para que los navegadores no usen una copia antigua de i18n/ui.js o i18n/i18n.js)."""
import hashlib, json, re
t = open("plantilla.html", encoding="utf-8").read()
c = open("preguntas.csv", encoding="utf-8").read()
t = t.replace('/*__PREGUNTAS_CSV__*/""', json.dumps(c, ensure_ascii=False))
esp = open("retos_especiales.csv", encoding="utf-8").read() if __import__("os").path.exists("retos_especiales.csv") else ""
t = t.replace('/*__RETOS_ESPECIALES__*/""', json.dumps(esp, ensure_ascii=False))
def ver(f): return hashlib.md5(open(f, "rb").read()).hexdigest()[:8]
t = re.sub(r'src="i18n/(ui|i18n)\.js(\?v=\w+)?"', lambda m: f'src="i18n/{m.group(1)}.js?v={ver("i18n/" + m.group(1) + ".js")}"', t)
open("index.html", "w", encoding="utf-8").write(t)
for f in ("evento.html", "jugar.html"):
    s = open(f, encoding="utf-8").read()
    open(f, "w", encoding="utf-8").write(re.sub(r'src="i18n/(ui|i18n)\.js(\?v=\w+)?"', lambda m: f'src="i18n/{m.group(1)}.js?v={ver("i18n/" + m.group(1) + ".js")}"', s))
print("index.html generado")
