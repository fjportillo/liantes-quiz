-- Base de datos de SABELOTODO (quiz de cultura general)
-- Proyecto de Supabase propio, independiente del de Liantes.
-- Pégalo ENTERO en Supabase > SQL Editor > New query y pulsa "Run" una sola vez.
-- Crea las tablas, funciones y vistas que usa la web: partidas y Hall of Fame, estadísticas anónimas,
-- reportes de errores, modo evento, PIN de usuario, reto diario, perfil y logros, ranking diario,
-- campeonato, filtro de nombres ofensivos y limpieza mensual automática.
-- (Generado juntando los SQL del motor en el orden en que se crearon.)


-- ===================================================================
-- supabase.sql
-- ===================================================================
-- Hall of Fame compartido para Sabelotodo
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".

create table if not exists public.partidas (
  id        bigint generated always as identity primary key,
  nombre    text not null check (char_length(nombre) between 1 and 24),
  clave     text not null check (char_length(clave) between 1 and 40),
  puntos    integer not null check (puntos >= 0),
  aciertos  integer not null check (aciertos >= 0),
  total     integer not null check (total between 1 and 200),
  creado    timestamptz not null default now(),
  constraint aciertos_validos check (aciertos <= total),
  constraint puntos_validos  check (puntos <= total * 250)  -- máximo posible por pregunta
);

alter table public.partidas enable row level security;

-- Cualquiera puede ver el ranking y guardar su partida, pero nadie puede modificar ni borrar desde la web.
drop policy if exists "ver partidas" on public.partidas;
create policy "ver partidas" on public.partidas for select to anon, authenticated using (true);
drop policy if exists "guardar partida" on public.partidas;
create policy "guardar partida" on public.partidas for insert to anon, authenticated with check (true);

grant select, insert on public.partidas to anon, authenticated;

-- Puntos acumulados por jugador
create or replace view public.hall_of_fame with (security_invoker = true) as
select
  clave,
  (array_agg(nombre order by creado desc))[1] as nombre,
  sum(puntos)::int   as puntos,
  count(*)::int      as partidas,
  sum(aciertos)::int as aciertos,
  sum(total)::int    as total,
  max(puntos)::int   as mejor
from public.partidas
group by clave;

grant select on public.hall_of_fame to anon, authenticated;

-- Para empezar una temporada nueva (borra TODAS las puntuaciones), ejecuta solo:
--   truncate public.partidas;


-- ===================================================================
-- estadisticas.sql
-- ===================================================================
-- Estadísticas anónimas de uso para Sabelotodo
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".

create table if not exists public.eventos (
  id          bigint generated always as identity primary key,
  tipo        text not null check (tipo in ('visita','inicio','fin','abandono')),
  dispositivo text check (dispositivo in ('movil','tablet','escritorio')),
  categoria   text check (char_length(categoria) <= 40),
  dificultad  text check (char_length(dificultad) <= 10),
  preguntas   integer check (preguntas between 0 and 2000),
  aciertos    integer check (aciertos between 0 and 2000),
  puntos      integer check (puntos between 0 and 500000),
  creado      timestamptz not null default now()
);

alter table public.eventos enable row level security;

-- La web solo puede AÑADIR eventos; nadie puede leerlos, modificarlos ni borrarlos desde fuera.
drop policy if exists "registrar evento" on public.eventos;
create policy "registrar evento" on public.eventos for insert to anon, authenticated with check (true);
grant insert on public.eventos to anon, authenticated;

-- Resúmenes por día (solo totales, sin datos individuales), en hora de Madrid
create or replace view public.stats_diarias as
select (creado at time zone 'Europe/Madrid')::date as dia,
  count(*) filter (where tipo = 'visita')                               as visitas,
  count(*) filter (where tipo = 'visita' and dispositivo = 'movil')     as visitas_movil,
  count(*) filter (where tipo = 'visita' and dispositivo = 'tablet')    as visitas_tablet,
  count(*) filter (where tipo = 'visita' and dispositivo = 'escritorio') as visitas_escritorio,
  count(*) filter (where tipo = 'inicio')                               as partidas_iniciadas,
  count(*) filter (where tipo = 'fin')                                  as partidas_terminadas,
  count(*) filter (where tipo = 'abandono')                             as abandonos,
  round(avg(puntos) filter (where tipo = 'fin'))::int                   as puntos_medios,
  round(100.0 * sum(aciertos) filter (where tipo = 'fin') / nullif(sum(preguntas) filter (where tipo = 'fin'), 0), 1) as pct_aciertos
from public.eventos group by 1;

create or replace view public.stats_categorias as
select (creado at time zone 'Europe/Madrid')::date as dia,
  coalesce(nullif(categoria, ''), 'Todas') as categoria,
  count(*) as partidas
from public.eventos where tipo = 'inicio' group by 1, 2;

create or replace view public.stats_jugadores as
select (creado at time zone 'Europe/Madrid')::date as dia,
  count(*)              as partidas_guardadas,
  count(distinct clave) as jugadores,
  max(puntos)           as mejor_puntuacion,
  (array_agg(nombre order by puntos desc))[1] as mejor_jugador
from public.partidas group by 1;

grant select on public.stats_diarias, public.stats_categorias, public.stats_jugadores to anon, authenticated;


-- ===================================================================
-- hall_of_fame_mensual.sql
-- ===================================================================
-- Hall of Fame mensual + campeones de cada mes para Sabelotodo
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- No borra nada: el ranking del mes solo cuenta las partidas del mes en curso (hora de Madrid),
-- así que se "vacía" solo el día 1 a las 00:00. Las partidas antiguas se usan para los campeones.

-- Ranking acumulado del mes en curso
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
select
  clave,
  (array_agg(nombre order by creado desc))[1] as nombre,
  sum(puntos)::int   as puntos,
  count(*)::int      as partidas,
  sum(aciertos)::int as aciertos,
  sum(total)::int    as total,
  max(puntos)::int   as mejor
from public.partidas
where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
group by clave;

-- Mejores partidas sueltas del mes en curso
create or replace view public.mejores_partidas_mes with (security_invoker = true) as
select nombre, puntos, aciertos, total, creado
from public.partidas
where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid');

-- Top 3 de cada mes ya terminado
create or replace view public.campeones_mensuales with (security_invoker = true) as
with m as (
  select
    to_char(date_trunc('month', creado at time zone 'Europe/Madrid'), 'YYYY-MM') as mes,
    clave,
    (array_agg(nombre order by creado desc))[1] as nombre,
    sum(puntos)::int as puntos,
    count(*)::int    as partidas,
    max(puntos)::int as mejor
  from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') < date_trunc('month', now() at time zone 'Europe/Madrid')
  group by 1, 2
), r as (
  select *, rank() over (partition by mes order by puntos desc, mejor desc) as puesto from m
)
select mes, puesto::int, nombre, puntos, partidas, mejor from r where puesto <= 3;

grant select on public.hall_of_fame_mes, public.mejores_partidas_mes, public.campeones_mensuales to anon, authenticated;


-- ===================================================================
-- reportes.sql
-- ===================================================================
-- Reportes de errores en preguntas para Sabelotodo
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".

create table if not exists public.reportes (
  id                 bigint generated always as identity primary key,
  pregunta           text not null check (char_length(pregunta) between 1 and 300),
  visual             text check (char_length(visual) <= 60),
  respuesta_correcta text check (char_length(respuesta_correcta) <= 150),
  categoria          text check (char_length(categoria) <= 40),
  motivo             text not null check (motivo in ('respuesta_erronea','varias_correctas','desactualizada','mal_escrita','otro')),
  comentario         text check (char_length(comentario) <= 300),
  creado             timestamptz not null default now()
);

alter table public.reportes enable row level security;

-- La web solo puede ENVIAR reportes; no puede leerlos, cambiarlos ni borrarlos.
drop policy if exists "enviar reporte" on public.reportes;
create policy "enviar reporte" on public.reportes for insert to anon, authenticated with check (true);
grant insert on public.reportes to anon, authenticated;

-- Resumen de los reportes de los últimos 30 días (lo usa la renovación semanal para corregir preguntas)
create or replace view public.reportes_recientes as
select
  pregunta,
  coalesce(visual, '')                 as visual,
  max(respuesta_correcta)              as respuesta_correcta,
  max(categoria)                       as categoria,
  motivo,
  count(*)::int                        as veces,
  string_agg(nullif(comentario, ''), ' | ' order by creado desc) as comentarios,
  max(creado)                          as ultimo
from public.reportes
where creado > now() - interval '30 days'
group by pregunta, coalesce(visual, ''), motivo;

grant select on public.reportes_recientes to anon, authenticated;


-- ===================================================================
-- evento.sql
-- ===================================================================
-- MODO EVENTO de Sabelotodo (pantalla grande + móviles)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Las tablas quedan cerradas: la web solo puede usarlas a través de las funciones de abajo,
-- que comprueban la clave secreta del presentador y el token de cada jugador.

create extension if not exists pgcrypto;

create table if not exists public.salas (
  codigo        text primary key,
  host_secret   text not null,
  estado        text not null default 'lobby' check (estado in ('lobby','pregunta','resultado','fin')),
  idx           integer not null default -1,
  total         integer not null default 10,
  segundos      integer not null default 20,
  pregunta      jsonb,
  correcta      integer,
  inicio        timestamptz,
  deadline      timestamptz,
  creado        timestamptz not null default now()
);

create table if not exists public.sala_jugadores (
  id      uuid primary key default gen_random_uuid(),
  codigo  text not null references public.salas(codigo) on delete cascade,
  nombre  text not null check (char_length(nombre) between 1 and 20),
  token   uuid not null default gen_random_uuid(),
  creado  timestamptz not null default now()
);
create unique index if not exists sala_jugadores_nombre on public.sala_jugadores (codigo, lower(nombre));

create table if not exists public.sala_preguntas (
  codigo    text not null references public.salas(codigo) on delete cascade,
  idx       integer not null,
  correcta  integer not null,
  segundos  integer not null,
  primary key (codigo, idx)
);

create table if not exists public.sala_respuestas (
  codigo   text not null references public.salas(codigo) on delete cascade,
  jugador  uuid not null references public.sala_jugadores(id) on delete cascade,
  idx      integer not null,
  opcion   integer not null check (opcion between 0 and 3),
  ms       integer not null,
  creado   timestamptz not null default now(),
  primary key (codigo, jugador, idx)
);

alter table public.salas           enable row level security;
alter table public.sala_jugadores  enable row level security;
alter table public.sala_preguntas  enable row level security;
alter table public.sala_respuestas enable row level security;
-- (sin políticas: nadie puede leer ni escribir directamente desde la web)

-- ---------- Funciones del presentador ----------
create or replace function public.ev_crear_sala(p_secret text, p_total int, p_segundos int)
returns text language plpgsql security definer set search_path = public as $$
declare c text; letras text := 'ABCDEFGHJKLMNPQRSTUVWXYZ'; i int;
begin
  if char_length(p_secret) < 16 then raise exception 'secreto no válido'; end if;
  loop
    c := '';
    for i in 1..4 loop c := c || substr(letras, 1 + floor(random() * length(letras))::int, 1); end loop;
    exit when not exists (select 1 from salas where codigo = c);
  end loop;
  insert into salas (codigo, host_secret, total, segundos)
  values (c, p_secret, greatest(1, least(p_total, 50)), greatest(10, least(p_segundos, 60)));
  delete from salas where creado < now() - interval '2 days';   -- limpieza de salas antiguas
  return c;
end $$;

create or replace function public.ev_pregunta(p_codigo text, p_secret text, p_idx int, p_pregunta jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare s salas;
begin
  select * into s from salas where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'sala no encontrada'; end if;
  update salas set estado = 'pregunta', idx = p_idx, pregunta = p_pregunta, correcta = null,
    inicio = now(), deadline = now() + make_interval(secs => s.segundos)
  where codigo = s.codigo;
end $$;

create or replace function public.ev_revelar(p_codigo text, p_secret text, p_correcta int)
returns void language plpgsql security definer set search_path = public as $$
declare s salas;
begin
  select * into s from salas where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'sala no encontrada'; end if;
  update salas set estado = 'resultado', correcta = p_correcta, deadline = least(deadline, now()) where codigo = s.codigo;
  insert into sala_preguntas (codigo, idx, correcta, segundos) values (s.codigo, s.idx, p_correcta, s.segundos)
  on conflict (codigo, idx) do update set correcta = excluded.correcta;
end $$;

create or replace function public.ev_fin(p_codigo text, p_secret text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update salas set estado = 'fin' where codigo = upper(p_codigo) and host_secret = p_secret;
end $$;

-- ---------- Funciones del jugador ----------
create or replace function public.ev_unirse(p_codigo text, p_nombre text)
returns table (jugador uuid, token uuid) language plpgsql security definer set search_path = public as $$
declare s salas; n text := btrim(p_nombre);
begin
  select * into s from salas where codigo = upper(p_codigo);
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  if s.estado = 'fin' then raise exception 'SALA_TERMINADA'; end if;
  if char_length(n) < 1 or char_length(n) > 20 then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if exists (select 1 from sala_jugadores j where j.codigo = s.codigo and lower(j.nombre) = lower(n)) then raise exception 'NOMBRE_OCUPADO'; end if;
  if (select count(*) from sala_jugadores j where j.codigo = s.codigo) >= 200 then raise exception 'SALA_LLENA'; end if;
  return query insert into sala_jugadores (codigo, nombre) values (s.codigo, n) returning id, sala_jugadores.token;
end $$;

create or replace function public.ev_responder(p_codigo text, p_jugador uuid, p_token uuid, p_idx int, p_opcion int)
returns integer language plpgsql security definer set search_path = public as $$
declare s salas; t int;
begin
  select * into s from salas where codigo = upper(p_codigo);
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  if not exists (select 1 from sala_jugadores where id = p_jugador and token = p_token and codigo = s.codigo) then raise exception 'JUGADOR_NO_VALIDO'; end if;
  if s.estado <> 'pregunta' or s.idx <> p_idx or now() > s.deadline + interval '1 second' then raise exception 'FUERA_DE_TIEMPO'; end if;
  t := greatest(0, least(s.segundos * 1000, (extract(epoch from (now() - s.inicio)) * 1000)::int));
  insert into sala_respuestas (codigo, jugador, idx, opcion, ms) values (s.codigo, p_jugador, p_idx, p_opcion, t)
  on conflict do nothing;
  return t;
end $$;

-- ---------- Vistas públicas (solo lo necesario para mostrar el juego) ----------
create or replace view public.ev_estado as
select codigo, estado, idx, total, segundos, pregunta, correcta, deadline, now() as ahora,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo)::int as jugadores,
  (select count(*) from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx)::int as respondidas
from salas s;

create or replace view public.ev_jugadores as
select codigo, nombre, creado from sala_jugadores;

create or replace view public.ev_votos as
select r.codigo, r.idx, r.opcion, count(*)::int as votos
from sala_respuestas r join salas s on s.codigo = r.codigo
where s.estado in ('resultado','fin') or r.idx < s.idx
group by r.codigo, r.idx, r.opcion;

-- 100 puntos por acierto + hasta 100 de bonus por rapidez
create or replace view public.ev_ranking as
select j.codigo, j.id as jugador, j.nombre,
  coalesce(sum(case when r.opcion = p.correcta then 100 + round(100.0 * greatest(0, p.segundos * 1000 - r.ms) / (p.segundos * 1000)) end), 0)::int as puntos,
  count(*) filter (where r.opcion = p.correcta)::int as aciertos
from sala_jugadores j
left join sala_respuestas r on r.jugador = j.id
left join sala_preguntas p on p.codigo = r.codigo and p.idx = r.idx
group by j.codigo, j.id, j.nombre;

grant select on public.ev_estado, public.ev_jugadores, public.ev_votos, public.ev_ranking to anon, authenticated;
grant execute on function public.ev_crear_sala(text,int,int), public.ev_pregunta(text,text,int,jsonb), public.ev_revelar(text,text,int),
  public.ev_fin(text,text), public.ev_unirse(text,text), public.ev_responder(text,uuid,uuid,int,int) to anon, authenticated;
create or replace function public.ev_salir(p_jugador uuid, p_token uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from sala_jugadores where id = p_jugador and token = p_token;
end $$;
grant execute on function public.ev_salir(uuid, uuid) to anon, authenticated;


-- ===================================================================
-- evento_salir.sql
-- ===================================================================
-- Permite que un jugador salga de una sala del modo evento.
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run" (si ya ejecutaste evento.sql).
create or replace function public.ev_salir(p_jugador uuid, p_token uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from sala_jugadores where id = p_jugador and token = p_token;
end $$;
grant execute on function public.ev_salir(uuid, uuid) to anon, authenticated;


-- ===================================================================
-- pin.sql
-- ===================================================================
-- PIN de 4 cifras para proteger los nombres del Hall of Fame (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
--
-- ADMINISTRACIÓN (ejecutar a mano cuando haga falta):
--   · Borrar el PIN de un jugador (si lo olvida o alguien se lo "robó"); la próxima vez que juegue podrá crear uno nuevo:
--       delete from public.jugadores_pin where clave = 'aliceinhell';
--     (la clave es el nombre en minúsculas, sin espacios, tildes ni símbolos: "Alice InHell" -> aliceinhell)
--   · Asignar tú un PIN a un jugador y dárselo en privado:
--       insert into public.jugadores_pin (clave, pin_hash) values ('aliceinhell', extensions.crypt('1234', extensions.gen_salt('bf')))
--       on conflict (clave) do update set pin_hash = excluded.pin_hash, fallos = 0, bloqueado_hasta = null;
--   · Ver qué nombres tienen PIN:
--       select clave, creado from public.jugadores_pin order by creado desc;

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.jugadores_pin (
  clave            text primary key check (char_length(clave) between 1 and 40),
  pin_hash         text not null,
  fallos           integer not null default 0,
  bloqueado_hasta  timestamptz,
  creado           timestamptz not null default now()
);
alter table public.jugadores_pin enable row level security;   -- sin políticas: nadie la lee desde la web

-- ¿El nombre está libre, tiene puntos pero no PIN, o ya tiene PIN?
create or replace function public.pin_estado(p_clave text)
returns text language sql stable security definer set search_path = public, extensions as $$
  select case
    when exists (select 1 from jugadores_pin where clave = p_clave) then 'con_pin'
    when exists (select 1 from partidas where clave = p_clave) then 'sin_pin'
    else 'libre' end
$$;

-- Crear el PIN (solo si el nombre aún no tiene uno)
create or replace function public.pin_crear(p_clave text, p_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_clave is null or char_length(p_clave) < 1 or char_length(p_clave) > 40 or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN_NO_VALIDO'; end if;
  insert into jugadores_pin (clave, pin_hash) values (p_clave, crypt(p_pin, gen_salt('bf'))) on conflict (clave) do nothing;
  return found;
end $$;

-- Comprobar el PIN: 'ok', 'mal', 'bloqueado' (5 fallos -> 15 minutos) o 'sin_pin'
create or replace function public.pin_comprobar(p_clave text, p_pin text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare r jugadores_pin;
begin
  select * into r from jugadores_pin where clave = p_clave;
  if not found then return 'sin_pin'; end if;
  if r.bloqueado_hasta is not null and r.bloqueado_hasta > now() then return 'bloqueado'; end if;
  if r.pin_hash = crypt(coalesce(p_pin, ''), r.pin_hash) then
    update jugadores_pin set fallos = 0, bloqueado_hasta = null where clave = p_clave;
    return 'ok';
  end if;
  update jugadores_pin set
    bloqueado_hasta = case when fallos + 1 >= 5 then now() + interval '15 minutes' else null end,
    fallos = case when fallos + 1 >= 5 then 0 else fallos + 1 end
  where clave = p_clave;
  return 'mal';
end $$;

-- Guardar una partida comprobando el PIN si el nombre lo tiene
create or replace function public.guardar_partida(p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is not null and (p_pin is null or h <> crypt(p_pin, h)) then raise exception 'PIN_INCORRECTO'; end if;
  insert into partidas (nombre, clave, puntos, aciertos, total) values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total);
end $$;

grant execute on function public.pin_estado(text), public.pin_crear(text,text), public.pin_comprobar(text,text),
  public.guardar_partida(text,text,int,int,int,text) to anon, authenticated;

-- A partir de ahora las partidas solo se guardan a través de guardar_partida (con comprobación de PIN)
drop policy if exists "guardar partida" on public.partidas;
revoke insert on public.partidas from anon, authenticated;


-- ===================================================================
-- retos_perfil.sql
-- ===================================================================
-- Reto diario + perfil de jugador con logros (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Necesita haber ejecutado antes pin.sql.
-- No borra nada: añade columnas a "partidas" y crea la tabla "retos".
--
-- ADMINISTRACIÓN:
--   · Ver el ranking del reto de hoy:   select * from public.reto_hoy;
--   · Anular el reto de un jugador hoy: delete from public.retos where clave = 'aliceinhell' and fecha = (now() at time zone 'Europe/Madrid')::date;

-- 1) Datos extra de cada partida (para el perfil y los logros)
alter table public.partidas add column if not exists modo    text  not null default 'normal';
alter table public.partidas add column if not exists racha   integer;
alter table public.partidas add column if not exists detalle jsonb;   -- {"Categoría": [aciertos, preguntas], ...}

-- 2) Reto diario: una sola partida por jugador y día
create table if not exists public.retos (
  fecha     date not null,
  clave     text not null check (char_length(clave) between 1 and 40),
  nombre    text not null check (char_length(nombre) between 1 and 24),
  puntos    integer not null check (puntos between 0 and 2500),
  aciertos  integer not null check (aciertos between 0 and 10),
  total     integer not null check (total = 10),
  cuadro    text,                                -- 🟩🟥⬛ para compartir
  creado    timestamptz not null default now(),
  primary key (fecha, clave)
);
alter table public.retos enable row level security;
drop policy if exists "ver retos" on public.retos;
create policy "ver retos" on public.retos for select to anon, authenticated using (true);
grant select on public.retos to anon, authenticated;

create or replace view public.reto_hoy with (security_invoker = true) as
select nombre, clave, puntos, aciertos, total, cuadro, creado
from public.retos
where fecha = (now() at time zone 'Europe/Madrid')::date;
grant select on public.reto_hoy to anon, authenticated;

-- 3) Guardar partida (normal o reto) comprobando el PIN.
--    Devuelve 'ok', o 'repetido' si ese nombre ya jugó hoy el reto (y entonces no guarda nada).
create or replace function public.guardar_partida2(
  p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text,
  p_modo text default 'normal', p_racha int default null, p_detalle jsonb default null, p_cuadro text default null)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare h text; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is not null and (p_pin is null or h <> crypt(p_pin, h)) then raise exception 'PIN_INCORRECTO'; end if;
  if p_modo = 'reto' then
    if p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
    insert into retos (fecha, clave, nombre, puntos, aciertos, total, cuadro)
      values (hoy, left(p_clave, 40), left(p_nombre, 24), p_puntos, p_aciertos, p_total, left(p_cuadro, 40))
      on conflict (fecha, clave) do nothing;
    if not found then return 'repetido'; end if;
  end if;
  insert into partidas (nombre, clave, puntos, aciertos, total, modo, racha, detalle)
    values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total,
            case when p_modo = 'reto' then 'reto' else 'normal' end,
            greatest(0, least(coalesce(p_racha, 0), p_total)),
            case when jsonb_typeof(p_detalle) = 'object' and length(p_detalle::text) < 2000 then p_detalle end);
  return 'ok';
end $$;
grant execute on function public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text) to anon, authenticated;

-- clave a partir del nombre (igual que hace la web): minúsculas, sin tildes ni símbolos
create extension if not exists unaccent with schema extensions;
create or replace function public.norm_clave(t text)
returns text language sql immutable set search_path = public, extensions as $$
  select regexp_replace(lower(extensions.unaccent(coalesce(t, ''))), '[^a-z0-9]', '', 'g')
$$;


-- 4) Perfil público de un jugador (lo mismo que ya se ve en el Hall of Fame, pero detallado)
create or replace function public.perfil(p_clave text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb; cats jsonb; dias date[]; racha_reto int := 0; racha_max int := 0; cur int := 0; prev date; d date; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  select jsonb_build_object(
      'nombre',    (array_agg(nombre order by creado desc))[1],
      'partidas',  count(*),
      'puntos',    coalesce(sum(puntos), 0),
      'mejor',     coalesce(max(puntos), 0),
      'aciertos',  coalesce(sum(aciertos), 0),
      'total',     coalesce(sum(total), 0),
      'perfectas', count(*) filter (where aciertos = total and total >= 10),
      'racha',     coalesce(max(racha), 0),
      'noche',     count(*) filter (where extract(hour from creado at time zone 'Europe/Madrid') < 6),
      'desde',     min(creado),
      'mes_puntos', coalesce(sum(puntos) filter (where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')), 0))
    into r from partidas where clave = p_clave;
  if (r->>'partidas')::int = 0 then return null; end if;

  select coalesce(jsonb_object_agg(cat, jsonb_build_array(ok, tot)), '{}'::jsonb) into cats from (
    select e.key as cat, sum((e.value->>0)::int) as ok, sum((e.value->>1)::int) as tot
    from partidas p, jsonb_each(p.detalle) e
    where p.clave = p_clave and jsonb_typeof(p.detalle) = 'object' and jsonb_typeof(e.value) = 'array'
    group by e.key) c;

  -- días seguidos jugando el reto: racha actual (hasta hoy o ayer) y mejor racha
  select array_agg(fecha order by fecha desc) into dias from retos where clave = p_clave;
  if dias is not null then
    foreach d in array dias loop
      if prev is not null and d = prev - 1 then cur := cur + 1; else cur := 1; end if;
      if cur > racha_max then racha_max := cur; end if;
      prev := d;
    end loop;
    if dias[1] >= hoy - 1 then
      foreach d in array dias loop
        if d = dias[1] - racha_reto then racha_reto := racha_reto + 1; else exit; end if;
      end loop;
    end if;
  end if;

  return r || jsonb_build_object(
    'categorias', cats,
    'retos', coalesce(array_length(dias, 1), 0),
    'racha_reto', racha_reto,
    'racha_reto_max', racha_max,
    'retos_ganados', (select count(*) from (
        select fecha, clave, rank() over (partition by fecha order by puntos desc, creado) as pos from retos
        where fecha in (select fecha from retos where clave = p_clave) and fecha < hoy) x
      where x.clave = p_clave and x.pos = 1),
    'mejor_reto', (select max(puntos) from retos where clave = p_clave),
    'campeon', (select count(*) from campeones_mensuales c where c.puesto = 1 and norm_clave(c.nombre) = p_clave),
    'podios',  (select count(*) from campeones_mensuales c where norm_clave(c.nombre) = p_clave));
end $$;

grant execute on function public.perfil(text), public.norm_clave(text) to anon, authenticated;

-- 5) Estadísticas: nuevos tipos de evento (compartir resultado, imagen, perfil) y su resumen diario
alter table public.eventos drop constraint if exists eventos_tipo_check;
alter table public.eventos add constraint eventos_tipo_check
  check (tipo in ('visita','inicio','fin','abandono','compartir','imagen','perfil','instalar'));

create or replace view public.stats_novedades as
select d.dia,
  coalesce(e.compartidos, 0) as compartidos, coalesce(e.imagenes, 0) as imagenes, coalesce(e.perfiles, 0) as perfiles,
  coalesce(r.retos, 0) as retos_jugados, r.mejor_reto, r.ganador_reto, coalesce(e.instalaciones, 0) as instalaciones
from (select (creado at time zone 'Europe/Madrid')::date as dia from public.eventos
      union select fecha from public.retos) d
left join (select (creado at time zone 'Europe/Madrid')::date as dia,
      count(*) filter (where tipo = 'compartir') as compartidos,
      count(*) filter (where tipo = 'imagen')    as imagenes,
      count(*) filter (where tipo = 'perfil')    as perfiles,
      count(*) filter (where tipo = 'instalar')  as instalaciones
    from public.eventos group by 1) e on e.dia = d.dia
left join (select fecha as dia, count(*) as retos, max(puntos) as mejor_reto,
      (array_agg(nombre order by puntos desc, creado))[1] as ganador_reto
    from public.retos group by 1) r on r.dia = d.dia;
grant select on public.stats_novedades to anon, authenticated;

-- Veces que se ha compartido el resultado, por red social (instagram, facebook, whatsapp, x, copiar, descargar, mas)
create or replace view public.stats_compartir as
select (creado at time zone 'Europe/Madrid')::date as dia, coalesce(nullif(dificultad, ''), 'texto') as red, count(*) as veces
from public.eventos where tipo = 'compartir' group by 1, 2;
grant select on public.stats_compartir to anon, authenticated;


-- ===================================================================
-- preguntas_vistas.sql
-- ===================================================================
-- Cuántas veces ha salido cada pregunta (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
-- La renovación semanal de los viernes retira las preguntas que más veces han salido.
--
-- Consultas útiles:
--   · Las 30 que más han salido:  select * from public.preguntas_ranking limit 30;
--   · Empezar el recuento de cero: truncate public.preguntas_vistas;

create table if not exists public.preguntas_vistas (
  pregunta    text not null check (char_length(pregunta) between 1 and 300),
  visual      text not null default '' check (char_length(visual) <= 120),
  veces       integer not null default 0,   -- partidas (o rondas de evento) en las que ha salido
  respuestas  integer not null default 0,   -- respuestas recibidas (en el modo evento, una por jugador)
  aciertos    integer not null default 0,
  primera     timestamptz not null default now(),
  ultima      timestamptz not null default now(),
  primary key (pregunta, visual)
);
alter table public.preguntas_vistas enable row level security;
drop policy if exists "ver preguntas vistas" on public.preguntas_vistas;
create policy "ver preguntas vistas" on public.preguntas_vistas for select to anon, authenticated using (true);
grant select on public.preguntas_vistas to anon, authenticated;

-- La web envía al terminar (o abandonar) la lista de preguntas que han salido:
--   [{"q": "texto", "v": "visual", "r": respuestas, "a": aciertos}, ...]
create or replace function public.contar_preguntas(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 60 then return; end if;
  insert into preguntas_vistas as t (pregunta, visual, veces, respuestas, aciertos)
  select left(e->>'q', 300), left(coalesce(e->>'v', ''), 120), count(*),
         sum(least(greatest(coalesce((e->>'r')::int, 1), 0), 500)),
         sum(least(greatest(coalesce((e->>'a')::int, 0), 0), 500))
  from jsonb_array_elements(p) e
  where coalesce(e->>'q', '') <> ''
  group by 1, 2
  on conflict (pregunta, visual) do update set
    veces = t.veces + excluded.veces,
    respuestas = t.respuestas + excluded.respuestas,
    aciertos = t.aciertos + least(excluded.aciertos, excluded.respuestas),
    ultima = now();
end $$;
grant execute on function public.contar_preguntas(jsonb) to anon, authenticated;

create or replace view public.preguntas_ranking with (security_invoker = true) as
select pregunta, visual, veces, respuestas, aciertos,
       case when respuestas > 0 then round(100.0 * aciertos / respuestas)::int end as pct_aciertos,
       primera, ultima
from public.preguntas_vistas
order by veces desc, respuestas desc;
grant select on public.preguntas_ranking to anon, authenticated;


-- ===================================================================
-- premios_reto.sql
-- ===================================================================
-- Premio del reto diario en el ranking mensual + puntos por dificultad (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Necesita haber ejecutado antes retos_perfil.sql.
-- No borra nada. Los premios empiezan a contar con los retos del 1 de diciembre de 2026.
--
-- PREMIOS: al cerrarse cada día (medianoche, hora de Madrid), los tres mejores del reto de ese día suman
--          +500 / +300 / +150 puntos al ranking del mes. Solo si ese día jugaron al menos 3 personas.
--          Empate a puntos: gana quien terminó antes.
-- Consultas útiles:  select * from public.reto_premios order by fecha desc, puesto;

-- 1) Nuevos límites de puntos (con puntos por dificultad una pregunta difícil puede dar hasta 350)
alter table public.partidas drop constraint if exists puntos_validos;
alter table public.partidas add constraint puntos_validos check (puntos <= total * 350);
alter table public.retos drop constraint if exists retos_puntos_check;
alter table public.retos add constraint retos_puntos_check check (puntos between 0 and 3500);

-- 2) Premios de cada reto ya cerrado
create or replace view public.reto_premios with (security_invoker = true) as
with d as (
  select fecha, clave, nombre, puntos, creado,
         row_number() over (partition by fecha order by puntos desc, creado) as puesto,
         count(*) over (partition by fecha) as jugadores
  from public.retos
  where fecha >= date '2026-11-01'
    and fecha < (now() at time zone 'Europe/Madrid')::date
)
select fecha, clave, nombre, puesto::int as puesto, jugadores::int as jugadores,
       (case puesto when 1 then 500 when 2 then 300 else 150 end)::int as bonus
from d
where jugadores >= 3 and puesto <= 3;
grant select on public.reto_premios to anon, authenticated;

-- 3) Ranking del mes en curso: partidas + premios del reto (mismas columnas que antes y dos nuevas al final)
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
select g.clave, g.nombre,
       (g.puntos + coalesce(b.bonus, 0))::int as puntos,
       g.partidas, g.aciertos, g.total, g.mejor,
       coalesce(b.bonus, 0)::int     as bonus_reto,
       coalesce(b.victorias, 0)::int as retos_ganados
from (
  select clave,
         (array_agg(nombre order by creado desc))[1] as nombre,
         sum(puntos)::int as puntos, count(*)::int as partidas,
         sum(aciertos)::int as aciertos, sum(total)::int as total, max(puntos)::int as mejor
  from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
) g
left join (
  select clave, sum(bonus) as bonus, count(*) filter (where puesto = 1) as victorias
  from public.reto_premios
  where date_trunc('month', fecha::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
) b using (clave);

-- 4) Campeones de cada mes terminado, también con los premios del reto
create or replace view public.campeones_mensuales with (security_invoker = true) as
with m as (
  select to_char(date_trunc('month', creado at time zone 'Europe/Madrid'), 'YYYY-MM') as mes,
         clave,
         (array_agg(nombre order by creado desc))[1] as nombre,
         sum(puntos)::int as puntos, count(*)::int as partidas, max(puntos)::int as mejor
  from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') < date_trunc('month', now() at time zone 'Europe/Madrid')
  group by 1, 2
), b as (
  select to_char(fecha, 'YYYY-MM') as mes, clave, sum(bonus)::int as bonus
  from public.reto_premios group by 1, 2
), t as (
  select m.mes, m.clave, m.nombre, (m.puntos + coalesce(b.bonus, 0))::int as puntos, m.partidas, m.mejor,
         coalesce(b.bonus, 0)::int as bonus_reto
  from m left join b on b.mes = m.mes and b.clave = m.clave
), r as (
  select *, rank() over (partition by mes order by puntos desc, mejor desc) as puesto from t
)
select mes, puesto::int, nombre, puntos, partidas, mejor, bonus_reto from r where puesto <= 3;

grant select on public.hall_of_fame_mes, public.campeones_mensuales to anon, authenticated;


-- ===================================================================
-- ranking_diario.sql
-- ===================================================================
-- Ranking mensual por MEJOR PARTIDA DE CADA DÍA (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Necesita haber ejecutado antes premios_reto.sql.
-- No borra nada. Hasta el 30-11-2026 el ranking sigue sumando todas las partidas (como siempre).
-- Desde el 1-12-2026: cada jugador suma, por cada día, solo su mejor partida de hasta 20 preguntas
-- (las partidas con más preguntas no puntúan para el ranking), más los premios del reto diario.

-- Partidas que cuentan para el ranking de su mes
create or replace view public.partidas_ranking with (security_invoker = true) as
with p as (
  select clave, nombre, puntos, aciertos, total, creado,
         (creado at time zone 'Europe/Madrid')::date as dia
  from public.partidas
), c as (
  select *, row_number() over (partition by clave, dia order by puntos desc, creado) as n
  from p
  where dia < date '2026-11-01' or total <= 20
)
select clave, nombre, puntos, aciertos, total, creado, dia
from c
where dia < date '2026-11-01' or n = 1;
grant select on public.partidas_ranking to anon, authenticated;

-- Ranking del mes en curso (mismas columnas que antes y "dias" al final)
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
with mes as (
  select * from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
), todas as (                      -- estadísticas de todas las partidas del mes
  select clave, (array_agg(nombre order by creado desc))[1] as nombre, count(*)::int as partidas,
         sum(aciertos)::int as aciertos, sum(total)::int as total
  from mes group by clave
), cuentan as (                    -- puntos que cuentan para el ranking
  select clave, sum(puntos)::int as puntos, max(puntos)::int as mejor, count(distinct dia)::int as dias
  from public.partidas_ranking
  where date_trunc('month', dia::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
), b as (
  select clave, sum(bonus) as bonus, count(*) filter (where puesto = 1) as victorias
  from public.reto_premios
  where date_trunc('month', fecha::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
)
select t.clave, t.nombre,
       (coalesce(c.puntos, 0) + coalesce(b.bonus, 0))::int as puntos,
       t.partidas, t.aciertos, t.total,
       coalesce(c.mejor, 0)::int     as mejor,
       coalesce(b.bonus, 0)::int     as bonus_reto,
       coalesce(b.victorias, 0)::int as retos_ganados,
       coalesce(c.dias, 0)::int      as dias
from todas t
left join cuentan c using (clave)
left join b using (clave);

-- Mejores partidas del mes (desde diciembre, solo las de hasta 20 preguntas)
create or replace view public.mejores_partidas_mes with (security_invoker = true) as
select nombre, puntos, aciertos, total, creado
from public.partidas
where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
  and ((creado at time zone 'Europe/Madrid')::date < date '2026-11-01' or total <= 20);

-- Campeones de cada mes terminado, con la misma regla
create or replace view public.campeones_mensuales with (security_invoker = true) as
with m as (
  select to_char(dia, 'YYYY-MM') as mes, clave,
         (array_agg(nombre order by creado desc))[1] as nombre,
         sum(puntos)::int as puntos, count(*)::int as partidas, max(puntos)::int as mejor
  from public.partidas_ranking
  where date_trunc('month', dia::timestamp) < date_trunc('month', now() at time zone 'Europe/Madrid')
  group by 1, 2
), b as (
  select to_char(fecha, 'YYYY-MM') as mes, clave, sum(bonus)::int as bonus
  from public.reto_premios group by 1, 2
), t as (
  select m.mes, m.clave, m.nombre, (m.puntos + coalesce(b.bonus, 0))::int as puntos, m.partidas, m.mejor,
         coalesce(b.bonus, 0)::int as bonus_reto
  from m left join b on b.mes = m.mes and b.clave = m.clave
), r as (
  select *, rank() over (partition by mes order by puntos desc, mejor desc) as puesto from t
)
select mes, puesto::int, nombre, puntos, partidas, mejor, bonus_reto from r where puesto <= 3;

grant select on public.hall_of_fame_mes, public.mejores_partidas_mes, public.campeones_mensuales to anon, authenticated;


-- ===================================================================
-- campeonato.sql
-- ===================================================================
-- Partidas de CAMPEONATO y de PRÁCTICA (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Sustituye a ranking_diario.sql (puedes ejecutarlo encima).
-- No borra nada. Desde el 1-12-2026:
--   · Campeonato: 20 preguntas, dificultad automática, todas las categorías. Es lo que puntúa: cada día cuenta
--     la mejor partida de campeonato (o el reto, si es mejor) de cada jugador, más los premios del reto.
--   · Práctica: el jugador elige preguntas, dificultad y categoría. Se guarda (perfil), pero no puntúa.

-- Guardar partida: ahora distingue campeonato / práctica / reto
create or replace function public.guardar_partida2(
  p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text,
  p_modo text default 'normal', p_racha int default null, p_detalle jsonb default null, p_cuadro text default null)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare h text; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is not null and (p_pin is null or h <> crypt(p_pin, h)) then raise exception 'PIN_INCORRECTO'; end if;
  if p_modo = 'reto' then
    if p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
    insert into retos (fecha, clave, nombre, puntos, aciertos, total, cuadro)
      values (hoy, left(p_clave, 40), left(p_nombre, 24), p_puntos, p_aciertos, p_total, left(p_cuadro, 40))
      on conflict (fecha, clave) do nothing;
    if not found then return 'repetido'; end if;
  end if;
  insert into partidas (nombre, clave, puntos, aciertos, total, modo, racha, detalle)
    values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total,
            case when p_modo in ('reto', 'campeonato', 'practica') then p_modo else 'normal' end,
            greatest(0, least(coalesce(p_racha, 0), p_total)),
            case when jsonb_typeof(p_detalle) = 'object' and length(p_detalle::text) < 2000 then p_detalle end);
  return 'ok';
end $$;
grant execute on function public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text) to anon, authenticated;

-- Partidas que cuentan para el ranking de su mes
create or replace view public.partidas_ranking with (security_invoker = true) as
with p as (
  select clave, nombre, puntos, aciertos, total, creado, modo,
         (creado at time zone 'Europe/Madrid')::date as dia
  from public.partidas
), c as (
  select *, row_number() over (partition by clave, dia order by puntos desc, creado) as n
  from p
  where dia < date '2026-11-01' or (total <= 20 and coalesce(modo, 'normal') <> 'practica')
)
select clave, nombre, puntos, aciertos, total, creado, dia
from c
where dia < date '2026-11-01' or n = 1;
grant select on public.partidas_ranking to anon, authenticated;

-- Ranking del mes en curso (mismas columnas que antes y "dias" al final)
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
with mes as (                      -- partidas del mes (desde diciembre, sin las de práctica)
  select * from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
    and ((creado at time zone 'Europe/Madrid')::date < date '2026-11-01' or coalesce(modo, 'normal') <> 'practica')
), todas as (                      -- estadísticas de todas las partidas del mes
  select clave, (array_agg(nombre order by creado desc))[1] as nombre, count(*)::int as partidas,
         sum(aciertos)::int as aciertos, sum(total)::int as total
  from mes group by clave
), cuentan as (                    -- puntos que cuentan para el ranking
  select clave, sum(puntos)::int as puntos, max(puntos)::int as mejor, count(distinct dia)::int as dias
  from public.partidas_ranking
  where date_trunc('month', dia::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
), b as (
  select clave, sum(bonus) as bonus, count(*) filter (where puesto = 1) as victorias
  from public.reto_premios
  where date_trunc('month', fecha::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
)
select t.clave, t.nombre,
       (coalesce(c.puntos, 0) + coalesce(b.bonus, 0))::int as puntos,
       t.partidas, t.aciertos, t.total,
       coalesce(c.mejor, 0)::int     as mejor,
       coalesce(b.bonus, 0)::int     as bonus_reto,
       coalesce(b.victorias, 0)::int as retos_ganados,
       coalesce(c.dias, 0)::int      as dias
from todas t
left join cuentan c using (clave)
left join b using (clave);

-- Mejores partidas del mes (desde diciembre, solo las de hasta 20 preguntas)
create or replace view public.mejores_partidas_mes with (security_invoker = true) as
select nombre, puntos, aciertos, total, creado
from public.partidas
where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
  and ((creado at time zone 'Europe/Madrid')::date < date '2026-11-01' or (total <= 20 and coalesce(modo, 'normal') <> 'practica'));

-- Campeones de cada mes terminado, con la misma regla
create or replace view public.campeones_mensuales with (security_invoker = true) as
with m as (
  select to_char(dia, 'YYYY-MM') as mes, clave,
         (array_agg(nombre order by creado desc))[1] as nombre,
         sum(puntos)::int as puntos, count(*)::int as partidas, max(puntos)::int as mejor
  from public.partidas_ranking
  where date_trunc('month', dia::timestamp) < date_trunc('month', now() at time zone 'Europe/Madrid')
  group by 1, 2
), b as (
  select to_char(fecha, 'YYYY-MM') as mes, clave, sum(bonus)::int as bonus
  from public.reto_premios group by 1, 2
), t as (
  select m.mes, m.clave, m.nombre, (m.puntos + coalesce(b.bonus, 0))::int as puntos, m.partidas, m.mejor,
         coalesce(b.bonus, 0)::int as bonus_reto
  from m left join b on b.mes = m.mes and b.clave = m.clave
), r as (
  select *, rank() over (partition by mes order by puntos desc, mejor desc) as puesto from t
)
select mes, puesto::int, nombre, puntos, partidas, mejor, bonus_reto from r where puesto <= 3;

grant select on public.hall_of_fame_mes, public.mejores_partidas_mes, public.campeones_mensuales to anon, authenticated;


-- ===================================================================
-- login_obligatorio.sql
-- ===================================================================
-- Acceso obligatorio con nombre + PIN (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
-- A partir de ahora solo se guardan partidas de jugadores con PIN y con el PIN correcto:
-- se acaban las partidas como «Anónimo» y los nombres sin proteger.

create or replace function public.guardar_partida2(
  p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text,
  p_modo text default 'normal', p_racha int default null, p_detalle jsonb default null, p_cuadro text default null)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare h text; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  if p_clave is null or p_clave = '' or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is null then raise exception 'PIN_OBLIGATORIO'; end if;
  if p_pin is null or h <> crypt(p_pin, h) then raise exception 'PIN_INCORRECTO'; end if;
  if p_modo = 'reto' then
    insert into retos (fecha, clave, nombre, puntos, aciertos, total, cuadro)
      values (hoy, left(p_clave, 40), left(p_nombre, 24), p_puntos, p_aciertos, p_total, left(p_cuadro, 40))
      on conflict (fecha, clave) do nothing;
    if not found then return 'repetido'; end if;
  end if;
  insert into partidas (nombre, clave, puntos, aciertos, total, modo, racha, detalle)
    values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total,
            case when p_modo in ('reto', 'campeonato', 'practica') then p_modo else 'normal' end,
            greatest(0, least(coalesce(p_racha, 0), p_total)),
            case when jsonb_typeof(p_detalle) = 'object' and length(p_detalle::text) < 2000 then p_detalle end);
  return 'ok';
end $$;
grant execute on function public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text) to anon, authenticated;

-- La función antigua de guardado (sin modo) deja de aceptar partidas
do $$ begin
  if exists (select 1 from pg_proc where proname = 'guardar_partida' and pronamespace = 'public'::regnamespace) then
    execute 'revoke execute on function public.guardar_partida from anon, authenticated';
  end if;
exception when others then null; end $$;

-- Las partidas antiguas de «Anónimo» se conservan, pero la web ya no las muestra en el ranking.


-- ===================================================================
-- nombres_ofensivos.sql
-- ===================================================================
-- Filtro de nombres ofensivos (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
--
-- Impide crear usuarios (y guardar partidas) con insultos, palabras groseras o discriminatorias
-- en castellano, catalán o inglés. Detecta trucos habituales: mayúsculas, tildes, letras repetidas
-- ("puuuta"), números por letras ("put4", "m13rda") y símbolos ("p.u.t.a").
--
-- Dos tipos de palabra:
--   'contiene' → se bloquea aunque vaya pegada a otras letras ("ElGilipollas").
--   'palabra'  → solo si aparece como palabra suelta, para no bloquear nombres inocentes
--                (p. ej. "culo" no bloquea "Vehículo"; "dick" no bloquea "Bruce Dickinson").
--
-- ADMINISTRACIÓN:
--   · Añadir una palabra:   insert into public.nombres_prohibidos values ('palabrota', 'contiene');
--   · Quitar una palabra:   delete from public.nombres_prohibidos where palabra = 'palabrota';
--   · Probar un nombre:     select public.nombre_ofensivo('Nombre de prueba');
--   · Ver nombres del ranking que ya lo incumplen:
--       select distinct nombre from public.partidas where public.nombre_ofensivo(nombre);

create extension if not exists unaccent with schema extensions;

create table if not exists public.nombres_prohibidos (
  palabra text primary key,
  modo    text not null default 'contiene' check (modo in ('contiene', 'palabra'))
);
alter table public.nombres_prohibidos enable row level security;   -- sin políticas: la lista no se puede leer desde la web

insert into public.nombres_prohibidos (palabra, modo) values
  -- castellano
  ('hijodeputa','contiene'),('hijaputa','contiene'),('hijoputa','contiene'),('gilipollas','contiene'),('gilipoya','contiene'),
  ('maricon','contiene'),('subnormal','contiene'),('retrasado','contiene'),('malparido','contiene'),('malnacido','contiene'),
  ('cabron','contiene'),('pendejo','contiene'),('pendeja','contiene'),('chupapollas','contiene'),('comepollas','contiene'),
  ('soplapollas','contiene'),('chupamela','contiene'),('mamahuevo','contiene'),('mierda','contiene'),('follar','contiene'),
  ('follame','contiene'),('puton','contiene'),('putilla','contiene'),('cojones','contiene'),('capullo','contiene'),
  ('imbecil','contiene'),('idiota','contiene'),('jodete','contiene'),('joder','contiene'),('negrata','contiene'),
  ('sudaca','contiene'),('moromierda','contiene'),('travelo','contiene'),('bollera','contiene'),('tortillera','contiene'),
  ('mongolo','contiene'),('anormal','contiene'),('pederasta','contiene'),('pedofilo','contiene'),('zoofilia','contiene'),
  ('violador','contiene'),('vagina','contiene'),('nazi','contiene'),('hitler','contiene'),('siegheil','contiene'),
  ('puta','palabra'),('puto','palabra'),('putas','palabra'),('putos','palabra'),('culo','palabra'),('culos','palabra'),
  ('polla','palabra'),('pollas','palabra'),('cono','palabra'),('chocho','palabra'),('teta','palabra'),('tetas','palabra'),
  ('pene','palabra'),('verga','palabra'),('zorra','palabra'),('guarra','palabra'),('violar','palabra'),('mamon','palabra'),
  ('pedo','palabra'),('marica','palabra'),('cerdo','palabra'),('cerda','palabra'),('sexo','palabra'),('heil','palabra'),
  -- català
  ('fillputa','contiene'),('filldeputa','contiene'),('collons','contiene'),('malparit','contiene'),('merda','contiene'),
  ('cabro','palabra'),('cony','palabra'),('fotre','palabra'),
  -- english
  ('fuck','contiene'),('shit','contiene'),('bitch','contiene'),('cunt','contiene'),('asshole','contiene'),('whore','contiene'),
  ('slut','contiene'),('nigga','contiene'),('faggot','contiene'),('retard','contiene'),('wanker','contiene'),('porn','contiene'),
  ('rapist','contiene'),('dildo','contiene'),('penis','contiene'),('motherf','contiene'),('fck','contiene'),('fuk','contiene'),
  ('dick','palabra'),('dicks','palabra'),('cock','palabra'),('pussy','palabra'),('fag','palabra'),('twat','palabra'),
  ('rape','palabra'),('cum','palabra'),('sex','palabra'),('nigger','palabra'),('niger','palabra'),('tits','palabra'),('ass','palabra')
on conflict (palabra) do nothing;

-- Normaliza: minúsculas, sin tildes, números y símbolos por letras (0→o, 1→i, 3→e, 4→a, 5→s, 7→t, 8→b, @→a, $→s, !→i, |→l)
-- y todo lo que no sea letra pasa a espacio.
create or replace function public.norm_ofensivo(t text)
returns text language sql immutable set search_path = public, extensions as $$
  select trim(regexp_replace(translate(lower(extensions.unaccent(coalesce(t, ''))), '0134578@$!|', 'oieastbasil'), '[^a-z]+', ' ', 'g'))
$$;
-- Letras repetidas seguidas, una sola vez ("puuuta" → "puta")
create or replace function public.sin_repes(t text)
returns text language sql immutable as $$ select regexp_replace(coalesce(t, ''), '([a-z])\1+', '\1', 'g') $$;

-- ¿El nombre contiene alguna palabra prohibida?
-- Una palabra suelta coincide si es igual a la prohibida quitando letras repetidas y no es más corta que ella
-- (así "puuuta" se bloquea pero "Zora" o "Pola" no se confunden con "zorra" o "polla").
create or replace function public.nombre_ofensivo(p_nombre text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  with n as (select norm_ofensivo(p_nombre) as w),
       ws as (select x as raw from n, unnest(string_to_array(n.w, ' ') || replace(n.w, ' ', '')) x where x <> '')
  select exists (
    select 1 from nombres_prohibidos p, n
    where p.modo = 'contiene' and position(sin_repes(replace(norm_ofensivo(p.palabra), ' ', '')) in sin_repes(replace(n.w, ' ', ''))) > 0
  ) or exists (
    select 1 from nombres_prohibidos p, ws
    where p.modo = 'palabra' and sin_repes(ws.raw) = sin_repes(norm_ofensivo(p.palabra)) and length(ws.raw) >= length(norm_ofensivo(p.palabra))
  )
$$;
grant execute on function public.nombre_ofensivo(text) to anon, authenticated;

-- Crear el PIN: ahora también comprueba el nombre
drop function if exists public.pin_crear(text, text);
create or replace function public.pin_crear(p_clave text, p_pin text, p_nombre text default null)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_clave is null or char_length(p_clave) < 1 or char_length(p_clave) > 40 or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if nombre_ofensivo(p_clave) or nombre_ofensivo(p_nombre) then raise exception 'NOMBRE_OFENSIVO'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN_NO_VALIDO'; end if;
  insert into jugadores_pin (clave, pin_hash) values (p_clave, crypt(p_pin, gen_salt('bf'))) on conflict (clave) do nothing;
  return found;
end $$;
grant execute on function public.pin_crear(text, text, text) to anon, authenticated;

-- Guardar partida: igual que en login_obligatorio.sql, rechazando además los nombres ofensivos
create or replace function public.guardar_partida2(
  p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text,
  p_modo text default 'normal', p_racha int default null, p_detalle jsonb default null, p_cuadro text default null)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare h text; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  if p_clave is null or p_clave = '' or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if nombre_ofensivo(p_clave) or nombre_ofensivo(p_nombre) then raise exception 'NOMBRE_OFENSIVO'; end if;
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is null then raise exception 'PIN_OBLIGATORIO'; end if;
  if p_pin is null or h <> crypt(p_pin, h) then raise exception 'PIN_INCORRECTO'; end if;
  if p_modo = 'reto' then
    insert into retos (fecha, clave, nombre, puntos, aciertos, total, cuadro)
      values (hoy, left(p_clave, 40), left(p_nombre, 24), p_puntos, p_aciertos, p_total, left(p_cuadro, 40))
      on conflict (fecha, clave) do nothing;
    if not found then return 'repetido'; end if;
  end if;
  insert into partidas (nombre, clave, puntos, aciertos, total, modo, racha, detalle)
    values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total,
            case when p_modo in ('reto', 'campeonato', 'practica') then p_modo else 'normal' end,
            greatest(0, least(coalesce(p_racha, 0), p_total)),
            case when jsonb_typeof(p_detalle) = 'object' and length(p_detalle::text) < 2000 then p_detalle end);
  return 'ok';
end $$;
grant execute on function public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text) to anon, authenticated;


-- ===================================================================
-- logros.sql
-- ===================================================================
-- Logros ampliados (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
-- Amplía el perfil del jugador con los datos que necesitan los logros nuevos:
-- días jugados, racha de días, partidas en un día, madrugador, fin de semana, campeonato,
-- retos perfectos, podios del reto y fechas de los retos jugados (para los retos especiales).

create or replace function public.perfil(p_clave text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb; cats jsonb; extra jsonb; dias date[]; racha_reto int := 0; racha_max int := 0; cur int := 0; prev date; d date; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  select jsonb_build_object(
      'nombre',    (array_agg(nombre order by creado desc))[1],
      'partidas',  count(*),
      'puntos',    coalesce(sum(puntos), 0),
      'mejor',     coalesce(max(puntos), 0),
      'aciertos',  coalesce(sum(aciertos), 0),
      'total',     coalesce(sum(total), 0),
      'perfectas', count(*) filter (where aciertos = total and total >= 10),
      'racha',     coalesce(max(racha), 0),
      'noche',     count(*) filter (where extract(hour from creado at time zone 'Europe/Madrid') < 6),
      'madrugador', count(*) filter (where extract(hour from creado at time zone 'Europe/Madrid') between 6 and 8),
      'finde',     count(*) filter (where extract(isodow from creado at time zone 'Europe/Madrid') >= 6),
      'dias',      count(distinct (creado at time zone 'Europe/Madrid')::date),
      'campeonato', count(*) filter (where modo = 'campeonato'),
      'campeonato_mejor', coalesce(max(puntos) filter (where modo = 'campeonato'), 0),
      'desde',     min(creado),
      'mes_puntos', coalesce(sum(puntos) filter (where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')), 0))
    into r from partidas where clave = p_clave;
  if (r->>'partidas')::int = 0 then return null; end if;

  select coalesce(jsonb_object_agg(cat, jsonb_build_array(ok, tot)), '{}'::jsonb) into cats from (
    select e.key as cat, sum((e.value->>0)::int) as ok, sum((e.value->>1)::int) as tot
    from partidas p, jsonb_each(p.detalle) e
    where p.clave = p_clave and jsonb_typeof(p.detalle) = 'object' and jsonb_typeof(e.value) = 'array'
    group by e.key) c;

  -- días seguidos jugando el reto: racha actual (hasta hoy o ayer) y mejor racha
  select array_agg(fecha order by fecha desc) into dias from retos where clave = p_clave;
  if dias is not null then
    foreach d in array dias loop
      if prev is not null and d = prev - 1 then cur := cur + 1; else cur := 1; end if;
      if cur > racha_max then racha_max := cur; end if;
      prev := d;
    end loop;
    if dias[1] >= hoy - 1 then
      foreach d in array dias loop
        if d = dias[1] - racha_reto then racha_reto := racha_reto + 1; else exit; end if;
      end loop;
    end if;
  end if;

  -- días seguidos jugando (cualquier partida) y máximo de partidas en un mismo día
  with d as (select distinct (creado at time zone 'Europe/Madrid')::date as dia from partidas where clave = p_clave),
       g as (select dia, dia - (row_number() over (order by dia))::int as grp from d),
       por_dia as (select (creado at time zone 'Europe/Madrid')::date as dia, count(*) as n from partidas where clave = p_clave group by 1)
  select jsonb_build_object(
      'racha_dias_max', coalesce((select max(c) from (select count(*) as c from g group by grp) x), 0),
      'max_dia',        coalesce((select max(n) from por_dia), 0),
      'retos_perfectos', (select count(*) from retos where clave = p_clave and total >= 10 and aciertos = total),
      'retos_podio', (select count(*) from (
          select clave, rank() over (partition by fecha order by puntos desc, creado) as pos from retos
          where fecha in (select fecha from retos where clave = p_clave) and fecha < hoy) x
        where x.clave = p_clave and x.pos <= 3),
      'fechas_reto', coalesce((select jsonb_agg(fecha order by fecha desc) from (select fecha from retos where clave = p_clave order by fecha desc limit 400) z), '[]'::jsonb))
    into extra;

  return r || extra || jsonb_build_object(
    'categorias', cats,
    'retos', coalesce(array_length(dias, 1), 0),
    'racha_reto', racha_reto,
    'racha_reto_max', racha_max,
    'retos_ganados', (select count(*) from (
        select fecha, clave, rank() over (partition by fecha order by puntos desc, creado) as pos from retos
        where fecha in (select fecha from retos where clave = p_clave) and fecha < hoy) x
      where x.clave = p_clave and x.pos = 1),
    'mejor_reto', (select max(puntos) from retos where clave = p_clave),
    'campeon', (select count(*) from campeones_mensuales c where c.puesto = 1 and norm_clave(c.nombre) = p_clave),
    'podios',  (select count(*) from campeones_mensuales c where norm_clave(c.nombre) = p_clave));
end $$;

grant execute on function public.perfil(text) to anon, authenticated;


-- ===================================================================
-- mantenimiento.sql
-- ===================================================================
-- Mantenimiento automático de la base de datos (Sabelotodo)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Se puede volver a ejecutar sin problema.
--
-- Qué hace, una vez al mes (día 1 a las 4:00, hora UTC):
--   · Estadísticas anónimas (tabla eventos) de hace más de 90 días: las resume por día en eventos_archivo
--     y borra el detalle. Los informes diarios solo usan los últimos días, así que no cambian.
--   · Salas del modo evento de hace más de 14 días: se borran (con sus jugadores, preguntas y respuestas).
--   · Reportes de errores de hace más de 180 días: se borran (ya se habrán revisado).
-- NO toca nunca partidas, retos, PIN, el Hall of Fame ni las estadísticas de preguntas.
--
-- Además crea tamano_bd(), que dice cuánto ocupa la base de datos (para el informe diario).

-- 1) Resumen diario de las estadísticas antiguas
create table if not exists public.eventos_archivo (
  dia         date not null,
  tipo        text not null,
  dispositivo text not null default '',
  categoria   text not null default '',
  dificultad  text not null default '',
  veces       integer not null,
  preguntas   bigint,
  aciertos    bigint,
  puntos      bigint,
  primary key (dia, tipo, dispositivo, categoria, dificultad)
);
alter table public.eventos_archivo enable row level security;   -- sin políticas: no se lee desde la web

-- 2) La limpieza
create or replace function public.limpieza_mensual()
returns jsonb language plpgsql security definer set search_path = public as $$
declare corte timestamptz := (date_trunc('day', now() at time zone 'Europe/Madrid') - interval '90 days') at time zone 'Europe/Madrid';
        n_ev int := 0; n_salas int := 0; n_rep int := 0;
begin
  insert into eventos_archivo (dia, tipo, dispositivo, categoria, dificultad, veces, preguntas, aciertos, puntos)
  select (creado at time zone 'Europe/Madrid')::date, tipo, coalesce(dispositivo, ''), coalesce(categoria, ''), coalesce(dificultad, ''),
         count(*), sum(preguntas), sum(aciertos), sum(puntos)
  from eventos where creado < corte
  group by 1, 2, 3, 4, 5
  on conflict (dia, tipo, dispositivo, categoria, dificultad) do update
    set veces = eventos_archivo.veces + excluded.veces,
        preguntas = coalesce(eventos_archivo.preguntas, 0) + coalesce(excluded.preguntas, 0),
        aciertos  = coalesce(eventos_archivo.aciertos, 0)  + coalesce(excluded.aciertos, 0),
        puntos    = coalesce(eventos_archivo.puntos, 0)    + coalesce(excluded.puntos, 0);
  delete from eventos where creado < corte;
  get diagnostics n_ev = row_count;

  if to_regclass('public.salas') is not null then
    delete from salas where creado < now() - interval '14 days';
    get diagnostics n_salas = row_count;
  end if;

  if to_regclass('public.reportes') is not null then
    delete from reportes where creado < now() - interval '180 days';
    get diagnostics n_rep = row_count;
  end if;

  return jsonb_build_object('eventos_resumidos', n_ev, 'salas_borradas', n_salas, 'reportes_borrados', n_rep);
end $$;
revoke all on function public.limpieza_mensual() from public, anon, authenticated;

-- 3) Programarla cada mes con pg_cron (incluido en el plan gratuito)
create extension if not exists pg_cron;
do $$ begin
  perform cron.unschedule('sabelotodo-limpieza-mensual');
exception when others then null; end $$;
select cron.schedule('sabelotodo-limpieza-mensual', '0 4 1 * *', $$select public.limpieza_mensual()$$);

-- 4) Tamaño de la base de datos (lectura pública, sin datos personales)
create or replace function public.tamano_bd()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'total_mb',    round(pg_database_size(current_database()) / 1048576.0, 1),
    'limite_mb',   500,
    'partidas_mb', round(pg_total_relation_size('public.partidas') / 1048576.0, 1),
    'eventos_mb',  round(pg_total_relation_size('public.eventos') / 1048576.0, 1))
$$;
grant execute on function public.tamano_bd() to anon, authenticated;

-- Para comprobarlo ahora mismo:
select public.tamano_bd() as tamano, (select count(*) from cron.job where jobname = 'sabelotodo-limpieza-mensual') as tarea_programada;


-- ===== vistas_jugador.sql =====
-- Preguntas vistas por jugador, compartidas entre sus dispositivos
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
-- Sirve igual para Liantes Quiz Metalero y para Sabelotodo (ejecútalo en cada proyecto).
-- Requiere pin.sql (tabla jugadores_pin). Solo se sincronizan jugadores con PIN.
--
-- Pensado para los límites del plan gratuito de Supabase (500 MB de base de datos, 5 GB de descarga al mes):
--   · Se guardan solo los identificadores cortos de las preguntas (unos 7 caracteres), como mucho 12.000 por jugador:
--     un jugador que lo hubiera visto todo ocupa unos 100 KB; uno normal, unos pocos KB.
--   · La web solo envía las preguntas nuevas al terminar cada partida (como mucho 300 por llamada).
--   · La lista completa solo se descarga cuando otro dispositivo del mismo jugador la ha cambiado.
--   · Los jugadores que llevan un año sin jugar se borran solos.
--
-- Consultas útiles:
--   · Espacio ocupado:   select pg_size_pretty(pg_total_relation_size('public.jugadores_vistas'));
--   · Jugadores y vistas: select clave, cardinality(ids) vistas, actualizado from public.jugadores_vistas order by actualizado desc;

create table if not exists public.jugadores_vistas (
  clave        text primary key references public.jugadores_pin(clave) on delete cascade,
  ids          text[] not null default '{}',      -- de la más antigua a la más reciente
  ver          integer not null default 0,        -- sube con cada cambio; la web lo usa para saber si tiene que descargar
  actualizado  timestamptz not null default now()
);
alter table public.jugadores_vistas enable row level security;   -- sin políticas: solo se accede con la función de abajo

-- p_ids: preguntas vistas desde la última sincronización (en orden). p_ver: la versión que tiene el dispositivo (null si ninguna).
-- Devuelve {"ver": n} si el dispositivo ya estaba al día, o {"ver": n, "ids": [...]} con la lista completa si no.
create or replace function public.vistas_sync(p_clave text, p_pin text, p_ids text[] default '{}', p_ver integer default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare h text; v_ver int; v_ids text[]; nuevos text[];
begin
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is null or p_pin is null or h <> crypt(p_pin, h) then raise exception 'PIN_INCORRECTO'; end if;

  -- sin repetidos (se queda la última aparición), solo identificadores válidos y como mucho 300
  select coalesce(array_agg(x order by o), '{}') into nuevos from (
    select x, max(o) o from unnest(coalesce(p_ids, '{}')) with ordinality t(x, o)
    where x ~ '^-?[0-9a-z]{1,8}$' group by x order by max(o) desc limit 300) s;

  insert into jugadores_vistas (clave) values (p_clave) on conflict (clave) do nothing;
  select ver, ids into v_ver, v_ids from jugadores_vistas where clave = p_clave for update;

  if cardinality(nuevos) > 0 then
    -- las que vuelven a verse pasan al final; se guardan las 12.000 más recientes
    select coalesce(array_agg(x order by o), '{}') into v_ids from (
      select x, o from unnest(v_ids) with ordinality t(x, o) where x <> all(nuevos)
      union all
      select x, 100000 + o from unnest(nuevos) with ordinality t(x, o)) s;
    if cardinality(v_ids) > 12000 then v_ids := v_ids[cardinality(v_ids) - 11999:]; end if;
    update jugadores_vistas set ids = v_ids, ver = ver + 1, actualizado = now() where clave = p_clave;
    if p_ver is not distinct from v_ver then return jsonb_build_object('ver', v_ver + 1); end if;
    v_ver := v_ver + 1;
  elsif p_ver is not distinct from v_ver then
    return jsonb_build_object('ver', v_ver);
  end if;

  if random() < 0.01 then delete from jugadores_vistas where actualizado < now() - interval '1 year'; end if;
  return jsonb_build_object('ver', v_ver, 'ids', to_jsonb(v_ids));
end $$;
revoke execute on function public.vistas_sync(text, text, text[], integer) from public;
grant execute on function public.vistas_sync(text, text, text[], integer) to anon, authenticated;
