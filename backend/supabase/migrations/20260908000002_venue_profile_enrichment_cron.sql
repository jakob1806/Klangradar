-- Automatischer, wiederkehrender Lauf für enrich-venue-details — analog zu
-- run_event_reference_enrichment (20260907000003), damit sich Venue-Profile
-- ohne manuelles Zutun weiter füllen ("wiederkehrend aktualisieren" +
-- "vollständigen Backfill für alle bestehenden Einträge"). Kleine
-- Batch-Größe (limit=5) aus dem gleichen Grund wie bei
-- enrich-event-references: die Funktion ruft pro Venue den Volltext der
-- offiziellen Website ab, ein größerer Batch riskiert WORKER_RESOURCE_LIMIT.
create or replace function run_venue_profile_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-venue-details',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_venue_profile_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'venue-profile-enrichment',
  '*/10 * * * *',
  $$ select run_venue_profile_enrichment(); $$
);
