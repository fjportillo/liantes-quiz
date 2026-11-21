-- MODO CONCURSO (rondas con reglas distintas, estilo concurso de TV) para el modo evento.
-- Requiere evento.sql. Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Ejecútalo en las dos bases de datos (Liantes y Sabelotodo). Se puede ejecutar más de una vez.
--
-- Qué cambia:
--  * Los puntos de cada pregunta los calcula la base de datos al revelar la respuesta, según la ronda
--    (el tipo de ronda viaja dentro de la pregunta que envía la pantalla del presentador).
--  * La rapidez se mide siempre con el reloj del servidor, no con el del móvil.
--  * El modo evento clásico (sin rondas) sigue puntuando igual que antes: 100 por acierto + hasta 100 por rapidez.

create table if not exists public.sala_puntos (
  codigo   text not null references public.salas(codigo) on delete cascade,
  idx      integer not null,
  jugador  uuid not null references public.sala_jugadores(id) on delete cascade,
  puntos   integer not null,
  motivo   text not null,               -- acierto | primero | fallo | robo | robado
  primary key (codigo, idx, jugador)
);
alter table public.sala_puntos enable row level security;   -- sin políticas: solo a través de las funciones y vistas

-- Puntos de un jugador antes de una pregunta (fallar o que te roben nunca te deja por debajo de 0)
create or replace function public.ev_total(p_codigo text, p_jugador uuid, p_idx int)
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, coalesce(sum(puntos), 0))::int from sala_puntos where codigo = p_codigo and jugador = p_jugador and idx < p_idx
$$;
revoke execute on function public.ev_total(text, uuid, int) from public, anon, authenticated;

-- Al revelar la respuesta se reparten los puntos de la pregunta según su ronda.
create or replace function public.ev_revelar(p_codigo text, p_secret text, p_correcta int)
returns void language plpgsql security definer set search_path = public as $$
declare
  s salas; tipo text; seg int; ladron uuid; victima uuid; botin int;
begin
  select * into s from salas where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'sala no encontrada'; end if;
  update salas set estado = 'resultado', correcta = p_correcta, deadline = least(deadline, now()) where codigo = s.codigo;
  insert into sala_preguntas (codigo, idx, correcta, segundos) values (s.codigo, s.idx, p_correcta, s.segundos)
  on conflict (codigo, idx) do update set correcta = excluded.correcta;

  tipo := coalesce(s.pregunta->>'tipo', 'clasica');
  seg := greatest(1, s.segundos * 1000);
  delete from sala_puntos where codigo = s.codigo and idx = s.idx;      -- por si se revela dos veces

  if tipo = 'calentamiento' then          -- 100 fijos por acierto
    insert into sala_puntos select r.codigo, r.idx, r.jugador, 100, 'acierto'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta;

  elsif tipo = 'contrarreloj' then        -- de 200 a 20 según lo que tardes
    insert into sala_puntos select r.codigo, r.idx, r.jugador, round(200 - 180.0 * least(r.ms, seg) / seg)::int, 'acierto'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta;

  elsif tipo = 'rapido' then              -- solo puntúa el primero que acierta (+200); fallar resta 100
    insert into sala_puntos select r.codigo, r.idx, r.jugador, 200, 'primero'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta
      order by r.ms, r.creado limit 1;
    insert into sala_puntos select r.codigo, r.idx, r.jugador, -least(100, ev_total(s.codigo, r.jugador, s.idx)), 'fallo'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion <> p_correcta;

  elsif tipo = 'robo' then                -- acertar da 50; el más rápido además roba hasta 150 al líder
    insert into sala_puntos select r.codigo, r.idx, r.jugador, 50, 'acierto'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta;
    select r.jugador into ladron from sala_respuestas r
      where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta order by r.ms, r.creado limit 1;
    if ladron is not null then
      select j.id, coalesce(sum(p.puntos), 0)::int into victima, botin
        from sala_jugadores j left join sala_puntos p on p.jugador = j.id and p.codigo = s.codigo and p.idx < s.idx
        where j.codigo = s.codigo and j.id <> ladron
        group by j.id having coalesce(sum(p.puntos), 0) > 0
        order by coalesce(sum(p.puntos), 0) desc, j.creado limit 1;
      if victima is not null then
        botin := least(150, botin);
        update sala_puntos set puntos = 50 + botin, motivo = 'robo' where codigo = s.codigo and idx = s.idx and jugador = ladron;
        insert into sala_puntos values (s.codigo, s.idx, victima, -botin, 'robado')
        on conflict (codigo, idx, jugador) do update set puntos = sala_puntos.puntos - botin, motivo = 'robado';
      end if;
    end if;

  elsif tipo = 'final' then               -- todo o nada: de 300 a 60 según lo que tardes; fallar resta 150
    insert into sala_puntos select r.codigo, r.idx, r.jugador, round(300 - 240.0 * least(r.ms, seg) / seg)::int, 'acierto'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta;
    insert into sala_puntos select r.codigo, r.idx, r.jugador, -least(150, ev_total(s.codigo, r.jugador, s.idx)), 'fallo'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion <> p_correcta;

  else                                    -- modo evento clásico: 100 por acierto + hasta 100 por rapidez
    insert into sala_puntos select r.codigo, r.idx, r.jugador, 100 + round(100.0 * greatest(0, seg - r.ms) / seg)::int, 'acierto'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta;
  end if;
end $$;

-- Clasificación: suma de los puntos repartidos (nunca por debajo de 0)
create or replace view public.ev_ranking as
select j.codigo, j.id as jugador, j.nombre,
  greatest(0, coalesce((select sum(p.puntos) from sala_puntos p where p.jugador = j.id), 0))::int as puntos,
  (select count(*) from sala_respuestas r join sala_preguntas q on q.codigo = r.codigo and q.idx = r.idx
     where r.jugador = j.id and r.opcion = q.correcta)::int as aciertos
from sala_jugadores j;

-- Lo que ha pasado en cada pregunta (para enseñar "+200", "¡robo!", "-100"…)
create or replace view public.ev_puntos as
select p.codigo, p.idx, p.jugador, j.nombre, p.puntos, p.motivo
from sala_puntos p join sala_jugadores j on j.id = p.jugador;

grant select on public.ev_ranking, public.ev_puntos to anon, authenticated;
grant execute on function public.ev_revelar(text,text,int) to anon, authenticated;
