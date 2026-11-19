-- Reto diario + perfil de jugador con logros (Liantes Quiz Metalero)
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
