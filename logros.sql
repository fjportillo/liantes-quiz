-- Logros ampliados (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
-- Amplía el perfil del jugador con los datos que necesitan los logros nuevos:
-- días jugados, racha de días, partidas en un día, madrugador, fin de semana, campeonato,
-- retos perfectos, podios del reto y fechas de los retos jugados (para los retos especiales).

create or replace function public.perfil(p_clave text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb; cats jsonb; extra jsonb; dias date[]; racha_reto int := 0; racha_max int := 0; cur int := 0; prev date; d date; hoy date := (now() at time zone 'Europe/Madrid')::date;
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
      'madrugador', count(*) filter (where extract(hour from creado at time zone 'Europe/Madrid') between 6 and 8),
      'finde',     count(*) filter (where extract(isodow from creado at time zone 'Europe/Madrid') >= 6),
      'dias',      count(distinct (creado at time zone 'Europe/Madrid')::date),
      'campeonato', count(*) filter (where modo = 'campeonato'),
      'campeonato_mejor', coalesce(max(puntos) filter (where modo = 'campeonato'), 0),
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

  -- días seguidos jugando (cualquier partida) y máximo de partidas en un mismo día
  with d as (select distinct (creado at time zone 'Europe/Madrid')::date as dia from partidas where clave = p_clave),
       g as (select dia, dia - (row_number() over (order by dia))::int as grp from d),
       por_dia as (select (creado at time zone 'Europe/Madrid')::date as dia, count(*) as n from partidas where clave = p_clave group by 1)
  select jsonb_build_object(
      'racha_dias_max', coalesce((select max(c) from (select count(*) as c from g group by grp) x), 0),
      'max_dia',        coalesce((select max(n) from por_dia), 0),
      'retos_perfectos', (select count(*) from retos where clave = p_clave and total >= 10 and aciertos = total),
      'retos_podio', (select count(*) from (
          select clave, rank() over (partition by fecha order by puntos desc, creado) as pos from retos
          where fecha in (select fecha from retos where clave = p_clave) and fecha < hoy) x
        where x.clave = p_clave and x.pos <= 3),
      'fechas_reto', coalesce((select jsonb_agg(fecha order by fecha desc) from (select fecha from retos where clave = p_clave order by fecha desc limit 400) z), '[]'::jsonb))
    into extra;

  return r || extra || jsonb_build_object(
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

grant execute on function public.perfil(text) to anon, authenticated;
