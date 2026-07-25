-- Auf Nutzerwunsch: automatischer Backfill für ALLE bestehenden
-- Datensätze ohne Bild UND automatische Bildsuche für neu angelegte/
-- aktualisierte Einträge — bisher lief enrich-entity-images ausschließlich
-- über den manuellen "Bilder automatisch suchen"-Button im Admin-Dashboard
-- (admin/src/app/(dashboard)/media/enrich-images-button.tsx). Statt jede
-- einzelne Anlege-/Bearbeiten-Aktion in persons/ensembles/venues/events
-- synchron um einen Bildsuche-Aufruf zu erweitern (langsamere UX, ein
-- externer Seitenabruf pro Speichern), läuft die Suche periodisch im
-- Hintergrund — ein neuer Datensatz ohne photo_url/image_urls wird beim
-- nächsten Lauf automatisch erfasst, spätestens nach IMAGE_ENRICHMENT_
-- INTERVAL. Gleiches Muster wie die bestehende tägliche Ingestion (siehe
-- 20260817000005_daily_ingestion_cron.sql), nur häufiger, weil
-- enrich-entity-images pro Lauf nur einen begrenzten Batch bearbeitet
-- (DEFAULT_LIMIT=8 pro Entitätsart, HEALTH_CHECK_LIMIT=15) und sich der
-- Backfill über bestehende ~250+ Datensätze sonst über Tage hinzöge.
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
    body := '{"limit": 15}'::jsonb,
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

-- Alle 15 Minuten — bewusst deutlich häufiger als die tägliche Ingestion,
-- damit sowohl der bestehende Rückstau (Backfill) als auch neu angelegte
-- Einträge innerhalb kurzer Zeit an die Reihe kommen, ohne jede
-- Admin-Aktion selbst synchron zu verlangsamen.
select cron.schedule(
  'image-enrichment',
  '*/15 * * * *',
  $$ select run_image_enrichment(); $$
);
