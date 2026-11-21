-- MODO EVENTO: reglas de la partida visibles en los móviles antes de empezar.
-- Requiere evento.sql, concurso.sql y salas_partidas.sql. Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Ejecútalo en las dos bases de datos (Liantes y Sabelotodo). Se puede ejecutar más de una vez.
--
-- El presentador guarda en la sala cómo será la partida (tipo, rondas, preguntas, segundos) y los móviles
-- lo leen en la sala de espera para enseñar las reglas.

alter table public.salas add column if not exists config jsonb;

create or replace function public.ev_config(p_codigo text, p_secret text, p_config jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if pg_column_size(p_config) > 4000 then raise exception 'config demasiado grande'; end if;
  update salas set config = p_config where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
end $$;

-- Al empezar otra partida en la misma sala, la configuración anterior deja de valer
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
    partida = np, config = null, creado = now()
  where codigo = s.codigo;
  update sala_jugadores set partida = np where codigo = s.codigo;
  return np;
end $$;

create or replace view public.ev_estado as
select codigo, estado, idx, total, segundos, pregunta, correcta, deadline, now() as ahora,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo and j.partida = s.partida)::int as jugadores,
  (select count(*) from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx)::int as respondidas,
  partida,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo and j.partida > s.partida)::int as en_espera,
  config
from salas s;

grant select on public.ev_estado to anon, authenticated;
grant execute on function public.ev_config(text,text,jsonb) to anon, authenticated;
grant execute on function public.ev_nueva_partida(text,text,int,int) to anon, authenticated;
