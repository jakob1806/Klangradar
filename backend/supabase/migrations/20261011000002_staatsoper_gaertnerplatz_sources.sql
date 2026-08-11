-- Offizielle Spielpläne der Bayerischen Staatsoper und des Staatstheaters
-- am Gärtnerplatz. Beide brauchen einen eigenen Fetch-Ablauf: Staatsoper
-- blockiert direkte Serverabrufe (Reader-Fallback), Gärtnerplatz liefert
-- seine Saison ausschließlich als paginierte POST-AJAX-Antworten.

insert into sources (id, name, type, url, venue_id, organizer_id, crawl_frequency_minutes, legal_basis, status, config)
select
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'Bayerische Staatsoper – offizieller Spielplan', 'staatsoper'::source_type,
  'https://www.staatsoper.de/spielplan', null,
  (select id from organizers where slug = 'bayerische-staatsoper' limit 1), 720,
  'Öffentlich sichtbarer offizieller Spielplan. robots.txt geprüft am 2026-08-11; '
    || 'Spielplanpfad nicht ausgeschlossen. Direkter Serverzugriff wird technisch blockiert, '
    || 'daher textbasierter Reader-Abruf derselben offiziellen URLs.',
  'active', jsonb_build_object('monthsAhead', 12, 'autoPublish', true)
where not exists (
  select 1 from sources where type = 'staatsoper'::source_type
    or url = 'https://www.staatsoper.de/spielplan'
);

insert into sources (id, name, type, url, venue_id, crawl_frequency_minutes, legal_basis, status, config)
select
  'c1100000-0000-4000-8000-000000000002'::uuid,
  'Staatstheater am Gärtnerplatz – offizieller Spielplan', 'gaertnerplatz'::source_type,
  'https://www.gaertnerplatztheater.de/de/spielplan/index.html',
  (select id from venues where slug = 'staatstheater-am-gaertnerplatz' limit 1), 720,
  'Öffentlich sichtbarer offizieller Spielplan. robots.txt geprüft am 2026-08-11; '
    || 'der Spielplanpfad ist nicht ausgeschlossen.',
  'active',
  jsonb_build_object(
    'maxPages', 80, 'autoPublish', true,
    'itemSelector', '.vorstellung.performance[class*="vorstellung-"]',
    'itemExcludeClassContains', jsonb_build_array('ort-102'),
    'titleSelector', '.fs-3 a', 'urlSelector', '.fs-3 a', 'urlAttribute', 'href',
    'dateSelector', '.col-xl-3 .fs-3', 'timeSelector', '.col-xl-3 .fw-bold',
    'descriptionSelector', '.children-without-margin',
    'baseUrl', 'https://www.gaertnerplatztheater.de/de/', 'fetchTimeoutMs', 30000
  )
where not exists (
  select 1 from sources where type = 'gaertnerplatz'::source_type
    or url = 'https://www.gaertnerplatztheater.de/de/spielplan/index.html'
);

-- Vorhandene unvollständige Termine erneut in die Programm-/Besetzungsqueue.
update events
set program_extraction_status = 'pending', program_retry_after = null, program_last_error = null
where venue_id in (
  select id from venues where slug in ('staatstheater-am-gaertnerplatz', 'nationaltheater-muenchen')
)
and status = 'scheduled';
