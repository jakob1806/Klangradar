-- 20261214000001_my_klangradar_stats.sql zeigt in `supabase migration list
-- --linked` als angewandt (local == remote), aber die Funktion existiert
-- laut Live-Test weiterhin nicht ("PGRST202 ... my_klangradar_stats without
-- parameters ... no matches were found in the schema cache", reproduziert
-- per curl gegen /rest/v1/rpc/my_klangradar_stats). Statt in der
-- Migrationshistorie zu reparieren, hier per neuer, idempotenter
-- (create or replace) Migration erneut angelegt -- unabhängig davon, ob der
-- vorige Lauf einen stillen Fehler hatte oder der PostgREST-Schema-Cache
-- die Funktion nur nie übernommen hat.
create or replace function public.my_klangradar_stats()
returns jsonb
language sql
stable
security invoker
as $$
  select jsonb_build_object(
    'saved_events', (select count(*) from favorites where user_id = auth.uid()),
    'planned_events', (
      select count(*) from favorites f
      join events e on e.id = f.event_id
      where f.user_id = auth.uid() and f.status = 'attending' and e.start_datetime >= now()
    ),
    'visited_events', (select count(*) from public.event_attendance where user_id = auth.uid() and status = 'attended'),
    'followed_persons', (select count(*) from user_favorite_persons where user_id = auth.uid()),
    'followed_ensembles', (select count(*) from user_favorite_ensembles where user_id = auth.uid()),
    'followed_venues', (select count(*) from user_favorite_venues where user_id = auth.uid()),
    'followed_works', (select count(*) from public.user_favorite_works where user_id = auth.uid())
  );
$$;

grant execute on function public.my_klangradar_stats() to authenticated;

notify pgrst, 'reload schema';
