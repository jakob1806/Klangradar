-- Abschnitt 3/F der Gesamtüberarbeitung: Nutzer hat der Reaktivierung
-- explizit zugestimmt ("Ja, wieder aktivieren"). Die Bildrecherche lief seit
-- 20260910000006_disable_image_enrichment_cron.sql nur noch redaktionell/
-- manuell — die Pipeline ist seither um eine Seitenverhältnis-Prüfung
-- ergänzt (imagePipeline.ts) und die Review-Queue (needs_review, /media)
-- fängt unsichere Treffer weiterhin ab, bevor sie öffentlich sichtbar
-- werden. run_image_enrichment() selbst wurde nie entfernt, nur der
-- Zeitplan — gleiche Taktung wie vor der Deaktivierung.
select cron.schedule(
  'image-enrichment',
  '*/5 * * * *',
  $$ select run_image_enrichment(); $$
);
