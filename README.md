# Liantes Quiz Metalero 🤘

Concurso de preguntas sobre rock, heavy metal, punk y la Associació Liantes Metaleros (Badalona).

Web: https://fjportillo.github.io/liantes-quiz/

## Archivos
- `index.html` — el juego (lleva una copia de las preguntas incrustada como respaldo)
- `plantilla.html` — plantilla del juego; `index.html` se genera a partir de ella
- `preguntas.csv` — banco de preguntas
- `supabase.sql` — base de datos del Hall of Fame compartido

## Formato de `preguntas.csv`
`pregunta,correcta,incorrecta1,incorrecta2,incorrecta3,categoria,dificultad,alta`

- `incorrecta3` es opcional (pregunta de 3 respuestas).
- `dificultad`: `facil`, `media` o `dificil`.
- `alta`: fecha en que se añadió la pregunta (AAAA-MM-DD).
- Se puede añadir una columna `activa` con `no` para ocultar una pregunta.

## Regenerar `index.html` tras editar las preguntas
```
python3 -c "import json;t=open('plantilla.html',encoding='utf-8').read();c=open('preguntas.csv',encoding='utf-8').read();open('index.html','w',encoding='utf-8').write(t.replace('/*__PREGUNTAS_CSV__*/\"\"',json.dumps(c,ensure_ascii=False)))"
```

## Renovación semanal (viernes 00:00, Madrid)
Se añaden preguntas nuevas en todas las categorías y se retiran las más antiguas según la columna `alta`.
