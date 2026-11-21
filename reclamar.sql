-- MODO EVENTO: "Soy yo, recuperar mi sitio".
-- Requiere reingreso.sql. Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Ejecútalo en las dos bases de datos (Liantes y Sabelotodo). Se puede ejecutar más de una vez.
--
-- Si un jugador vuelve desde otro navegador o móvil (o tras borrar los datos del navegador), su nombre sigue
-- ocupado en la sala. Con esta función recupera su sitio (mismos puntos y misma partida): se le da un token
-- nuevo y el dispositivo anterior deja de poder responder.

create or replace function public.ev_reclamar(p_codigo text, p_nombre text)
returns table (jugador uuid, token uuid) language plpgsql security definer set search_path = public as $$
declare j sala_jugadores;
begin
  select x.* into j from sala_jugadores x join salas s on s.codigo = x.codigo
   where s.codigo = upper(p_codigo) and lower(x.nombre) = lower(btrim(p_nombre));
  if not found then raise exception 'JUGADOR_NO_EXISTE'; end if;
  return query update sala_jugadores set fuera = false, token = gen_random_uuid() where id = j.id
    returning id, sala_jugadores.token;
end $$;

grant execute on function public.ev_reclamar(text,text) to anon, authenticated;
