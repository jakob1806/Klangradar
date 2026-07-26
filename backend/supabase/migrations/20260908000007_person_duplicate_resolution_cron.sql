-- Wiederkehrender Lauf für resolve-person-duplicates — auf Nutzerwunsch
-- ("Künstler-Duplikate wie J.S. Bach/Johann Sebastian Bach automatisch
-- erkennen und zusammenführen") vollautomatisch bei hoher KI-Konfidenz,
-- analog zu den übrigen Enrichment-Cron-Jobs. Seltener als die
-- Profil-Anreicherungen (stündlich statt alle 10 Minuten) — neue
-- Namensvarianten entstehen nur, wenn neue Personen angelegt werden, kein
-- Bedarf für eine engere Taktung.
create or replace function run_person_duplicate_resolution()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/resolve-person-duplicates',
    body := '{"limit": 15}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_person_duplicate_resolution: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'person-duplicate-resolution',
  '0 * * * *',
  $$ select run_person_duplicate_resolution(); $$
);
