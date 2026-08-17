-- Die Bildrecherche wurde um robuste Wikipedia-Retries, internationale
-- Suchanfragen und namensbezogene Bilder auf Künstler-/Agenturseiten
-- erweitert. Frühere endgültige Fehlschläge einmalig wieder in die Queue
-- stellen, damit sie von der besseren Logik profitieren.
update public.persons
set
  image_search_checked_at = null,
  last_image_search_note = 'Erneute Bildrecherche mit erweiterter Suche eingeplant.'
where photo_url is null
  and (
    last_image_search_note = 'Kein eindeutiger Wikipedia-Artikel mit Porträtbild gefunden.'
    or last_image_search_note = 'Kein eindeutiges Porträt in Wikipedia, Wikidata oder der erweiterten Websuche gefunden.'
  );
