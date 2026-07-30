-- Die Bildrecherche wird vorerst redaktionell/manuell ausgeführt.
-- Nur der Job `image-enrichment` wird entfernt; alle anderen Cronjobs
-- bleiben unverändert. run_image_enrichment() bleibt für manuelle Aufrufe
-- und eine spätere Reaktivierung erhalten.
select cron.unschedule('image-enrichment');
