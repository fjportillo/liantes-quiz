-- Mantenimiento automático de la base de datos (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". Se puede volver a ejecutar sin problema.
--
-- Qué hace, una vez al mes (día 1 a las 4:00, hora UTC):
--   · Estadísticas anónimas (tabla eventos) de hace más de 90 días: las resume por día en eventos_archivo
--     y borra el detalle. Los informes diarios solo usan los últimos días, así que no cambian.
--   · Salas del modo evento de hace más de 14 días: se borran (con sus jugadores, preguntas y respuestas).
--   · Reportes de errores de hace más de 180 días: se borran (ya se habrán revisado).
-- NO toca nunca partidas, retos, PIN, el Hall of Fame ni las estadísticas de preguntas.
--
-- Además crea tamano_bd(), que dice cuánto ocupa la base de datos (para el informe diario).

-- 1) Resumen diario de las estadísticas antiguas
create table if not exists public.eventos_archivo (
  dia         date not null,
  tipo        text not null,
  dispositivo text not null default '',
  categoria   text not null default '',
  dificultad  text not null default '',
  veces       integer not null,
  preguntas   bigint,
  aciertos    bigint,
  puntos      bigint,
  primary key (dia, tipo, dispositivo, categoria, dificultad)
);
alter table public.eventos_archivo enable row level security;   -- sin políticas: no se lee desde la web

-- 2) La limpieza
create or replace function public.limpieza_mensual()
returns jsonb language plpgsql security definer set search_path = public as $$
declare corte timestamptz := (date_trunc('day', now() at time zone 'Europe/Madrid') - interval '90 days') at time zone 'Europe/Madrid';
        n_ev int := 0; n_salas int := 0; n_rep int := 0;
begin
  insert into eventos_archivo (dia, tipo, dispositivo, categoria, dificultad, veces, preguntas, aciertos, puntos)
  select (creado at time zone 'Europe/Madrid')::date, tipo, coalesce(dispositivo, ''), coalesce(categoria, ''), coalesce(dificultad, ''),
         count(*), sum(preguntas), sum(aciertos), sum(puntos)
  from eventos where creado < corte
  group by 1, 2, 3, 4, 5
  on conflict (dia, tipo, dispositivo, categoria, dificultad) do update
    set veces = eventos_archivo.veces + excluded.veces,
        preguntas = coalesce(eventos_archivo.preguntas, 0) + coalesce(excluded.preguntas, 0),
        aciertos  = coalesce(eventos_archivo.aciertos, 0)  + coalesce(excluded.aciertos, 0),
        puntos    = coalesce(eventos_archivo.puntos, 0)    + coalesce(excluded.puntos, 0);
  delete from eventos where creado < corte;
  get diagnostics n_ev = row_count;

  if to_regclass('public.salas') is not null then
    delete from salas where creado < now() - interval '14 days';
    get diagnostics n_salas = row_count;
  end if;

  if to_regclass('public.reportes') is not null then
    delete from reportes where creado < now() - interval '180 days';
    get diagnostics n_rep = row_count;
  end if;

  return jsonb_build_object('eventos_resumidos', n_ev, 'salas_borradas', n_salas, 'reportes_borrados', n_rep);
end $$;
revoke all on function public.limpieza_mensual() from public, anon, authenticated;

-- 3) Programarla cada mes con pg_cron (incluido en el plan gratuito)
create extension if not exists pg_cron;
do $$ begin
  perform cron.unschedule('liantes-limpieza-mensual');
exception when others then null; end $$;
select cron.schedule('liantes-limpieza-mensual', '0 4 1 * *', $$select public.limpieza_mensual()$$);

-- 4) Tamaño de la base de datos (lectura pública, sin datos personales)
create or replace function public.tamano_bd()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'total_mb',    round(pg_database_size(current_database()) / 1048576.0, 1),
    'limite_mb',   500,
    'partidas_mb', round(pg_total_relation_size('public.partidas') / 1048576.0, 1),
    'eventos_mb',  round(pg_total_relation_size('public.eventos') / 1048576.0, 1))
$$;
grant execute on function public.tamano_bd() to anon, authenticated;

-- Para comprobarlo ahora mismo:
select public.tamano_bd() as tamano, (select count(*) from cron.job where jobname = 'liantes-limpieza-mensual') as tarea_programada;
