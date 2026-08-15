-- Nach Einbindung des entitätsspezifischen Tiefencrawlers sollen alle
-- bildlosen Profile mit offizieller Website erneut durch Presse-, Portrait-,
-- Galerie-, Bio- und Team-Unterseiten laufen. Der bisherige Event-Cover-
-- Parser übersah u.a. Squarespace data-image/data-src-Porträts.
update public.persons
set
  image_search_checked_at = null,
  last_image_search_note = 'Vertiefte Bildrecherche auf Presse- und Portraitseiten eingeplant.'
where photo_url is null
  and website_url is not null
  and btrim(website_url) <> '';

update public.ensembles
set
  image_search_checked_at = null,
  last_image_search_note = 'Vertiefte Bildrecherche auf Presse- und Ensemble-Seiten eingeplant.'
where photo_url is null
  and website_url is not null
  and btrim(website_url) <> '';
