-- Automatischer, wiederkehrender Lauf für auto-fix-content-report — analog
-- zu run_work_composer_enrichment (20261002000005). Kleine Batch-Größe
-- (limit=5): pro Meldung potenziell ein Seiten-Fetch + ein KI-Aufruf, bei
-- wrong_image zusätzlich die volle Bilder-Recherche-Kaskade.
create or replace function run_auto_fix_content_reports()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/auto-fix-content-report',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_auto_fix_content_reports: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'auto-fix-content-reports',
  '*/30 * * * *',
  $$ select run_auto_fix_content_reports(); $$
);
