-- Reto diario jugado sin conexión: permite subirlo después con la fecha en que se jugó (solo hoy o ayer).
-- Idempotente. Sustituye guardar_partida2 (misma lógica que la versión actual + parámetro p_fecha opcional).
begin;
drop function if exists public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text);
create or replace function public.guardar_partida2(
  p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text,
  p_modo text default 'normal', p_racha int default null, p_detalle jsonb default null, p_cuadro text default null,
  p_fecha date default null)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare h text; hoy date := (now() at time zone 'Europe/Madrid')::date; f date; ts timestamptz := now();
begin
  if p_clave is null or p_clave = '' or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if nombre_ofensivo(p_clave) or nombre_ofensivo(p_nombre) then raise exception 'NOMBRE_OFENSIVO'; end if;
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is null then raise exception 'PIN_OBLIGATORIO'; end if;
  if p_pin is null or h <> crypt(p_pin, h) then raise exception 'PIN_INCORRECTO'; end if;
  f := coalesce(p_fecha, hoy);
  if p_modo = 'reto' and f <> hoy then
    if f > hoy or f < hoy - 1 then raise exception 'FECHA_NO_VALIDA'; end if;      -- solo se admite el reto de ayer
    ts := ((f + time '23:59:00') at time zone 'Europe/Madrid');                      -- cuenta como jugado ese día
  end if;
  if p_modo = 'reto' then
    insert into retos (fecha, clave, nombre, puntos, aciertos, total, cuadro, creado)
      values (f, left(p_clave, 40), left(p_nombre, 24), p_puntos, p_aciertos, p_total, left(p_cuadro, 40), ts)
      on conflict (fecha, clave) do nothing;
    if not found then return 'repetido'; end if;
  end if;
  insert into partidas (nombre, clave, puntos, aciertos, total, modo, racha, detalle, creado)
    values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total,
            case when p_modo in ('reto', 'campeonato', 'practica') then p_modo else 'normal' end,
            greatest(0, least(coalesce(p_racha, 0), p_total)),
            case when jsonb_typeof(p_detalle) = 'object' and length(p_detalle::text) < 2000 then p_detalle end, ts);
  return 'ok';
end $$;
grant execute on function public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text,date) to anon, authenticated;
commit;
