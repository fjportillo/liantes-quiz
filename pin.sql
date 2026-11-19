-- PIN de 4 cifras para proteger los nombres del Hall of Fame (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run".
--
-- ADMINISTRACIÓN (ejecutar a mano cuando haga falta):
--   · Borrar el PIN de un jugador (si lo olvida o alguien se lo "robó"); la próxima vez que juegue podrá crear uno nuevo:
--       delete from public.jugadores_pin where clave = 'aliceinhell';
--     (la clave es el nombre en minúsculas, sin espacios, tildes ni símbolos: "Alice InHell" -> aliceinhell)
--   · Asignar tú un PIN a un jugador y dárselo en privado:
--       insert into public.jugadores_pin (clave, pin_hash) values ('aliceinhell', extensions.crypt('1234', extensions.gen_salt('bf')))
--       on conflict (clave) do update set pin_hash = excluded.pin_hash, fallos = 0, bloqueado_hasta = null;
--   · Ver qué nombres tienen PIN:
--       select clave, creado from public.jugadores_pin order by creado desc;

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.jugadores_pin (
  clave            text primary key check (char_length(clave) between 1 and 40),
  pin_hash         text not null,
  fallos           integer not null default 0,
  bloqueado_hasta  timestamptz,
  creado           timestamptz not null default now()
);
alter table public.jugadores_pin enable row level security;   -- sin políticas: nadie la lee desde la web

-- ¿El nombre está libre, tiene puntos pero no PIN, o ya tiene PIN?
create or replace function public.pin_estado(p_clave text)
returns text language sql stable security definer set search_path = public, extensions as $$
  select case
    when exists (select 1 from jugadores_pin where clave = p_clave) then 'con_pin'
    when exists (select 1 from partidas where clave = p_clave) then 'sin_pin'
    else 'libre' end
$$;

-- Crear el PIN (solo si el nombre aún no tiene uno)
create or replace function public.pin_crear(p_clave text, p_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_clave is null or char_length(p_clave) < 1 or char_length(p_clave) > 40 or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN_NO_VALIDO'; end if;
  insert into jugadores_pin (clave, pin_hash) values (p_clave, crypt(p_pin, gen_salt('bf'))) on conflict (clave) do nothing;
  return found;
end $$;

-- Comprobar el PIN: 'ok', 'mal', 'bloqueado' (5 fallos -> 15 minutos) o 'sin_pin'
create or replace function public.pin_comprobar(p_clave text, p_pin text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare r jugadores_pin;
begin
  select * into r from jugadores_pin where clave = p_clave;
  if not found then return 'sin_pin'; end if;
  if r.bloqueado_hasta is not null and r.bloqueado_hasta > now() then return 'bloqueado'; end if;
  if r.pin_hash = crypt(coalesce(p_pin, ''), r.pin_hash) then
    update jugadores_pin set fallos = 0, bloqueado_hasta = null where clave = p_clave;
    return 'ok';
  end if;
  update jugadores_pin set
    bloqueado_hasta = case when fallos + 1 >= 5 then now() + interval '15 minutes' else null end,
    fallos = case when fallos + 1 >= 5 then 0 else fallos + 1 end
  where clave = p_clave;
  return 'mal';
end $$;

-- Guardar una partida comprobando el PIN si el nombre lo tiene
create or replace function public.guardar_partida(p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is not null and (p_pin is null or h <> crypt(p_pin, h)) then raise exception 'PIN_INCORRECTO'; end if;
  insert into partidas (nombre, clave, puntos, aciertos, total) values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total);
end $$;

grant execute on function public.pin_estado(text), public.pin_crear(text,text), public.pin_comprobar(text,text),
  public.guardar_partida(text,text,int,int,int,text) to anon, authenticated;

-- A partir de ahora las partidas solo se guardan a través de guardar_partida (con comprobación de PIN)
drop policy if exists "guardar partida" on public.partidas;
revoke insert on public.partidas from anon, authenticated;
