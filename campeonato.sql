-- Partidas de CAMPEONATO y de PRÁCTICA (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Sustituye a ranking_diario.sql (puedes ejecutarlo encima).
-- No borra nada. Desde el 1-12-2026:
--   · Campeonato: 20 preguntas, dificultad automática, todas las categorías. Es lo que puntúa: cada día cuenta
--     la mejor partida de campeonato (o el reto, si es mejor) de cada jugador, más los premios del reto.
--   · Práctica: el jugador elige preguntas, dificultad y categoría. Se guarda (perfil), pero no puntúa.

-- Guardar partida: ahora distingue campeonato / práctica / reto
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
            case when p_modo in ('reto', 'campeonato', 'practica') then p_modo else 'normal' end,
            greatest(0, least(coalesce(p_racha, 0), p_total)),
            case when jsonb_typeof(p_detalle) = 'object' and length(p_detalle::text) < 2000 then p_detalle end);
  return 'ok';
end $$;
grant execute on function public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text) to anon, authenticated;

-- Partidas que cuentan para el ranking de su mes
create or replace view public.partidas_ranking with (security_invoker = true) as
with p as (
  select clave, nombre, puntos, aciertos, total, creado, modo,
         (creado at time zone 'Europe/Madrid')::date as dia
  from public.partidas
), c as (
  select *, row_number() over (partition by clave, dia order by puntos desc, creado) as n
  from p
  where dia < date '2026-12-01' or (total <= 20 and coalesce(modo, 'normal') <> 'practica')
)
select clave, nombre, puntos, aciertos, total, creado, dia
from c
where dia < date '2026-12-01' or n = 1;
grant select on public.partidas_ranking to anon, authenticated;

-- Ranking del mes en curso (mismas columnas que antes y "dias" al final)
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
with mes as (                      -- partidas del mes (desde diciembre, sin las de práctica)
  select * from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
    and ((creado at time zone 'Europe/Madrid')::date < date '2026-12-01' or coalesce(modo, 'normal') <> 'practica')
), todas as (                      -- estadísticas de todas las partidas del mes
  select clave, (array_agg(nombre order by creado desc))[1] as nombre, count(*)::int as partidas,
         sum(aciertos)::int as aciertos, sum(total)::int as total
  from mes group by clave
), cuentan as (                    -- puntos que cuentan para el ranking
  select clave, sum(puntos)::int as puntos, max(puntos)::int as mejor, count(distinct dia)::int as dias
  from public.partidas_ranking
  where date_trunc('month', dia::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
), b as (
  select clave, sum(bonus) as bonus, count(*) filter (where puesto = 1) as victorias
  from public.reto_premios
  where date_trunc('month', fecha::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
)
select t.clave, t.nombre,
       (coalesce(c.puntos, 0) + coalesce(b.bonus, 0))::int as puntos,
       t.partidas, t.aciertos, t.total,
       coalesce(c.mejor, 0)::int     as mejor,
       coalesce(b.bonus, 0)::int     as bonus_reto,
       coalesce(b.victorias, 0)::int as retos_ganados,
       coalesce(c.dias, 0)::int      as dias
from todas t
left join cuentan c using (clave)
left join b using (clave);

-- Mejores partidas del mes (desde diciembre, solo las de hasta 20 preguntas)
create or replace view public.mejores_partidas_mes with (security_invoker = true) as
select nombre, puntos, aciertos, total, creado
from public.partidas
where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
  and ((creado at time zone 'Europe/Madrid')::date < date '2026-12-01' or (total <= 20 and coalesce(modo, 'normal') <> 'practica'));

-- Campeones de cada mes terminado, con la misma regla
create or replace view public.campeones_mensuales with (security_invoker = true) as
with m as (
  select to_char(dia, 'YYYY-MM') as mes, clave,
         (array_agg(nombre order by creado desc))[1] as nombre,
         sum(puntos)::int as puntos, count(*)::int as partidas, max(puntos)::int as mejor
  from public.partidas_ranking
  where date_trunc('month', dia::timestamp) < date_trunc('month', now() at time zone 'Europe/Madrid')
  group by 1, 2
), b as (
  select to_char(fecha, 'YYYY-MM') as mes, clave, sum(bonus)::int as bonus
  from public.reto_premios group by 1, 2
), t as (
  select m.mes, m.clave, m.nombre, (m.puntos + coalesce(b.bonus, 0))::int as puntos, m.partidas, m.mejor,
         coalesce(b.bonus, 0)::int as bonus_reto
  from m left join b on b.mes = m.mes and b.clave = m.clave
), r as (
  select *, rank() over (partition by mes order by puntos desc, mejor desc) as puesto from t
)
select mes, puesto::int, nombre, puntos, partidas, mejor, bonus_reto from r where puesto <= 3;

grant select on public.hall_of_fame_mes, public.mejores_partidas_mes, public.campeones_mensuales to anon, authenticated;
