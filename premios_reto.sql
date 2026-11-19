-- Premio del reto diario en el ranking mensual + puntos por dificultad (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Necesita haber ejecutado antes retos_perfil.sql.
-- No borra nada. Los premios empiezan a contar con los retos del 1 de diciembre de 2026.
--
-- PREMIOS: al cerrarse cada día (medianoche, hora de Madrid), los tres mejores del reto de ese día suman
--          +300 / +200 / +100 puntos al ranking del mes. Solo si ese día jugaron al menos 3 personas.
--          Empate a puntos: gana quien terminó antes.
-- Consultas útiles:  select * from public.reto_premios order by fecha desc, puesto;

-- 1) Nuevos límites de puntos (con puntos por dificultad una pregunta difícil puede dar hasta 350)
alter table public.partidas drop constraint if exists puntos_validos;
alter table public.partidas add constraint puntos_validos check (puntos <= total * 350);
alter table public.retos drop constraint if exists retos_puntos_check;
alter table public.retos add constraint retos_puntos_check check (puntos between 0 and 3500);

-- 2) Premios de cada reto ya cerrado
create or replace view public.reto_premios with (security_invoker = true) as
with d as (
  select fecha, clave, nombre, puntos, creado,
         row_number() over (partition by fecha order by puntos desc, creado) as puesto,
         count(*) over (partition by fecha) as jugadores
  from public.retos
  where fecha >= date '2026-12-01'
    and fecha < (now() at time zone 'Europe/Madrid')::date
)
select fecha, clave, nombre, puesto::int as puesto, jugadores::int as jugadores,
       (case puesto when 1 then 300 when 2 then 200 else 100 end)::int as bonus
from d
where jugadores >= 3 and puesto <= 3;
grant select on public.reto_premios to anon, authenticated;

-- 3) Ranking del mes en curso: partidas + premios del reto (mismas columnas que antes y dos nuevas al final)
create or replace view public.hall_of_fame_mes with (security_invoker = true) as
select g.clave, g.nombre,
       (g.puntos + coalesce(b.bonus, 0))::int as puntos,
       g.partidas, g.aciertos, g.total, g.mejor,
       coalesce(b.bonus, 0)::int     as bonus_reto,
       coalesce(b.victorias, 0)::int as retos_ganados
from (
  select clave,
         (array_agg(nombre order by creado desc))[1] as nombre,
         sum(puntos)::int as puntos, count(*)::int as partidas,
         sum(aciertos)::int as aciertos, sum(total)::int as total, max(puntos)::int as mejor
  from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
) g
left join (
  select clave, sum(bonus) as bonus, count(*) filter (where puesto = 1) as victorias
  from public.reto_premios
  where date_trunc('month', fecha::timestamp) = date_trunc('month', now() at time zone 'Europe/Madrid')
  group by clave
) b using (clave);

-- 4) Campeones de cada mes terminado, también con los premios del reto
create or replace view public.campeones_mensuales with (security_invoker = true) as
with m as (
  select to_char(date_trunc('month', creado at time zone 'Europe/Madrid'), 'YYYY-MM') as mes,
         clave,
         (array_agg(nombre order by creado desc))[1] as nombre,
         sum(puntos)::int as puntos, count(*)::int as partidas, max(puntos)::int as mejor
  from public.partidas
  where date_trunc('month', creado at time zone 'Europe/Madrid') < date_trunc('month', now() at time zone 'Europe/Madrid')
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

grant select on public.hall_of_fame_mes, public.campeones_mensuales to anon, authenticated;
