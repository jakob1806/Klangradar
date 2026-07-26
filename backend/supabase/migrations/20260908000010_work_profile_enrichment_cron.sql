-- Wiederkehrender Lauf für enrich-work-profile — analog zu den übrigen
-- Profil-Enrichment-Cron-Jobs (Venues/Personen/Ensembles).
create or replace function run_work_profile_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-work-profile',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_work_profile_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'work-profile-enrichment',
  '*/10 * * * *',
  $$ select run_work_profile_enrichment(); $$
);
