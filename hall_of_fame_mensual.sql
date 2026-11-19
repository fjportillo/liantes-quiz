-- Hall of Fame mensual + campeones de cada mes para Liantes Quiz Metalero
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- No borra nada: el ranking del mes solo cuenta las partidas del mes en curso (hora de Madrid),
-- así que se "vacía" solo el día 1 a las 00:00. Las partidas antiguas se usan para los campeones.

-- Ranking acumulado del mes en curso
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
select
  clave,
  (array_agg(nombre order by creado desc))[1] as nombre,
  sum(puntos)::int   as puntos,
  count(*)::int      as partidas,
  sum(aciertos)::int as aciertos,
  sum(total)::int    as total,
  max(puntos)::int   as mejor
from public.partidas
where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
group by clave;

-- Mejores partidas sueltas del mes en curso
create or replace view public.mejores_partidas_mes with (security_invoker = true) as
select nombre, puntos, aciertos, total, creado
from public.partidas
where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid');

-- Top 3 de cada mes ya terminado
create or replace view public.campeones_mensuales with (security_invoker = true) as
with m as (
  select
    to_char(date_trunc('month', creado at time zone 'Europe/Madrid'), 'YYYY-MM') as mes,
    clave,
    (array_agg(nombre order by creado desc))[1] as nombre,
    sum(puntos)::int as puntos,
    count(*)::int    as partidas,
    max(puntos)::int as mejor
  from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') < date_trunc('month', now() at time zone 'Europe/Madrid')
  group by 1, 2
), r as (
  select *, rank() over (partition by mes order by puntos desc, mejor desc) as puesto from m
)
select mes, puesto::int, nombre, puntos, partidas, mejor from r where puesto <= 3;

grant select on public.hall_of_fame_mes, public.mejores_partidas_mes, public.campeones_mensuales to anon, authenticated;
