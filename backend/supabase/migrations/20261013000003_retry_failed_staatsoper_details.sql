-- Nach dem vollständigen Hauptlauf nur tatsächliche Transport-/Readerfehler
-- erneut einreihen. Erfolgreiche Sonderveranstaltungen ohne Programmliste
-- oder Bild bleiben abgeschlossen und werden nicht endlos wiederholt.
update events
set staatsoper_detail_synced_at = null
where website_url ilike '%staatsoper.de/%'
  and start_datetime >= now()
  and staatsoper_detail_sync_error is not null;
