-- Erstellt mit Claude Code.
--
-- Quellen-Audit 2026-10-12, Teil 2: Quellen im Status 'under_review', bei
-- denen die JSON-Konfiguration fehlte (nur parser=auto, keine Selektoren)
-- oder die URL inzwischen 404 liefert. Alle Configs lokal mit dem
-- Scrape-Parser dieses PRs gegen die Live-Seiten geprüft.

-- Pierre Boulez Saal: Kalender lädt per JavaScript nach (im rohen HTML nur 2 von ~50 Terminen) -> renderJs. Selektoren an den serverseitig gerenderten Einträgen geprüft.
update sources
set type = 'scrape',
    url = 'https://www.boulezsaal.de/de/events',
    config = $cfg${"renderJs": true, "renderJsWaitMs": 6000, "itemSelector": "a.event-list__item", "titleSelector": ".event-list__title", "descriptionSelector": ".event-list__subtitle", "urlSelector": ":scope", "dateSelector": ".event-list__date", "timeSelector": ".event-list__time", "imageSelector": ".event-list__thumb img", "baseUrl": "https://www.boulezsaal.de"}$cfg$::jsonb,
    status = 'active',
    last_run_at = null,
    consecutive_failures = 0
where id = 'eebb6302-30da-48a8-8ff5-92eaf77f1dad';

-- Oper Frankfurt: Monatsseiten (?datum=JJJJ-MM), am Termin nur Wochentag+Tag: Monat per pageMonthSelector, Folgemonate per nextPageSelector (9 Monate). Geprüft: Okt 24, Jan 35 Termine.
update sources
set type = 'scrape',
    url = 'https://oper-frankfurt.de/de/spielplan/',
    config = $cfg${"itemSelector": ".repertoire-element", "titleSelector": "h3", "descriptionSelector": "h4", "urlSelector": "a.season-hover-text", "dateSelector": ".col-date span", "timeSelector": ".meta", "pageMonthSelector": "ul.months li.active a", "pageMonthAttribute": "href", "nextPageSelector": "ul.months li.active + li a, ul.months:has(li.active) + ul.months li:first-child a", "maxPages": 9, "baseUrl": "https://oper-frankfurt.de/de/spielplan/"}$cfg$::jsonb,
    status = 'active',
    last_run_at = null,
    consecutive_failures = 0
where id = '6ce7f477-2e0b-4a6f-8b15-8ab633a2c067';

-- Opern- und Museumsorchester: Saisonliste mit vollem Datum in .meta. Geprüft: 18 Termine, Spielstätte aus .meta.
update sources
set type = 'scrape',
    url = 'https://oper-frankfurt.de/de/konzerte/',
    config = $cfg${"itemSelector": ".repertoire-element", "titleSelector": "h3", "urlSelector": "a.season-hover-text", "dateSelector": ".meta", "venueSelector": ".meta", "venueStripPattern": "^.*?Uhr,\\s*", "baseUrl": "https://oper-frankfurt.de"}$cfg$::jsonb,
    status = 'active',
    last_run_at = null,
    consecutive_failures = 0
where id = 'b1399489-d79c-40e7-9069-1914a41559cf';

-- hr-Sinfonieorchester: Bestehende Config + Folgemonate per monthUrlTemplate, Ortspräfix 'Frankfurt am Main' entfernt.
update sources
set type = 'scrape',
    url = 'https://www.hr-sinfonieorchester.de/konzerte/konzertkalender/index.html',
    config = $cfg${"baseUrl": "https://www.hr-sinfonieorchester.de", "dateSelector": ".c-eventTeaser__eventDate", "deferImageEnrichment": true, "descriptionSelector": ".c-eventTeaser__eventDetails", "itemSelector": ".c-eventTeaser", "targetRegionSlug": "frankfurt", "timeSelector": ".c-eventTeaser__startTime", "titleFullText": true, "titleSelector": ".c-eventTeaser__headline", "urlSelector": "a.c-teaser__headlineLink", "venueAllowlist": ["Frankfurt am Main", "Frankfurt"], "venueNameMap": {"Weseler Werft": "Weseler Werft"}, "venueSelector": ".c-eventTeaser__venue .c-eventInstant__content", "writeBatchSize": 100, "venueStripPattern": "^Frankfurt am Main\\s+", "monthUrlTemplate": "https://www.hr-sinfonieorchester.de/konzerte/veranstaltungen-110~_month-{YYYY-MM}.html", "monthsAhead": 6}$cfg$::jsonb,
    status = 'active',
    last_run_at = null,
    consecutive_failures = 0
where id = '57d46a72-c2c3-4d9a-8f26-40dfa4fd6baa';

-- Ensemble Modern: Tourneeensemble: feste venue_id entfernt, nur Termine mit Stadt Frankfurt, Datum aus der Detail-URL.
update sources
set type = 'scrape',
    url = 'https://www.ensemble-modern.com/de/kalender',
    config = $cfg${"itemSelector": "section.w__concert", "titleSelector": ".w__tile--title", "titleFullText": true, "urlSelector": ".w__concert--details a[href]", "dateSelector": ".w__concert--details a[href]", "timeSelector": ".w__concert--time", "venueSelector": ".w__concert--location", "tagsSelector": ".w__concert--city", "includeIfTagContains": ["Frankfurt"], "imageSelector": "img.w__tile--image", "descriptionSelector": ".w__concert--works-cell", "baseUrl": "https://www.ensemble-modern.com", "dateAttribute": "href", "venueStripPattern": ",.*$"}$cfg$::jsonb,
    venue_id = null,
    status = 'active',
    last_run_at = null,
    consecutive_failures = 0
where id = '2b2a7eb4-7c6a-46f1-b020-692f1fb4d2c6';

-- HfMDK Frankfurt: React-Kalender -> renderJs; Selektoren an den serverseitig gerenderten Startseiten-Einträgen geprüft (8/8).
update sources
set type = 'scrape',
    url = 'https://www.hfmdk-frankfurt.de/thema/kalender',
    config = $cfg${"renderJs": true, "renderJsWaitMs": 8000, "itemSelector": "article.teaser-veranstaltung", "titleSelector": "h3", "titleFullText": true, "dateSelector": ".mobile-header time", "venueSelector": "a.location span", "venueStripPattern": ",.*$", "baseUrl": "https://www.hfmdk-frankfurt.de"}$cfg$::jsonb,
    status = 'active',
    last_run_at = null,
    consecutive_failures = 0
where id = '254acef7-e787-442e-971f-ab54c085d58d';

-- Pausieren: Domain nicht erreichbar (kein DNS/keine Antwort am 2026-10-12)
-- bzw. inhaltlich schon durch eine andere aktive Quelle abgedeckt.
update sources
set status = 'paused'
where id in (
  '5b01bdb1-6ecc-4d09-9091-945fdd0d4874', -- Casals Forum Kronberg: kronbergacademy.org nicht erreichbar; Casals-Forum-Termine kommen über "Kronberg Academy – Veranstaltungen (Scrape)"
  '1f894b28-d8db-4d3a-8511-1895eac830a7', -- hr-Sendesaal: hr-sendesaal.de nicht erreichbar; Termine kommen über hr-Sinfonieorchester
  'f5e30fe3-a591-40af-bebf-0d5769020880', -- Frankfurter Museums-Gesellschaft: dieselben Sinfoniekonzerte wie "Opern- und Museumsorchester" (dort mit Uhrzeit)
  '24561916-732a-45f7-a6d8-f5dec5b2e1e8', -- Mozart-Gesellschaft Frankfurt: Domain nicht erreichbar
  'de43bfbc-dada-47ea-8bdb-4271e45aa577'  -- St. Katharinenkirche Frankfurt: Domain nicht erreichbar
);

-- Bleiben bewusst 'under_review' (nicht Teil dieser Reparatur):
--   Universität der Künste Berlin: Kalender-API (/api/v1/kalender) liefert
--     keine Uhrzeiten und mischt Konzerte mit Workshops/Ausstellungen.
--   Kampnagel, Künstlerhaus Mousonturm: Tanz/Theater, kaum Klassik.
