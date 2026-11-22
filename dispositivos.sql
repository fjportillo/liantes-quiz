-- Dispositivos de cada jugador: para saber si dos nombres los usa la misma persona (mismo móvil u ordenador)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
-- Sirve igual para Liantes Quiz Metalero y para Sabelotodo (ejecútalo en cada proyecto). Requiere pin.sql.
--
-- Cada navegador guarda un identificador aleatorio (no es el nombre del aparato, ni la IP, ni nada personal).
-- La web lo envía, como mucho una vez al día por jugador, al entrar con PIN o al guardar una partida.
-- Solo cuenta a partir de ahora. No detecta a quien use otro aparato u otro navegador, ni a quien borre los datos del navegador.
-- Ocupa muy poco (una fila por jugador y dispositivo) y las filas sin uso durante un año se borran solas.
--
-- CONSULTAS:
--   · ¿Comparten dispositivo dos jugadores? (las claves van en minúsculas, sin espacios ni tildes)
--       select disp, string_agg(clave, ', ' order by clave) as jugadores, max(ultima) as ultima_vez
--       from public.jugadores_dispositivos where clave in ('juanpe', 'juanpedro')
--       group by disp having count(*) > 1;
--   · Todos los dispositivos usados con más de un nombre:
--       select disp, string_agg(clave, ', ' order by clave) as jugadores, max(ultima) as ultima_vez
--       from public.jugadores_dispositivos group by disp having count(*) > 1 order by ultima_vez desc;
--   · Dispositivos de un jugador:
--       select * from public.jugadores_dispositivos where clave = 'juanpe' order by ultima desc;

create table if not exists public.jugadores_dispositivos (
  clave    text not null check (char_length(clave) between 1 and 40),
  disp     text not null check (char_length(disp) between 8 and 64),
  primera  timestamptz not null default now(),
  ultima   timestamptz not null default now(),
  veces    integer not null default 1,
  primary key (clave, disp)
);
create index if not exists jugadores_dispositivos_disp on public.jugadores_dispositivos (disp);
alter table public.jugadores_dispositivos enable row level security;   -- sin políticas: nadie la lee desde la web

create or replace function public.registrar_dispositivo(p_clave text, p_pin text, p_disp text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if p_disp is null or p_disp !~ '^[0-9a-zA-Z-]{8,64}$' then return; end if;
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is null or p_pin is null or h <> crypt(p_pin, h) then return; end if;
  insert into jugadores_dispositivos (clave, disp) values (p_clave, p_disp)
  on conflict (clave, disp) do update set ultima = now(), veces = jugadores_dispositivos.veces + 1;
  if random() < 0.01 then delete from jugadores_dispositivos where ultima < now() - interval '1 year'; end if;
end $$;
revoke execute on function public.registrar_dispositivo(text, text, text) from public;
grant execute on function public.registrar_dispositivo(text, text, text) to anon, authenticated;
