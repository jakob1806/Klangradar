-- Alle 15 Minuten — Änderungen sollen zeitnah ankommen (anders als die
-- tägliche "morgen"-Erinnerung), aber nicht so oft wie der 10-Minuten-Takt
-- der Daten-Enrichment-Crons, da hier zusätzlich pro betroffenem Favoriten-
-- Nutzer ein FCM-Call anfällt.
create or replace function run_notify_changes()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/notify-changes',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_notify_changes: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'notify-changes',
  '*/15 * * * *',
  $$ select run_notify_changes(); $$
);
