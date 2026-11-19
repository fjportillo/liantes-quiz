-- Acceso obligatorio con nombre + PIN (Liantes Quiz Metalero)
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
