-- Erstellt von Claude Code (25.10.2026): Musikverein-Termine über die
-- offizielle Spielplan-JSON anreichern (Werke, Mitwirkende, Langtext).
alter table events
  add column if not exists musikverein_detail_synced_at timestamptz,
  add column if not exists musikverein_detail_sync_error text;

create or replace function run_musikverein_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-musikverein-events',
    body := '{"limit":20}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon,
      'x-internal-secret', internal_function_secret()),
    timeout_milliseconds := 150000
  );
exception when others then
  raise warning 'run_musikverein_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- Nachts kommende Termine erneut abgleichen (Besetzungsänderungen).
create or replace function queue_musikverein_resync()
returns void
language sql
as $$
  update events set musikverein_detail_synced_at = null
  where start_datetime between now() and now() + interval '120 days'
    and (website_url ilike '%musikverein.at/konzert%' or external_id ilike '%musikverein.at/konzert%');
$$;

select cron.unschedule(jobid) from cron.job where jobname in ('musikverein-detail-sync', 'musikverein-resync');
select cron.schedule('musikverein-detail-sync', '*/5 * * * *', $$ select run_musikverein_detail_sync(); $$);
select cron.schedule('musikverein-resync', '35 2 * * *', $$ select queue_musikverein_resync(); $$);
