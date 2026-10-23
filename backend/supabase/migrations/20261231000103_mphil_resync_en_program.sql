-- Erstellt von Claude Code (23.10.2026): mphil.de-Konzerte erneut abgleichen.
-- Der Programm-Parser griff auf englischen Seiten nicht, und zusammengeführte
-- Termine mit Aggregator-URL wurden übersprungen (mphil-URL nur in external_id).
update events
set mphil_detail_synced_at = null, mphil_detail_sync_error = null
where start_datetime >= now()
  and (website_url ilike '%mphil.de/%' or external_id ilike '%mphil.de/%');
