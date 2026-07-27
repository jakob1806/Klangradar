-- Moderate Erhöhung des Batch-Limits (15 -> 20 pro Entitätsart/Events) auf
-- Nutzerwunsch, im Zug weiterer kostenloser Bildquellen (Wikidata,
-- Wikipedia für alle Entity-Kinds, Website-Discovery, Presse-/Über-uns-
-- Unterseiten) — mehr Quellen pro Entität bedeuten mehr HTTP-Aufrufe pro
-- Batch-Eintrag, ein etwas größeres Limit hält den Durchsatz bei
-- kontinuierlich neu hinzukommenden Datensätzen ähnlich wie bisher, ohne
-- das Cron-Intervall (alle 15 Minuten) selbst anzufassen. Gleiche
-- Funktion, nur der Body des net.http_post-Aufrufs ändert sich.
create or replace function run_image_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-entity-images',
    body := '{"limit": 20}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_image_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;
