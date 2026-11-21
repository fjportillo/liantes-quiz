-- MODO EVENTO: volver a entrar tras salir por error, sin perder los puntos.
-- Requiere evento.sql, concurso.sql, salas_partidas.sql y reglas.sql. Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Ejecútalo en las dos bases de datos (Liantes y Sabelotodo). Se puede ejecutar más de una vez.
--
-- Qué cambia:
--  * "Salir" ya no borra al jugador: lo marca como fuera (y anula su token).
--  * Si vuelve a entrar con el mismo nombre, recupera su sitio: mismos puntos y misma partida.
--  * Los jugadores que están fuera no cuentan para "han respondido" ni salen en la sala de espera,
--    y desaparecen al empezar otra partida en la sala.

alter table public.sala_jugadores add column if not exists fuera boolean not null default false;

create or replace function public.ev_salir(p_jugador uuid, p_token uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update sala_jugadores set fuera = true, token = gen_random_uuid() where id = p_jugador and token = p_token;
end $$;

create or replace function public.ev_unirse(p_codigo text, p_nombre text)
returns table (jugador uuid, token uuid) language plpgsql security definer set search_path = public as $$
declare s salas; n text := btrim(p_nombre); j sala_jugadores;
begin
  select * into s from salas where codigo = upper(p_codigo);
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  if char_length(n) < 1 or char_length(n) > 20 then raise exception 'NOMBRE_NO_VALIDO'; end if;
  select * into j from sala_jugadores x where x.codigo = s.codigo and lower(x.nombre) = lower(n);
  if found then
    if not j.fuera then raise exception 'NOMBRE_OCUPADO'; end if;
    -- vuelve quien salió: conserva su id (y con él sus respuestas y puntos) y su partida
    return query update sala_jugadores set fuera = false, token = gen_random_uuid() where id = j.id
      returning id, sala_jugadores.token;
    return;
  end if;
  if (select count(*) from sala_jugadores x where x.codigo = s.codigo and not x.fuera) >= 200 then raise exception 'SALA_LLENA'; end if;
  return query insert into sala_jugadores (codigo, nombre, partida)
    values (s.codigo, n, case when s.estado = 'lobby' then s.partida else s.partida + 1 end)
    returning id, sala_jugadores.token;
end $$;

create or replace function public.ev_nueva_partida(p_codigo text, p_secret text, p_total int, p_segundos int)
returns integer language plpgsql security definer set search_path = public as $$
declare s salas; np int;
begin
  select * into s from salas where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  delete from sala_puntos where codigo = s.codigo;
  delete from sala_respuestas where codigo = s.codigo;
  delete from sala_preguntas where codigo = s.codigo;
  delete from sala_jugadores where codigo = s.codigo and fuera;          -- los que se fueron no pasan a la nueva
  np := s.partida + 1;
  update salas set estado = 'lobby', idx = -1, pregunta = null, correcta = null, inicio = null, deadline = null,
    total = greatest(1, least(p_total, 50)), segundos = greatest(10, least(p_segundos, 60)),
    partida = np, config = null, creado = now()
  where codigo = s.codigo;
  update sala_jugadores set partida = np where codigo = s.codigo;
  return np;
end $$;

create or replace view public.ev_estado as
select codigo, estado, idx, total, segundos, pregunta, correcta, deadline, now() as ahora,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo and j.partida = s.partida and not j.fuera)::int as jugadores,
  (select count(*) from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx)::int as respondidas,
  partida,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo and j.partida > s.partida and not j.fuera)::int as en_espera,
  config
from salas s;

create or replace view public.ev_jugadores as
select codigo, nombre, creado, id as jugador, partida from sala_jugadores where not fuera;

grant select on public.ev_estado, public.ev_jugadores to anon, authenticated;
grant execute on function public.ev_salir(uuid,uuid) to anon, authenticated;
grant execute on function public.ev_unirse(text,text) to anon, authenticated;
grant execute on function public.ev_nueva_partida(text,text,int,int) to anon, authenticated;
