-- Estadísticas anónimas de uso para Liantes Quiz Metalero
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".

create table if not exists public.eventos (
  id          bigint generated always as identity primary key,
  tipo        text not null check (tipo in ('visita','inicio','fin','abandono')),
  dispositivo text check (dispositivo in ('movil','tablet','escritorio')),
  categoria   text check (char_length(categoria) <= 40),
  dificultad  text check (char_length(dificultad) <= 10),
  preguntas   integer check (preguntas between 0 and 2000),
  aciertos    integer check (aciertos between 0 and 2000),
  puntos      integer check (puntos between 0 and 500000),
  creado      timestamptz not null default now()
);

alter table public.eventos enable row level security;

-- La web solo puede AÑADIR eventos; nadie puede leerlos, modificarlos ni borrarlos desde fuera.
drop policy if exists "registrar evento" on public.eventos;
create policy "registrar evento" on public.eventos for insert to anon, authenticated with check (true);
grant insert on public.eventos to anon, authenticated;

-- Resúmenes por día (solo totales, sin datos individuales), en hora de Madrid
create or replace view public.stats_diarias as
select (creado at time zone 'Europe/Madrid')::date as dia,
  count(*) filter (where tipo = 'visita')                               as visitas,
  count(*) filter (where tipo = 'visita' and dispositivo = 'movil')     as visitas_movil,
  count(*) filter (where tipo = 'visita' and dispositivo = 'tablet')    as visitas_tablet,
  count(*) filter (where tipo = 'visita' and dispositivo = 'escritorio') as visitas_escritorio,
  count(*) filter (where tipo = 'inicio')                               as partidas_iniciadas,
  count(*) filter (where tipo = 'fin')                                  as partidas_terminadas,
  count(*) filter (where tipo = 'abandono')                             as abandonos,
  round(avg(puntos) filter (where tipo = 'fin'))::int                   as puntos_medios,
  round(100.0 * sum(aciertos) filter (where tipo = 'fin') / nullif(sum(preguntas) filter (where tipo = 'fin'), 0), 1) as pct_aciertos
from public.eventos group by 1;

create or replace view public.stats_categorias as
select (creado at time zone 'Europe/Madrid')::date as dia,
  coalesce(nullif(categoria, ''), 'Todas') as categoria,
  count(*) as partidas
from public.eventos where tipo = 'inicio' group by 1, 2;

create or replace view public.stats_jugadores as
select (creado at time zone 'Europe/Madrid')::date as dia,
  count(*)              as partidas_guardadas,
  count(distinct clave) as jugadores,
  max(puntos)           as mejor_puntuacion,
  (array_agg(nombre order by puntos desc))[1] as mejor_jugador
from public.partidas group by 1;

grant select on public.stats_diarias, public.stats_categorias, public.stats_jugadores to anon, authenticated;
