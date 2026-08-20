-- Ein Kandidat-Event pro Nutzer für die Re-Engagement-Push (siehe Edge
-- Function notify-reengagement) — explizit über p_user_id statt auth.uid(),
-- weil die Funktion von der Edge Function mit Service-Role für BELIEBIGE
-- Nutzer aufgerufen wird, nicht im Kontext einer eingeloggten Session.
-- Bevorzugt ein Event an einer gefolgten Venue/Person/Ensemble, sonst null
-- (die Edge Function nutzt dann ihren eigenen plattformweiten Fallback).
create or replace function reengagement_candidate_event(p_user_id uuid)
returns table (id uuid, title text, slug text)
language sql
stable
as $$
  select e.id, e.title, e.slug
  from events e
  where e.status = 'scheduled'
    and e.start_datetime >= now()
    and (
      exists (select 1 from user_favorite_venues ufv where ufv.venue_id = e.venue_id and ufv.user_id = p_user_id)
      or exists (
        select 1 from event_participants ep
        join user_favorite_persons ufp on ufp.person_id = ep.person_id
        where ep.event_id = e.id and ufp.user_id = p_user_id
      )
      or exists (
        select 1 from event_participants ep
        join user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
        where ep.event_id = e.id and ufe.user_id = p_user_id
      )
    )
  order by e.start_datetime
  limit 1;
$$;

grant execute on function reengagement_candidate_event(uuid) to service_role;

-- Re-Engagement-Push für inaktive Nutzer (Discovery & Engagement,
-- Nutzeranfrage: "Nutzer gezielt auf interessante neue Inhalte
-- zurückbringen"). Nutzt die bisher ungenutzte notification_preferences-
-- Spalte "new_matching_events" (siehe Kommentar in notify-changes/index.ts:
-- "new_matching_events ... ist bewusst NICHT Teil dieser Funktion ...
-- architektonisch ein anderer Baustein" — das ist genau dieser Baustein).
-- Täglich morgens statt alle 15 Minuten wie notify-changes — ein Win-back
-- ist nicht zeitkritisch, und ein Nutzer soll nicht mehrfach am Tag dieselbe
-- "wir vermissen dich"-Push bekommen (zusätzlich zum 14-Tage-Cooldown der
-- Edge Function selbst).
create or replace function run_notify_reengagement()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/notify-reengagement',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_notify_reengagement: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'notify-reengagement',
  '0 9 * * *',
  $$ select run_notify_reengagement(); $$
);
