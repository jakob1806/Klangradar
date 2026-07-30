-- Der Bild-Backfill umfasst weiterhin mehrere hundert Datensätze und die
-- Edge Function verarbeitet bewusst nur begrenzte Batches. Fünf Minuten
-- verkürzen die Wartezeit deutlich, ohne dass reguläre Läufe mit ihrem
-- 120-Sekunden-Timeout überlappen.
select cron.schedule(
  'image-enrichment',
  '*/5 * * * *',
  $$ select run_image_enrichment(); $$
);
