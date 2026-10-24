-- Erstellt von Claude Code (Nutzerwunsch 24.10.2026):
-- * Werkeinführung (KI aus Wikipedia de/en, mit Quelle) + recherchierte
--   Satzfolge für Werke kommender Konzerte (Edge Function work-introduction).
-- * Programmhefte, falls online verfügbar (Detail-Scraper, _shared/programBooklet.ts).
-- * Erneuter MPhil-Abgleich: der Parser kannte eine dritte Titel-Schreibweise
--   nicht, dadurch fehlten Werke.

alter table works add column if not exists introduction_de text;
alter table works add column if not exists introduction_source_url text;
alter table works add column if not exists introduction_checked_at timestamptz;
alter table works add column if not exists movements_source text;
alter table events add column if not exists program_booklet_url text;

create or replace function run_work_introductions()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/work-introduction',
    body := '{"limit": 8}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(), 'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000);
exception when others then
  raise warning 'run_work_introductions: % (%)', sqlerrm, sqlstate;
end; $$;

select cron.unschedule('work-introductions') where exists (select 1 from cron.job where jobname = 'work-introductions');
select cron.schedule('work-introductions', '*/20 * * * *', $$ select run_work_introductions(); $$);

update events
set mphil_detail_synced_at = null, mphil_detail_sync_error = null
where start_datetime >= now()
  and (website_url ilike '%mphil.de/%' or external_id ilike '%mphil.de/%');
