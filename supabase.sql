-- Hall of Fame compartido para Liantes Quiz Metalero
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".

create table if not exists public.partidas (
  id        bigint generated always as identity primary key,
  nombre    text not null check (char_length(nombre) between 1 and 24),
  clave     text not null check (char_length(clave) between 1 and 40),
  puntos    integer not null check (puntos >= 0),
  aciertos  integer not null check (aciertos >= 0),
  total     integer not null check (total between 1 and 200),
  creado    timestamptz not null default now(),
  constraint aciertos_validos check (aciertos <= total),
  constraint puntos_validos  check (puntos <= total * 250)  -- máximo posible por pregunta
);

alter table public.partidas enable row level security;

-- Cualquiera puede ver el ranking y guardar su partida, pero nadie puede modificar ni borrar desde la web.
drop policy if exists "ver partidas" on public.partidas;
create policy "ver partidas" on public.partidas for select to anon, authenticated using (true);
drop policy if exists "guardar partida" on public.partidas;
create policy "guardar partida" on public.partidas for insert to anon, authenticated with check (true);

grant select, insert on public.partidas to anon, authenticated;

-- Puntos acumulados por jugador
create or replace view public.hall_of_fame with (security_invoker = true) as
select
  clave,
  (array_agg(nombre order by creado desc))[1] as nombre,
  sum(puntos)::int   as puntos,
  count(*)::int      as partidas,
  sum(aciertos)::int as aciertos,
  sum(total)::int    as total,
  max(puntos)::int   as mejor
from public.partidas
group by clave;

grant select on public.hall_of_fame to anon, authenticated;

-- Para empezar una temporada nueva (borra TODAS las puntuaciones), ejecuta solo:
--   truncate public.partidas;
