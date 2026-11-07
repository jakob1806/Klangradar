-- Erstellt von Claude Code (07.11.2026): Werkdauern ergänzen (nur 9 von
-- ~2.950 Werken hatten eine). Grundlage für „Jetzt läuft …“ in der
-- Live-Aktivität. Läuft alle 10 Minuten, je 10 Werke, kommende zuerst.
alter table public.works add column if not exists duration_checked_at timestamptz;

create or replace function run_work_duration_enrichment()
returns void language plpgsql as $$
declare
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-work-duration',
    body := '{"limit": 10}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key, 'Authorization', 'Bearer ' || v_anon_key),
    timeout_milliseconds := 120000
  );
exception when others then
  raise warning 'run_work_duration_enrichment fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'work-duration-enrichment') then
    perform cron.unschedule('work-duration-enrichment');
  end if;
  perform cron.schedule('work-duration-enrichment', '3-59/10 * * * *', 'select run_work_duration_enrichment()');
end $$;
