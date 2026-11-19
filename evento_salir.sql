-- Permite que un jugador salga de una sala del modo evento.
-- Pégalo en Supabase > SQL Editor > New query y pulsa "Run" (si ya ejecutaste evento.sql).
create or replace function public.ev_salir(p_jugador uuid, p_token uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from sala_jugadores where id = p_jugador and token = p_token;
end $$;
grant execute on function public.ev_salir(uuid, uuid) to anon, authenticated;
