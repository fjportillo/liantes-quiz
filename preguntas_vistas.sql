-- Cuántas veces ha salido cada pregunta (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
-- La renovación semanal de los viernes retira las preguntas que más veces han salido.
--
-- Consultas útiles:
--   · Las 30 que más han salido:  select * from public.preguntas_ranking limit 30;
--   · Empezar el recuento de cero: truncate public.preguntas_vistas;

create table if not exists public.preguntas_vistas (
  pregunta    text not null check (char_length(pregunta) between 1 and 300),
  visual      text not null default '' check (char_length(visual) <= 120),
  veces       integer not null default 0,   -- partidas (o rondas de evento) en las que ha salido
  respuestas  integer not null default 0,   -- respuestas recibidas (en el modo evento, una por jugador)
  aciertos    integer not null default 0,
  primera     timestamptz not null default now(),
  ultima      timestamptz not null default now(),
  primary key (pregunta, visual)
);
alter table public.preguntas_vistas enable row level security;
drop policy if exists "ver preguntas vistas" on public.preguntas_vistas;
create policy "ver preguntas vistas" on public.preguntas_vistas for select to anon, authenticated using (true);
grant select on public.preguntas_vistas to anon, authenticated;

-- La web envía al terminar (o abandonar) la lista de preguntas que han salido:
--   [{"q": "texto", "v": "visual", "r": respuestas, "a": aciertos}, ...]
create or replace function public.contar_preguntas(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 60 then return; end if;
  insert into preguntas_vistas as t (pregunta, visual, veces, respuestas, aciertos)
  select left(e->>'q', 300), left(coalesce(e->>'v', ''), 120), count(*),
         sum(least(greatest(coalesce((e->>'r')::int, 1), 0), 500)),
         sum(least(greatest(coalesce((e->>'a')::int, 0), 0), 500))
  from jsonb_array_elements(p) e
  where coalesce(e->>'q', '') <> ''
  group by 1, 2
  on conflict (pregunta, visual) do update set
    veces = t.veces + excluded.veces,
    respuestas = t.respuestas + excluded.respuestas,
    aciertos = t.aciertos + least(excluded.aciertos, excluded.respuestas),
    ultima = now();
end $$;
grant execute on function public.contar_preguntas(jsonb) to anon, authenticated;

create or replace view public.preguntas_ranking with (security_invoker = true) as
select pregunta, visual, veces, respuestas, aciertos,
       case when respuestas > 0 then round(100.0 * aciertos / respuestas)::int end as pct_aciertos,
       primera, ultima
from public.preguntas_vistas
order by veces desc, respuestas desc;
grant select on public.preguntas_ranking to anon, authenticated;
