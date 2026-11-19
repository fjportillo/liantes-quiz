-- Ranking mensual por MEJOR PARTIDA DE CADA DÍA (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Necesita haber ejecutado antes premios_reto.sql.
-- No borra nada. Hasta el 30-11-2026 el ranking sigue sumando todas las partidas (como siempre).
-- Desde el 1-12-2026: cada jugador suma, por cada día, solo su mejor partida de hasta 20 preguntas
-- (las partidas con más preguntas no puntúan para el ranking), más los premios del reto diario.

-- Partidas que cuentan para el ranking de su mes
create or replace view public.partidas_ranking with (security_invoker = true) as
with p as (
  select clave, nombre, puntos, aciertos, total, creado,
         (creado at time zone 'Europe/Madrid')::date as dia
  from public.partidas
), c as (
  select *, row_number() over (partition by clave, dia order by puntos desc, creado) as n
  from p
  where dia < date '2026-12-01' or total <= 20
)
select clave, nombre, puntos, aciertos, total, creado, dia
from c
where dia < date '2026-12-01' or n = 1;
grant select on public.partidas_ranking to anon, authenticated;

-- Ranking del mes en curso (mismas columnas que antes y "dias" al final)
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
with mes as (
  select * from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
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
  and ((creado at time zone 'Europe/Madrid')::date < date '2026-12-01' or total <= 20);

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
