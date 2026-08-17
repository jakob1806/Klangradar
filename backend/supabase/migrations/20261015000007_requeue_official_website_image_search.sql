-- Der priorisierte Personen-Cron lief mit fastFallback=true. Bis zum Fix in
-- enrich-entity-images übersprang dieser Modus auch eine bereits bekannte
-- website_url. Alle dadurch abgeschlossenen bildlosen Personen mit
-- offizieller Website einmalig neu und bevorzugt prüfen.
update public.persons
set
  image_search_checked_at = null,
  last_image_search_note = 'Erneute Bildrecherche auf der offiziellen Website eingeplant.'
where photo_url is null
  and website_url is not null
  and btrim(website_url) <> '';
