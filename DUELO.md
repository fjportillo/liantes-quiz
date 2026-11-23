# Modo Duelo — plan y estado

Petición del usuario (23-11-2026): que cualquiera pueda abrir una sala desde su propio móvil y jugar desde él a la vez,
sin pantalla grande ni segundo dispositivo. Se llama **Duelo** y es una opción más (el modo evento con pantalla grande sigue igual).
Se desarrolla en la rama `duelo` en sesiones de unos 30 minutos al día (tarea programada «Desarrollo del modo Duelo»).
No se publica nada en `main` hasta que esté terminado y probado.

## Diseño acordado
- Botón nuevo «⚔️ Duelo» en el menú del juego (junto a «Modo evento») que abre `duelo.html`.
- `duelo.html`: quien abre crea la sala con las mismas opciones que el modo evento (clásica o por rondas, tiempo, nº de preguntas,
  categoría, dificultad, golpe final) en una pantalla de móvil.
- Tras crearla ve el código, el QR y un botón «Invitar» (Web Share API / enlace de WhatsApp) con el enlace a `jugar.html?codigo=XXXX`.
- El anfitrión se une como jugador a su propia sala y juega con la misma interfaz que los demás (la de `jugar.html`),
  más un botón «Empezar» en la sala de espera y un indicador de que es el anfitrión.
- La partida avanza sola desde el móvil del anfitrión: pregunta → (tiempo agotado o todos han respondido) → resultado →
  clasificación cuando toque → siguiente. Mismas reglas, puntos y SQL que el modo evento (ev_crear_sala, ev_pregunta, ev_revelar,
  ev_nueva_partida…, todo con el host_secret guardado en localStorage del anfitrión).
- Robustez: Wake Lock API para que no se apague la pantalla; si el anfitrión cierra o recarga, al volver continúa donde estaba
  (estado en localStorage, como `ev-host` en evento.html); los demás ven «Esperando al anfitrión…» si el estado no avanza
  más de ~15 s después del plazo.
- Sin SQL nuevo si se puede; si hace falta, en un archivo nuevo idempotente y avisando en el resumen de que hay que ejecutarlo.
- Textos en castellano, català e inglés (i18n/ui.js).
- Debe funcionar también en Sabelotodo: `build.py` copia/adapta evento.html y jugar.html para otros quizzes (líneas ~56 y ~82);
  añadir duelo.html (y cualquier .js nuevo) a esas listas.

## Enfoque técnico propuesto
1. Extraer la lógica del presentador de `evento.html` (crear sala, elegir preguntas incl. golpe final, startQuestion, reveal,
   avance automático, nueva partida) a un archivo compartido `anfitrion.js` sin dependencias de la pantalla grande,
   con callbacks para pintar. `evento.html` pasa a usarlo sin cambiar su comportamiento (probar que sigue igual).
2. `jugar.html` gana un «modo anfitrión»: si en localStorage hay secreto para ese código (`duelo-host`), carga `anfitrion.js`
   y ejecuta el bucle de avance además de la interfaz de jugador.
3. `duelo.html` = formulario de creación para móvil + invitación; al crear, se une como jugador y redirige a
   `jugar.html?codigo=XXXX` (modo anfitrión).
4. Botón en el menú principal (plantilla.html), README, i18n, build.py.
5. Pruebas con Playwright (varios contextos de navegador simulando móviles) contra un Supabase falso o, mejor,
   un Postgres local con los SQL del repo + un mini servidor PostgREST simulado (o interceptando fetch con page.route).

## Estado (actualizar al final de cada sesión)
- [ ] 1. anfitrion.js extraído y evento.html funcionando igual
- [ ] 2. modo anfitrión en jugar.html
- [ ] 3. duelo.html (creación, QR, invitar)
- [ ] 4. menú, README, i18n, build.py (Liantes y Sabelotodo)
- [ ] 5. pruebas completas con varios jugadores, incluido anfitrión que recarga
- [ ] 6. merge a main, build de los dos quizzes, push y aviso al usuario

## Diario
- 2026-11-23: plan creado (sesión interactiva).
