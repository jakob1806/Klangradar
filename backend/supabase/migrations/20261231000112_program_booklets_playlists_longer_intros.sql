-- Erstellt von Claude Code (25.10.2026):
-- * Programmhefte für alle Konzerte suchen (find-program-booklets, alle
--   30 Min.; pro Termin höchstens alle 20 h erneut, bis ein Heft da ist).
-- * Offizielle Playlists (MPhil-Konzertseiten) speichern.
-- * Werkeinführungen ausführlicher neu erzeugen (Einleitung + Entstehung).
alter table events add column if not exists program_booklet_checked_at timestamptz;
alter table events add column if not exists playlist_urls jsonb;

create or replace function run_find_program_booklets()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/find-program-booklets',
    body := '{"limit": 40}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(), 'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000);
exception when others then
  raise warning 'run_find_program_booklets: % (%)', sqlerrm, sqlstate;
end; $$;

select cron.unschedule('find-program-booklets') where exists (select 1 from cron.job where jobname = 'find-program-booklets');
select cron.schedule('find-program-booklets', '*/30 * * * *', $$ select run_find_program_booklets(); $$);

update works set introduction_checked_at = null;

update events set mphil_detail_synced_at = null, mphil_detail_sync_error = null
where start_datetime >= now() and (website_url ilike '%mphil.de/%' or external_id ilike '%mphil.de/%');
