#!/usr/bin/env python3
"""Comprueba que las traducciones de las preguntas están al día con preguntas.csv.

Uso:  python3 tools/check_i18n.py            -> informe
      python3 tools/check_i18n.py --limpiar  -> además borra las filas huérfanas (preguntas retiradas)
      python3 tools/check_i18n.py --quiz sabelotodo [--limpiar]  -> lo mismo para quizzes/sabelotodo/

Formato de i18n/preguntas_XX.csv (XX = ca, en):
  pregunta_es,visual,correcta_es,pregunta,correcta,incorrecta1,incorrecta2,incorrecta3
  - pregunta_es + visual identifican la pregunta (tal cual está en preguntas.csv).
  - correcta_es es la respuesta correcta en castellano cuando se tradujo; si ya no coincide,
    el juego ignora la traducción y muestra la pregunta en castellano.
  - Una respuesta traducida vacía significa "igual que en castellano" (nombres de grupos, discos, años...).
  - incorrecta1..3 van en el mismo orden que en preguntas.csv.
"""
import csv, io, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# --quiz sabelotodo -> comprueba quizzes/sabelotodo/ en lugar del quiz de Liantes
if "--quiz" in sys.argv: ROOT = os.path.join(ROOT, "quizzes", sys.argv[sys.argv.index("--quiz") + 1])
LANGS = ["ca", "en"]
HEAD = ["pregunta_es", "visual", "correcta_es", "pregunta", "correcta", "incorrecta1", "incorrecta2", "incorrecta3"]

def read(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.reader(f))

def main():
    clean = "--limpiar" in sys.argv
    es = read(os.path.join(ROOT, "preguntas.csv"))
    h = [x.strip().lower() for x in es[0]]
    ix = lambda n: h.index(n) if n in h else -1
    iq, ic, iv = ix("pregunta"), ix("correcta"), ix("visual")
    bank = {}
    for r in es[1:]:
        if len(r) <= max(iq, ic) or not r[iq].strip(): continue
        bank[(r[iq].strip(), (r[iv].strip() if iv >= 0 and iv < len(r) else ""))] = r[ic].strip()
    ok_all = True
    for L in LANGS:
        path = os.path.join(ROOT, "i18n", f"preguntas_{L}.csv")
        rows = read(path)
        assert rows[0] == HEAD, f"{path}: cabecera distinta de {HEAD}"
        seen, orphan, stale, empty, dup = set(), [], [], [], []
        keep = [HEAD]
        for r in rows[1:]:
            r = (r + [""] * 8)[:8]
            k = (r[0].strip(), r[1].strip())
            if k in seen: dup.append(k); continue
            seen.add(k)
            if k not in bank: orphan.append(k);
            elif r[2].strip() != bank[k]: stale.append((k, r[2], bank[k])); keep.append(r)
            else:
                if not r[3].strip(): empty.append(k)
                keep.append(r)
        missing = [k for k in bank if k not in seen]
        print(f"[{L}] {len(rows)-1} filas · faltan {len(missing)} · desactualizadas {len(stale)} · huérfanas {len(orphan)} · sin texto {len(empty)} · duplicadas {len(dup)}")
        for k in missing[:200]: print(f"   FALTA: {k[0]}  {k[1]}")
        for k, old, new in stale[:200]: print(f"   DESACTUALIZADA: {k[0]}  (traducida con «{old}», ahora «{new}»)")
        for k in orphan[:200]: print(f"   HUÉRFANA: {k[0]}  {k[1]}")
        for k in empty: print(f"   SIN TEXTO: {k[0]}")
        if missing or stale or empty or dup: ok_all = False
        if clean and (orphan or dup):
            buf = io.StringIO(); csv.writer(buf, lineterminator="\n").writerows(keep)
            open(path, "w", encoding="utf-8").write(buf.getvalue())
            print(f"   -> borradas {len(orphan)} huérfanas y {len(dup)} duplicadas")
    print("OK: traducciones completas" if ok_all else "HAY QUE COMPLETAR TRADUCCIONES")
    sys.exit(0 if ok_all else 1)

if __name__ == "__main__":
    main()
