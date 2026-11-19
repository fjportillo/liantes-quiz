# Liantes Quiz Metalero 🤘

Concurso de preguntas sobre rock, heavy metal, punk y la Associació Liantes Metaleros (Badalona).

Web: https://fjportillo.github.io/liantes-quiz/

## Archivos
- `index.html` — el juego (lleva una copia de las preguntas incrustada como respaldo)
- `plantilla.html` — plantilla del juego; `index.html` se genera a partir de ella
- `preguntas.csv` — banco de preguntas
- `supabase.sql` — base de datos del Hall of Fame compartido
- `hall_of_fame_mensual.sql`, `estadisticas.sql`, `reportes.sql`, `evento.sql`, `pin.sql` — ranking mensual, estadísticas, reportes de errores, modo evento y PIN
- `login_obligatorio.sql` — solo guarda partidas de jugadores con nombre y PIN correcto (se acabaron las partidas como «Anónimo»)

**Acceso:** al abrir la web aparece la pantalla «Entra para jugar»: nombre + PIN de 4 cifras (si el nombre está libre o no tiene PIN, se crea en ese momento). La sesión se recuerda en el dispositivo; «Cambiar de usuario» la cierra. Sin entrar solo se puede consultar el Hall of Fame.
- `retos_perfil.sql` — reto diario (10 preguntas iguales para todos cada día, una partida por jugador) y perfiles de jugador con logros
- `ranking_diario.sql` — desde el 1-12-2026 el ranking del mes suma la mejor partida de cada día (hasta 20 preguntas) + premios del reto
- `premios_reto.sql` — premio del reto diario (+500/+300/+150 al ranking del mes para el podio, mínimo 3 jugadores) y nuevos límites de puntos; activo desde el 1-12-2026
- `preguntas_vistas.sql` — cuenta cuántas veces sale cada pregunta (vista `preguntas_ranking`); la renovación semanal retira las más vistas
- `promo.html` — publicación del día para redes (imagen 4:5 y 9:16 + texto listo para copiar): https://fjportillo.github.io/liantes-quiz/promo.html
- `manifest.webmanifest`, `sw.js`, `icons/` — app instalable (PWA): icono en el móvil y juego sin conexión. Enlace directo para instalar: https://fjportillo.github.io/liantes-quiz/#instalar. Si cambias archivos que guarda el sw.js, sube el número de CACHE para forzar la actualización.

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

## Modo evento (pantalla grande + móviles)
- `evento.html` — pantalla del presentador: se proyecta, crea la sala, muestra el QR y el código, las preguntas, el reparto de votos, la clasificación y el podio. Atajo: barra espaciadora para avanzar.
- `jugar.html` — pantalla del jugador en el móvil (se abre con el QR o con `jugar.html?sala=CODIGO`).
- `evento.sql` — tablas y funciones en Supabase (hay que ejecutarlo una vez).
Puntuación: 100 puntos por acierto + hasta 100 por rapidez. Las salas se borran solas a los 2 días.

## Idiomas (castellano, català, English)

- El idioma se elige con los botones **ES · CA · EN** de la cabecera (se recuerda en cada dispositivo). También se puede forzar con `?lang=ca` o `?lang=en` en la dirección.
- `i18n/ui.js` — traducciones de la interfaz. La clave es el texto en castellano tal como está en el código; `{x}` son valores que se rellenan solos. Si falta una traducción, se ve en castellano.
- `i18n/i18n.js` — sistema de idiomas de las páginas del modo evento (`evento.html`, `jugar.html`).
- `i18n/preguntas_ca.csv` e `i18n/preguntas_en.csv` — traducción de las preguntas:
  `pregunta_es,visual,correcta_es,pregunta,correcta,incorrecta1,incorrecta2,incorrecta3`
  - `pregunta_es` + `visual` identifican la pregunta tal cual está en `preguntas.csv`.
  - `correcta_es` es la respuesta correcta en castellano cuando se tradujo: si después se cambia en `preguntas.csv`, el juego muestra esa pregunta en castellano hasta que se actualice la traducción.
  - Una respuesta traducida vacía = igual que en castellano (nombres de grupos, discos, años…). Las incorrectas van en el mismo orden que en `preguntas.csv`.
- `tools/check_i18n.py` — comprueba que no falte ni sobre ninguna traducción (`--limpiar` borra las de preguntas retiradas).
- En el modo evento cada móvil ve la pregunta en su idioma, aunque la sala sea la misma.
- El reto diario es el mismo en los tres idiomas (mismas preguntas y mismo orden de respuestas).
- Los reportes de errores y el recuento de preguntas vistas se guardan siempre con el texto en castellano.

## Reglas desde el 1 de diciembre de 2026

- **Puntos por dificultad:** fácil 100, media 150, difícil 200 (+5 por segundo sobrante y +50 con racha de 3 o más). Constantes `NEW_RULES_FROM` y `POINTS_BY_DIFF` en `plantilla.html`.
- **Campeonato o práctica:** al empezar se elige el tipo de partida. *Campeonato*: 20 preguntas de todas las categorías con dificultad automática; es la única que puntúa (`modo = 'campeonato'`). *Práctica*: número de preguntas, dificultad y categoría libres; se guarda para el perfil pero no cuenta para el ranking (`modo = 'practica'`). SQL en `campeonato.sql`.
- **Dificultad automática**: cada pregunta se elige según el porcentaje de aciertos del jugador en ese dispositivo y sube o baja durante la partida según acierte o falle. El reto diario y el modo evento siguen siendo iguales para todos.
- **Ranking por días:** cada jugador suma, por cada día, solo su mejor partida de campeonato (vista `partidas_ranking`). Las de práctica no puntúan; las de más de 200 preguntas («Todas») son de práctica y no se guardan.
- **Aviso de novedades:** el 1 de diciembre la web muestra una vez en cada dispositivo una ventana con los cambios.
- **Premio del reto diario:** el podio de cada día suma +500 / +300 / +150 al ranking del mes si jugaron al menos 3 personas (vista `reto_premios`).
- Para probar las reglas antes de esa fecha, añade `#nuevas-reglas` a la dirección.
