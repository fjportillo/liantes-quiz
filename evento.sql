-- MODO EVENTO de Liantes Quiz Metalero (pantalla grande + móviles)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
-- Las tablas quedan cerradas: la web solo puede usarlas a través de las funciones de abajo,
-- que comprueban la clave secreta del presentador y el token de cada jugador.

create extension if not exists pgcrypto;

create table if not exists public.salas (
  codigo        text primary key,
  host_secret   text not null,
  estado        text not null default 'lobby' check (estado in ('lobby','pregunta','resultado','fin')),
  idx           integer not null default -1,
  total         integer not null default 10,
  segundos      integer not null default 20,
  pregunta      jsonb,
  correcta      integer,
  inicio        timestamptz,
  deadline      timestamptz,
  creado        timestamptz not null default now()
);

create table if not exists public.sala_jugadores (
  id      uuid primary key default gen_random_uuid(),
  codigo  text not null references public.salas(codigo) on delete cascade,
  nombre  text not null check (char_length(nombre) between 1 and 20),
  token   uuid not null default gen_random_uuid(),
  creado  timestamptz not null default now()
);
create unique index if not exists sala_jugadores_nombre on public.sala_jugadores (codigo, lower(nombre));

create table if not exists public.sala_preguntas (
  codigo    text not null references public.salas(codigo) on delete cascade,
  idx       integer not null,
  correcta  integer not null,
  segundos  integer not null,
  primary key (codigo, idx)
);

create table if not exists public.sala_respuestas (
  codigo   text not null references public.salas(codigo) on delete cascade,
  jugador  uuid not null references public.sala_jugadores(id) on delete cascade,
  idx      integer not null,
  opcion   integer not null check (opcion between 0 and 3),
  ms       integer not null,
  creado   timestamptz not null default now(),
  primary key (codigo, jugador, idx)
);

alter table public.salas           enable row level security;
alter table public.sala_jugadores  enable row level security;
alter table public.sala_preguntas  enable row level security;
alter table public.sala_respuestas enable row level security;
-- (sin políticas: nadie puede leer ni escribir directamente desde la web)

-- ---------- Funciones del presentador ----------
create or replace function public.ev_crear_sala(p_secret text, p_total int, p_segundos int)
returns text language plpgsql security definer set search_path = public as $$
declare c text; letras text := 'ABCDEFGHJKLMNPQRSTUVWXYZ'; i int;
begin
  if char_length(p_secret) < 16 then raise exception 'secreto no válido'; end if;
  loop
    c := '';
    for i in 1..4 loop c := c || substr(letras, 1 + floor(random() * length(letras))::int, 1); end loop;
    exit when not exists (select 1 from salas where codigo = c);
  end loop;
  insert into salas (codigo, host_secret, total, segundos)
  values (c, p_secret, greatest(1, least(p_total, 50)), greatest(10, least(p_segundos, 60)));
  delete from salas where creado < now() - interval '2 days';   -- limpieza de salas antiguas
  return c;
end $$;

create or replace function public.ev_pregunta(p_codigo text, p_secret text, p_idx int, p_pregunta jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare s salas;
begin
  select * into s from salas where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'sala no encontrada'; end if;
  update salas set estado = 'pregunta', idx = p_idx, pregunta = p_pregunta, correcta = null,
    inicio = now(), deadline = now() + make_interval(secs => s.segundos)
  where codigo = s.codigo;
end $$;

create or replace function public.ev_revelar(p_codigo text, p_secret text, p_correcta int)
returns void language plpgsql security definer set search_path = public as $$
declare s salas;
begin
  select * into s from salas where codigo = upper(p_codigo) and host_secret = p_secret;
  if not found then raise exception 'sala no encontrada'; end if;
  update salas set estado = 'resultado', correcta = p_correcta, deadline = least(deadline, now()) where codigo = s.codigo;
  insert into sala_preguntas (codigo, idx, correcta, segundos) values (s.codigo, s.idx, p_correcta, s.segundos)
  on conflict (codigo, idx) do update set correcta = excluded.correcta;
end $$;

create or replace function public.ev_fin(p_codigo text, p_secret text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update salas set estado = 'fin' where codigo = upper(p_codigo) and host_secret = p_secret;
end $$;

-- ---------- Funciones del jugador ----------
create or replace function public.ev_unirse(p_codigo text, p_nombre text)
returns table (jugador uuid, token uuid) language plpgsql security definer set search_path = public as $$
declare s salas; n text := btrim(p_nombre);
begin
  select * into s from salas where codigo = upper(p_codigo);
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  if s.estado = 'fin' then raise exception 'SALA_TERMINADA'; end if;
  if char_length(n) < 1 or char_length(n) > 20 then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if exists (select 1 from sala_jugadores j where j.codigo = s.codigo and lower(j.nombre) = lower(n)) then raise exception 'NOMBRE_OCUPADO'; end if;
  if (select count(*) from sala_jugadores j where j.codigo = s.codigo) >= 200 then raise exception 'SALA_LLENA'; end if;
  return query insert into sala_jugadores (codigo, nombre) values (s.codigo, n) returning id, sala_jugadores.token;
end $$;

create or replace function public.ev_responder(p_codigo text, p_jugador uuid, p_token uuid, p_idx int, p_opcion int)
returns integer language plpgsql security definer set search_path = public as $$
declare s salas; t int;
begin
  select * into s from salas where codigo = upper(p_codigo);
  if not found then raise exception 'SALA_NO_EXISTE'; end if;
  if not exists (select 1 from sala_jugadores where id = p_jugador and token = p_token and codigo = s.codigo) then raise exception 'JUGADOR_NO_VALIDO'; end if;
  if s.estado <> 'pregunta' or s.idx <> p_idx or now() > s.deadline + interval '1 second' then raise exception 'FUERA_DE_TIEMPO'; end if;
  t := greatest(0, least(s.segundos * 1000, (extract(epoch from (now() - s.inicio)) * 1000)::int));
  insert into sala_respuestas (codigo, jugador, idx, opcion, ms) values (s.codigo, p_jugador, p_idx, p_opcion, t)
  on conflict do nothing;
  return t;
end $$;

-- ---------- Vistas públicas (solo lo necesario para mostrar el juego) ----------
create or replace view public.ev_estado as
select codigo, estado, idx, total, segundos, pregunta, correcta, deadline, now() as ahora,
  (select count(*) from sala_jugadores j where j.codigo = s.codigo)::int as jugadores,
  (select count(*) from sala_respuestas r where r.codigo = s.codigo and r.idx = s.idx)::int as respondidas
from salas s;

create or replace view public.ev_jugadores as
select codigo, nombre, creado from sala_jugadores;

create or replace view public.ev_votos as
select r.codigo, r.idx, r.opcion, count(*)::int as votos
from sala_respuestas r join salas s on s.codigo = r.codigo
where s.estado in ('resultado','fin') or r.idx < s.idx
group by r.codigo, r.idx, r.opcion;

-- 100 puntos por acierto + hasta 100 de bonus por rapidez
create or replace view public.ev_ranking as
select j.codigo, j.id as jugador, j.nombre,
  coalesce(sum(case when r.opcion = p.correcta then 100 + round(100.0 * greatest(0, p.segundos * 1000 - r.ms) / (p.segundos * 1000)) end), 0)::int as puntos,
  count(*) filter (where r.opcion = p.correcta)::int as aciertos
from sala_jugadores j
left join sala_respuestas r on r.jugador = j.id
left join sala_preguntas p on p.codigo = r.codigo and p.idx = r.idx
group by j.codigo, j.id, j.nombre;

grant select on public.ev_estado, public.ev_jugadores, public.ev_votos, public.ev_ranking to anon, authenticated;
grant execute on function public.ev_crear_sala(text,int,int), public.ev_pregunta(text,text,int,jsonb), public.ev_revelar(text,text,int),
  public.ev_fin(text,text), public.ev_unirse(text,text), public.ev_responder(text,uuid,uuid,int,int) to anon, authenticated;
