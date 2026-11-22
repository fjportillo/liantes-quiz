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
