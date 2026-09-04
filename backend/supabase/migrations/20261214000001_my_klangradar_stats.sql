-- ProfileView.swift ruft "Mein Klangradar" (klangradarStats) auf und erwartet
-- eine RPC public.my_klangradar_stats() ohne Parameter — die Funktion wurde
-- nie angelegt (PGRST202 "Could not find the function ... in the schema
-- cache" beim Öffnen von Profil -> Mein Klangradar). Zählungen bewusst
-- konsistent mit bereits live funktionierenden Definitionen: saved/planned
-- wie in coach_dashboard_context() (20261202000001_klangradar_ai_coach.sql),
-- visited aus dem neueren, eigens dafür gebauten event_attendance
-- (20261211000001_event_attendance.sql) statt der älteren
-- coach_event_reflections, followed_* aus den bestehenden
-- user_favorite_*-Tabellen.
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
