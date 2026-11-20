"""Genera config.json y manifest.webmanifest de Sabelotodo (ejecutar tras cambiar marca.py)."""
import json
from marca import M, CATS
SITE = "https://fjportillo.github.io/sabelotodo/"
marca = {"es": {}, "ca": {}, "en": {}}
for orig, es, ca, en in M:
    if es != orig: marca["es"][orig] = es
    marca["ca"][es] = ca; marca["en"][es] = en
for es, ca, en in CATS:
    marca["ca"][es] = ca; marca["en"][es] = en
CSS = """
  :root{--bg:#0b1324;--panel:#121c33;--panel2:#18243f;--line:#26365a;--text:#f1f5f9;--muted:#94a3b8;--grey:#e2e8f0;--blue:#0d9488;--blue2:#5eead4;--gold:#ffd166}
  .topbar{background:linear-gradient(90deg,#0f172a,#0d9488)}
  .logo-slot{background:transparent;box-shadow:none;width:72px;height:72px;top:4px}
  .menu-space{background:#0f172a}
  .lang-sw button.on{background:var(--blue2);color:#0b1324}
  @media (max-width:640px){ .lang-sw{background:#0f172a} }
  h1.logo{font-family:"Fraunces",Georgia,serif;font-weight:800;color:var(--text);letter-spacing:0;font-size:clamp(48px,12vw,92px)}
  h1.logo a span{color:var(--gold)}
  .big,.hof-title,.prof-av,.reto-esp .esp-t{font-family:"Fraunces",Georgia,serif;font-weight:800}
  .hero .sub span{color:var(--gold)}
  .tag{font-style:normal}
  footer .motto{font-style:italic}
  footer{background:#0f172a !important;border-top:1px solid var(--line) !important}
"""
cfg = {
  "nombre": "Sabelotodo",
  "salida": "../../../sabelotodo-web",
  "preguntas": "preguntas.csv",
  "copiar": ["i18n/preguntas_ca.csv", "i18n/preguntas_en.csv", "logo.png", "icons", "manifest.webmanifest", "retos_especiales.csv"],
  "cfg": {
    "SUPABASE_URL": "https://bdtkngisgjarnyabzhsy.supabase.co",
    "SUPABASE_KEY": "sb_publishable_LaMPVutoRf9rrjdmOWzBOw_ZDVX-W-1",
    "PAYPAL_ME": "",
    "NEW_RULES_FROM": "2026-11-01",
    "LOCAL_CATS": [],
    "LOCAL_RE": "",
    "SITE_URL": SITE,
    "EPOCH": "2026-11-20",
    "RETO_SEED": "sabelotodo-reto-",
    "IMG_TITULO": "SABELOTODO",
    "IMG_SUB1": "QUIZ ",
    "IMG_SUB2": "DIARIO",
    "IMG_ARCHIVO": "sabelotodo.png",
    "IMG_WEB": "  fjportillo.github.io/sabelotodo",
    "IMG_FONT": "800 \"Fraunces\", Georgia, serif".replace("800 ", ""),
    "TEMAS": False,
    "STORE_PREFIX": "sab:",
    "NOVEDADES_DIC": False,
    "MARCA": marca,
  },
  "bloques": {
    "cabeza1": '<meta name="theme-color" content="#0f172a">\n<link rel="icon" type="image/png" href="logo.png">\n<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">',
    "cabeza2": '<meta name="apple-mobile-web-app-title" content="Sabelotodo">\n<meta name="description" content="Sabelotodo: el quiz diario de cultura general. Reto diario, campeonato, logros y ranking. En castellano, català e English.">\n<meta property="og:title" content="Sabelotodo 🧠 El quiz diario de cultura general">\n<meta property="og:description" content="Diez preguntas al día, las mismas para todos. ¿Cuánto sabes de todo un poco?">\n<meta property="og:image" content="' + SITE + 'icons/icon-512.png">\n<meta property="og:url" content="' + SITE + '">\n<meta property="og:type" content="website">\n<title>Sabelotodo · El quiz diario de cultura general</title>',
    "fuentes": '<link href="https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&family=Fraunces:wght@600;800&family=Red+Hat+Display:wght@400;700;800;900&family=DM+Sans:ital,wght@0,400;0,600;0,700;1,400&family=Roboto:wght@400&display=swap" rel="stylesheet">',
    "css": CSS,
    "topbar": '<div class="topbar"><a class="logo-slot" id="logo-slot" href="#" title="Sabelotodo"><img src="logo.png" alt="Sabelotodo"></a></div>',
    "hero": '<div class="pre" data-t>El quiz diario de cultura general</div>\n  <h1 class="logo"><a href="#" id="home-link" title="Volver al inicio" data-t-title>Sabelo<span>todo</span></a></h1>',
    "lema": '<div class="tag" data-t>¿Cuánto sabes de todo un poco? Diez preguntas al día, las mismas para todos.</div>',
    "socio": '',
    "evento": '',
    "pie": '<p class="motto" data-t>Pon a prueba tu cultura general.</p>\n  <p><button class="deco-toggle hidden" id="deco-toggle"></button></p>\n  <p class="foot-install hidden" id="foot-install-p"><a class="web-link" href="#instalar" id="foot-install" data-t>📲 Descarga la app Liantes Quiz</a></p>',
  },
}
cfg["cfg"]["IMG_FONT"] = '"Fraunces", Georgia, serif'
json.dump(cfg, open("config.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
man = {
  "name": "Sabelotodo · El quiz diario de cultura general", "short_name": "Sabelotodo",
  "description": "El quiz diario de cultura general: reto diario, campeonato, logros y ranking.",
  "lang": "es", "id": "./", "start_url": "./?app=1", "scope": "./", "display": "standalone", "orientation": "portrait",
  "background_color": "#0b1324", "theme_color": "#0f172a", "categories": ["games", "education", "entertainment"],
  "icons": [{"src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
            {"src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
            {"src": "icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"}],
  "shortcuts": [{"name": "Reto diario", "short_name": "Reto", "url": "./?app=1#reto", "icons": [{"src": "icons/icon-192.png", "sizes": "192x192"}]}]}
json.dump(man, open("manifest.webmanifest", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("config.json y manifest.webmanifest generados")
