-- Erstellt von Claude Code (25.10.2026, Nutzerwunsch "beschleunige, alles
-- durchsuchen"): Programmheft-Suche und Werkeinführungen alle 5 Minuten mit
-- größeren Paketen, damit die erste Runde in ~1–2 h statt ~9 h durch ist.
create or replace function run_find_program_booklets()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/find-program-booklets',
    body := '{"limit": 50}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(), 'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000);
exception when others then
  raise warning 'run_find_program_booklets: % (%)', sqlerrm, sqlstate;
end; $$;

create or replace function run_work_introductions()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/work-introduction',
    body := '{"limit": 40}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(), 'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000);
exception when others then
  raise warning 'run_work_introductions: % (%)', sqlerrm, sqlstate;
end; $$;

select cron.unschedule('find-program-booklets') where exists (select 1 from cron.job where jobname = 'find-program-booklets');
select cron.schedule('find-program-booklets', '*/5 * * * *', $$ select run_find_program_booklets(); $$);
select cron.unschedule('work-introductions') where exists (select 1 from cron.job where jobname = 'work-introductions');
select cron.schedule('work-introductions', '2-59/5 * * * *', $$ select run_work_introductions(); $$);
