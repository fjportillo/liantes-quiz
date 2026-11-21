-- MODO EVENTO: varias partidas en la misma sala y lobby para quien llega tarde.
-- Requiere evento.sql y concurso.sql. Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Ejecútalo en las dos bases de datos (Liantes y Sabelotodo). Se puede ejecutar más de una vez.
--
-- Qué cambia:
--  * Cada sala lleva la cuenta de su número de partida, y cada jugador sabe en qué partida juega.
--  * Quien entra con la partida ya empezada (o terminada) queda apuntado a la SIGUIENTE: espera en el lobby
--    y no puede responder ni sale en la clasificación de la partida en curso.
--  * El presentador puede empezar otra partida en la misma sala (ev_nueva_partida): se borran respuestas y
--    puntos, y todos los jugadores conectados (también los que esperaban) pasan a la nueva partida.

alter table public.salas          add column if not exists partida integer not null default 1;
alter table public.sala_jugadores add column if not exists partida integer not null default 1;

-- Entrar en una sala: si la partida ya ha empezado o terminado, se entra para la siguiente
create or replace function public.ev_unirse(p_codigo text, p_nombre text)
returns table (jugador uuid, token uuid) language plpgsql security definer set search_path = public as $$
declare s salas; n text := btrim(p_nombre);
begin
  select * into s from salas where codigo = upper(p_codigo);
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  if char_length(n) < 1 or char_length(n) > 20 then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if exists (select 1 from sala_jugadores j where j.codigo = s.codigo and lower(j.nombre) = lower(n)) then raise exception 'NOMBRE_OCUPADO'; end if;
  if (select count(*) from sala_jugadores j where j.codigo = s.codigo) >= 200 then raise exception 'SALA_LLENA'; end if;
  return query insert into sala_jugadores (codigo, nombre, partida)
    values (s.codigo, n, case when s.estado = 'lobby' then s.partida else s.partida + 1 end)
    returning id, sala_jugadores.token;
end $$;

-- Responder: solo quien juega la partida en curso
create or replace function public.ev_responder(p_codigo text, p_jugador uuid, p_token uuid, p_idx int, p_opcion int)
returns integer language plpgsql security definer set search_path = public as $$
declare s salas; t int; mp int;
begin
  select * into s from salas where codigo = upper(p_codigo);
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  select partida into mp from sala_jugadores where id = p_jugador and token = p_token and codigo = s.codigo;
  if not found then raise exception 'JUGADOR_NO_VALIDO'; end if;
  if mp <> s.partida then raise exception 'ESPERANDO_SIGUIENTE'; end if;
  if s.estado <> 'pregunta' or s.idx <> p_idx or now() > s.deadline + interval '1 second' then raise exception 'FUERA_DE_TIEMPO'; end if;
  t := greatest(0, least(s.segundos * 1000, (extract(epoch from (now() - s.inicio)) * 1000)::int));
  insert into sala_respuestas (codigo, jugador, idx, opcion, ms) values (s.codigo, p_jugador, p_idx, p_opcion, t)
  on conflict do nothing;
  return t;
end $$;

-- Otra partida en la misma sala (presentador)
create or replace function public.ev_nueva_partida(p_codigo text, p_secret text, p_total int, p_segundos int)
returns integer language plpgsql security definer set search_path = public as $$
declare s salas; np int;
begin
  select * into s from salas where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  delete from sala_puntos where codigo = s.codigo;
  delete from sala_respuestas where codigo = s.codigo;
  delete from sala_preguntas where codigo = s.codigo;
  np := s.partida + 1;
  update salas set estado = 'lobby', idx = -1, pregunta = null, correcta = null, inicio = null, deadline = null,
    total = greatest(1, least(p_total, 50)), segundos = greatest(10, least(p_segundos, 60)),
    partida = np, creado = now()                        -- la sala dura otros 2 días
  where codigo = s.codigo;
  update sala_jugadores set partida = np where codigo = s.codigo;
  return np;
end $$;

-- Vistas: jugadores y respuestas cuentan solo los de la partida en curso; en_espera = los que esperan la siguiente
create or replace view public.ev_estado as
select codigo, estado, idx, total, segundos, pregunta, correcta, deadline, now() as ahora,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo and j.partida = s.partida)::int as jugadores,
  (select count(*) from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx)::int as respondidas,
  partida,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo and j.partida > s.partida)::int as en_espera
from salas s;

create or replace view public.ev_jugadores as
select codigo, nombre, creado, id as jugador, partida from sala_jugadores;

create or replace view public.ev_ranking as
select j.codigo, j.id as jugador, j.nombre,
  greatest(0, coalesce((select sum(p.puntos) from sala_puntos p where p.jugador = j.id), 0))::int as puntos,
  (select count(*) from sala_respuestas r join sala_preguntas q on q.codigo = r.codigo and q.idx = r.idx
     where r.jugador = j.id and r.opcion = q.correcta)::int as aciertos
from sala_jugadores j join salas s on s.codigo = j.codigo
where j.partida = s.partida;

grant select on public.ev_estado, public.ev_jugadores, public.ev_ranking to anon, authenticated;
grant execute on function public.ev_unirse(text,text) to anon, authenticated;
grant execute on function public.ev_responder(text,uuid,uuid,int,int) to anon, authenticated;
grant execute on function public.ev_nueva_partida(text,text,int,int) to anon, authenticated;
