-- Erstellt von Claude Code (25.10.2026): Werkangaben aus Programmheften und
-- Veranstalter-Beschreibungen (Edge Function booklet-work-facts).
alter table events add column if not exists booklet_facts_checked_at timestamptz;
alter table works add column if not exists introduction_source text;
update works set introduction_source = 'wikipedia' where introduction_de is not null and introduction_source is null;

create or replace function run_booklet_work_facts()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/booklet-work-facts',
    body := '{"limit": 12}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(), 'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000);
exception when others then
  raise warning 'run_booklet_work_facts: % (%)', sqlerrm, sqlstate;
end; $$;

select cron.unschedule('booklet-work-facts') where exists (select 1 from cron.job where jobname = 'booklet-work-facts');
select cron.schedule('booklet-work-facts', '4-59/5 * * * *', $$ select run_booklet_work_facts(); $$);
