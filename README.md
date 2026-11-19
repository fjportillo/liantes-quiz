# Liantes Quiz Metalero 🤘

Concurso de preguntas sobre rock, heavy metal, punk y la Associació Liantes Metaleros (Badalona).

Web: https://fjportillo.github.io/liantes-quiz/

## Archivos
- `index.html` — el juego (lleva una copia de las preguntas incrustada como respaldo)
- `plantilla.html` — plantilla del juego; `index.html` se genera a partir de ella
- `preguntas.csv` — banco de preguntas
- `supabase.sql` — base de datos del Hall of Fame compartido

## Formato de `preguntas.csv`
`pregunta,correcta,incorrecta1,incorrecta2,incorrecta3,categoria,dificultad,alta,visual`

- `incorrecta3` es opcional (pregunta de 3 respuestas).
- `dificultad`: `facil`, `media` o `dificil`.
- `alta`: fecha en que se añadió la pregunta (AAAA-MM-DD).
- `visual` (opcional): emojis que se muestran en grande (categoría «Adivina la banda») o la ruta de una foto en `img/` (p. ej. `img/bunker.jpg`). Solo fotos propias o cedidas con permiso.
- Se puede añadir una columna `activa` con `no` para ocultar una pregunta.

## Regenerar `index.html` tras editar las preguntas
```
python3 -c "import json;t=open('plantilla.html',encoding='utf-8').read();c=open('preguntas.csv',encoding='utf-8').read();open('index.html','w',encoding='utf-8').write(t.replace('/*__PREGUNTAS_CSV__*/\"\"',json.dumps(c,ensure_ascii=False)))"
```

## Renovación semanal (viernes 00:00, Madrid)
Se añaden preguntas nuevas en todas las categorías y se retiran las más antiguas según la columna `alta`.

## Decoración automática
La web se decora sola según la fecha (hora de Madrid): Festes de Maig de Badalona (Cremada del Dimoni, 9-11 may), Sant Jordi (22-23 abr), Día Mundial del Rock (12-14 jul), aniversario de Liantes (8 mar), Sant Joan (22-24 jun), San Valentín (13-14 feb), Carnaval (calculado cada año), Halloween (20 oct-2 nov), Navidad (1 dic-4 ene), Nochevieja/Año Nuevo, Reyes (5-6 ene) y, el resto del año, la estación.
Para previsualizar un tema: añadir `#tema-halloween` (o `navidad`, `dimoni`, `santjordi`, `carnaval`, `rock`, `aniversario`, `santjoan`, `sanvalentin`, `nochevieja`, `reyes`, `primavera`, `verano`, `otono`, `invierno`, `ninguno`) al final de la dirección.
