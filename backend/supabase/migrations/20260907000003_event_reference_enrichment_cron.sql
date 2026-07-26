-- Automatischer, wiederkehrender Lauf für enrich-event-references — bisher
-- nur manuell über einen Admin-Button/Testaufruf angestoßen. Auf
-- Nutzerwunsch ("wiederkehrend aktualisieren" + "vollständigen Backfill
-- für alle bestehenden Einträge") jetzt periodisch, mit kleiner Batch-Größe
-- (limit=5): seit die Funktion zusätzlich den Volltext der offiziellen
-- Event-Seite abruft (siehe _shared/pageText.ts), sprengte ein größerer
-- Batch (10) das Speicherlimit der Edge Function (WORKER_RESOURCE_LIMIT,
-- live beobachtet) — 5 lief stabil durch. Gleiches Muster wie
-- image-enrichment (20260905000002_image_enrichment_cron.sql).
create or replace function run_event_reference_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-event-references',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_event_reference_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'event-reference-enrichment',
  '*/10 * * * *',
  $$ select run_event_reference_enrichment(); $$
);
