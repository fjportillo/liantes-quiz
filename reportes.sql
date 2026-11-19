-- Reportes de errores en preguntas para Liantes Quiz Metalero
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".

create table if not exists public.reportes (
  id                 bigint generated always as identity primary key,
  pregunta           text not null check (char_length(pregunta) between 1 and 300),
  visual             text check (char_length(visual) <= 60),
  respuesta_correcta text check (char_length(respuesta_correcta) <= 150),
  categoria          text check (char_length(categoria) <= 40),
  motivo             text not null check (motivo in ('respuesta_erronea','varias_correctas','desactualizada','mal_escrita','otro')),
  comentario         text check (char_length(comentario) <= 300),
  creado             timestamptz not null default now()
);

alter table public.reportes enable row level security;

-- La web solo puede ENVIAR reportes; no puede leerlos, cambiarlos ni borrarlos.
drop policy if exists "enviar reporte" on public.reportes;
create policy "enviar reporte" on public.reportes for insert to anon, authenticated with check (true);
grant insert on public.reportes to anon, authenticated;

-- Resumen de los reportes de los últimos 30 días (lo usa la renovación semanal para corregir preguntas)
create or replace view public.reportes_recientes as
select
  pregunta,
  coalesce(visual, '')                 as visual,
  max(respuesta_correcta)              as respuesta_correcta,
  max(categoria)                       as categoria,
  motivo,
  count(*)::int                        as veces,
  string_agg(nullif(comentario, ''), ' | ' order by creado desc) as comentarios,
  max(creado)                          as ultimo
from public.reportes
where creado > now() - interval '30 days'
group by pregunta, coalesce(visual, ''), motivo;

grant select on public.reportes_recientes to anon, authenticated;
