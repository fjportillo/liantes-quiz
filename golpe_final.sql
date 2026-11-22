-- GOLPE FINAL del modo evento: una última pregunta muy difícil en la que el primero que acierta
-- roba hasta 300 puntos a cada uno de los demás jugadores (nadie baja de 0; si nadie acierta, no pasa nada).
-- Requiere evento.sql, concurso.sql y salas_partidas.sql. Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Ejecútalo en las dos bases de datos (Liantes y Sabelotodo). No borra nada y se puede ejecutar más de una vez.
-- Sustituye a ev_revelar con las mismas reglas de siempre más la nueva ronda 'golpe'.

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

  elsif tipo = 'golpe' then               -- golpe final: el primero que acierta roba hasta 300 a cada uno de los demás
    select r.jugador into ladron from sala_respuestas r
      where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta order by r.ms, r.creado limit 1;
    if ladron is not null then
      insert into sala_puntos
        select s.codigo, s.idx, j.id, -least(300, ev_total(s.codigo, j.id, s.idx)), 'golpeado'
        from sala_jugadores j
        where j.codigo = s.codigo and j.partida = s.partida and j.id <> ladron and ev_total(s.codigo, j.id, s.idx) > 0;
      select coalesce(-sum(puntos), 0)::int into botin from sala_puntos where codigo = s.codigo and idx = s.idx and motivo = 'golpeado';
      insert into sala_puntos values (s.codigo, s.idx, ladron, botin, 'golpe');
    end if;

  else                                    -- modo evento clásico: 100 por acierto + hasta 100 por rapidez
    insert into sala_puntos select r.codigo, r.idx, r.jugador, 100 + round(100.0 * greatest(0, seg - r.ms) / seg)::int, 'acierto'
      from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx and r.opcion = p_correcta;
  end if;
end $$;

grant execute on function public.ev_revelar(text,text,int) to anon, authenticated;
