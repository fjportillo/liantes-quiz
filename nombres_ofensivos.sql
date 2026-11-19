-- Filtro de nombres ofensivos (Liantes Quiz Metalero)
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run". No borra nada.
--
-- Impide crear usuarios (y guardar partidas) con insultos, palabras groseras o discriminatorias
-- en castellano, catalán o inglés. Detecta trucos habituales: mayúsculas, tildes, letras repetidas
-- ("puuuta"), números por letras ("put4", "m13rda") y símbolos ("p.u.t.a").
--
-- Dos tipos de palabra:
--   'contiene' → se bloquea aunque vaya pegada a otras letras ("ElGilipollas").
--   'palabra'  → solo si aparece como palabra suelta, para no bloquear nombres inocentes
--                (p. ej. "culo" no bloquea "Vehículo"; "dick" no bloquea "Bruce Dickinson").
--
-- ADMINISTRACIÓN:
--   · Añadir una palabra:   insert into public.nombres_prohibidos values ('palabrota', 'contiene');
--   · Quitar una palabra:   delete from public.nombres_prohibidos where palabra = 'palabrota';
--   · Probar un nombre:     select public.nombre_ofensivo('Nombre de prueba');
--   · Ver nombres del ranking que ya lo incumplen:
--       select distinct nombre from public.partidas where public.nombre_ofensivo(nombre);

create extension if not exists unaccent with schema extensions;

create table if not exists public.nombres_prohibidos (
  palabra text primary key,
  modo    text not null default 'contiene' check (modo in ('contiene', 'palabra'))
);
alter table public.nombres_prohibidos enable row level security;   -- sin políticas: la lista no se puede leer desde la web

insert into public.nombres_prohibidos (palabra, modo) values
  -- castellano
  ('hijodeputa','contiene'),('hijaputa','contiene'),('hijoputa','contiene'),('gilipollas','contiene'),('gilipoya','contiene'),
  ('maricon','contiene'),('subnormal','contiene'),('retrasado','contiene'),('malparido','contiene'),('malnacido','contiene'),
  ('cabron','contiene'),('pendejo','contiene'),('pendeja','contiene'),('chupapollas','contiene'),('comepollas','contiene'),
  ('soplapollas','contiene'),('chupamela','contiene'),('mamahuevo','contiene'),('mierda','contiene'),('follar','contiene'),
  ('follame','contiene'),('puton','contiene'),('putilla','contiene'),('cojones','contiene'),('capullo','contiene'),
  ('imbecil','contiene'),('idiota','contiene'),('jodete','contiene'),('joder','contiene'),('negrata','contiene'),
  ('sudaca','contiene'),('moromierda','contiene'),('travelo','contiene'),('bollera','contiene'),('tortillera','contiene'),
  ('mongolo','contiene'),('anormal','contiene'),('pederasta','contiene'),('pedofilo','contiene'),('zoofilia','contiene'),
  ('violador','contiene'),('vagina','contiene'),('nazi','contiene'),('hitler','contiene'),('siegheil','contiene'),
  ('puta','palabra'),('puto','palabra'),('putas','palabra'),('putos','palabra'),('culo','palabra'),('culos','palabra'),
  ('polla','palabra'),('pollas','palabra'),('cono','palabra'),('chocho','palabra'),('teta','palabra'),('tetas','palabra'),
  ('pene','palabra'),('verga','palabra'),('zorra','palabra'),('guarra','palabra'),('violar','palabra'),('mamon','palabra'),
  ('pedo','palabra'),('marica','palabra'),('cerdo','palabra'),('cerda','palabra'),('sexo','palabra'),('heil','palabra'),
  -- català
  ('fillputa','contiene'),('filldeputa','contiene'),('collons','contiene'),('malparit','contiene'),('merda','contiene'),
  ('cabro','palabra'),('cony','palabra'),('fotre','palabra'),
  -- english
  ('fuck','contiene'),('shit','contiene'),('bitch','contiene'),('cunt','contiene'),('asshole','contiene'),('whore','contiene'),
  ('slut','contiene'),('nigga','contiene'),('faggot','contiene'),('retard','contiene'),('wanker','contiene'),('porn','contiene'),
  ('rapist','contiene'),('dildo','contiene'),('penis','contiene'),('motherf','contiene'),('fck','contiene'),('fuk','contiene'),
  ('dick','palabra'),('dicks','palabra'),('cock','palabra'),('pussy','palabra'),('fag','palabra'),('twat','palabra'),
  ('rape','palabra'),('cum','palabra'),('sex','palabra'),('nigger','palabra'),('niger','palabra'),('tits','palabra'),('ass','palabra')
on conflict (palabra) do nothing;

-- Normaliza: minúsculas, sin tildes, números y símbolos por letras (0→o, 1→i, 3→e, 4→a, 5→s, 7→t, 8→b, @→a, $→s, !→i, |→l)
-- y todo lo que no sea letra pasa a espacio.
create or replace function public.norm_ofensivo(t text)
returns text language sql immutable set search_path = public, extensions as $$
  select trim(regexp_replace(translate(lower(extensions.unaccent(coalesce(t, ''))), '0134578@$!|', 'oieastbasil'), '[^a-z]+', ' ', 'g'))
$$;
-- Letras repetidas seguidas, una sola vez ("puuuta" → "puta")
create or replace function public.sin_repes(t text)
returns text language sql immutable as $$ select regexp_replace(coalesce(t, ''), '([a-z])\1+', '\1', 'g') $$;

-- ¿El nombre contiene alguna palabra prohibida?
-- Una palabra suelta coincide si es igual a la prohibida quitando letras repetidas y no es más corta que ella
-- (así "puuuta" se bloquea pero "Zora" o "Pola" no se confunden con "zorra" o "polla").
create or replace function public.nombre_ofensivo(p_nombre text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  with n as (select norm_ofensivo(p_nombre) as w),
       ws as (select x as raw from n, unnest(string_to_array(n.w, ' ') || replace(n.w, ' ', '')) x where x <> '')
  select exists (
    select 1 from nombres_prohibidos p, n
    where p.modo = 'contiene' and position(sin_repes(replace(norm_ofensivo(p.palabra), ' ', '')) in sin_repes(replace(n.w, ' ', ''))) > 0
  ) or exists (
    select 1 from nombres_prohibidos p, ws
    where p.modo = 'palabra' and sin_repes(ws.raw) = sin_repes(norm_ofensivo(p.palabra)) and length(ws.raw) >= length(norm_ofensivo(p.palabra))
  )
$$;
grant execute on function public.nombre_ofensivo(text) to anon, authenticated;

-- Crear el PIN: ahora también comprueba el nombre
drop function if exists public.pin_crear(text, text);
create or replace function public.pin_crear(p_clave text, p_pin text, p_nombre text default null)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_clave is null or char_length(p_clave) < 1 or char_length(p_clave) > 40 or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if nombre_ofensivo(p_clave) or nombre_ofensivo(p_nombre) then raise exception 'NOMBRE_OFENSIVO'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN_NO_VALIDO'; end if;
  insert into jugadores_pin (clave, pin_hash) values (p_clave, crypt(p_pin, gen_salt('bf'))) on conflict (clave) do nothing;
  return found;
end $$;
grant execute on function public.pin_crear(text, text, text) to anon, authenticated;

-- Guardar partida: igual que en login_obligatorio.sql, rechazando además los nombres ofensivos
create or replace function public.guardar_partida2(
  p_nombre text, p_clave text, p_puntos int, p_aciertos int, p_total int, p_pin text,
  p_modo text default 'normal', p_racha int default null, p_detalle jsonb default null, p_cuadro text default null)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare h text; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  if p_clave is null or p_clave = '' or p_clave = 'anonimo' then raise exception 'NOMBRE_NO_VALIDO'; end if;
  if nombre_ofensivo(p_clave) or nombre_ofensivo(p_nombre) then raise exception 'NOMBRE_OFENSIVO'; end if;
  select pin_hash into h from jugadores_pin where clave = p_clave;
  if h is null then raise exception 'PIN_OBLIGATORIO'; end if;
  if p_pin is null or h <> crypt(p_pin, h) then raise exception 'PIN_INCORRECTO'; end if;
  if p_modo = 'reto' then
    insert into retos (fecha, clave, nombre, puntos, aciertos, total, cuadro)
      values (hoy, left(p_clave, 40), left(p_nombre, 24), p_puntos, p_aciertos, p_total, left(p_cuadro, 40))
      on conflict (fecha, clave) do nothing;
    if not found then return 'repetido'; end if;
  end if;
  insert into partidas (nombre, clave, puntos, aciertos, total, modo, racha, detalle)
    values (left(p_nombre, 24), left(p_clave, 40), p_puntos, p_aciertos, p_total,
            case when p_modo in ('reto', 'campeonato', 'practica') then p_modo else 'normal' end,
            greatest(0, least(coalesce(p_racha, 0), p_total)),
            case when jsonb_typeof(p_detalle) = 'object' and length(p_detalle::text) < 2000 then p_detalle end);
  return 'ok';
end $$;
grant execute on function public.guardar_partida2(text,text,int,int,int,text,text,int,jsonb,text) to anon, authenticated;
