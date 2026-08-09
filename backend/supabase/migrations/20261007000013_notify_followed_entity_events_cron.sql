-- Cron-Trigger für notify-followed-entity-events (siehe Funktions-
-- Kommentar): Nutzerwunsch "Ankündigung, wenn neues Konzert dazu kommt" für
-- gefolgte Personen/Ensembles/Venues. Gleicher 15-Minuten-Takt wie
-- notify-changes (20261002000010_notify_changes_cron.sql) — zeitnah, aber
-- nicht so oft wie die Daten-Enrichment-Crons, da pro betroffenem
-- Follower-Nutzer ein FCM-Call anfällt.
create or replace function run_notify_followed_entity_events()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/notify-followed-entity-events',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_notify_followed_entity_events: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'notify-followed-entity-events',
  '*/15 * * * *',
  $$ select run_notify_followed_entity_events(); $$
);
