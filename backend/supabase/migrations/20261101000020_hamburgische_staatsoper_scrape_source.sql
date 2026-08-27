-- Vierte echte Event-Quelle der Stadt-Erweiterung, erste für Hamburg (nach
-- dem Fehlschlag bei Elbphilharmonie/Laeiszhalle, siehe unten): die
-- Hamburgische Staatsoper (inkl. Philharmonisches Staatsorchester Hamburg)
-- listet ihren Spielplan serverseitig gerendert (.event-entry). Config
-- lokal gegen echtes HTML verifiziert (Deno, 25/25 Termine korrekt
-- geparst mit Titel/Datum/Uhrzeit/Ort).
--
-- staatsoper-hamburg.de (Quelle laut Nutzer-Excel) leitet per 301/302 auf
-- die neue Domain die-hamburgische-staatsoper.de weiter -- direkt die
-- neue, tatsächlich bediente URL als Quelle eingetragen, nicht die
-- veraltete, damit der Cron nicht dauerhaft von einem Redirect abhängt.
-- robots.txt der neuen Domain ist "Allow: /" ohne jede Einschränkung.
--
-- Elbphilharmonie & Laeiszhalle (separater Eintrag derselben Excel-Liste,
-- ebenfalls Priorität A) bleiben bewusst AUSSER Betracht: deren robots.txt
-- enthält "User-agent: ClaudeBot / Disallow: /", ein expliziter Ausschluss
-- für Claude/Anthropic-Crawler, der unabhängig vom technisch gesendeten
-- User-Agent-String respektiert wird (siehe docs/12-city-expansion-import.md).
--
-- Ein additiver Fix in parsers/scrape.ts war nötig (siehe dortiger
-- Kommentar/Diff im selben PR): bares "HH:MM" ohne "Uhr"/Gedankenstrich-
-- Suffix als Fallback auch im Punkt-getrennten "TT.MM.JJ"-Datumsblock
-- (bisher nur im Block für ausgeschriebene Monatsnamen vorhanden). Rein
-- additiv, bestehende Testsuite unter ingest-source/ bleibt unverändert
-- grün (5/5).
--
-- Keine venue_id: Termine finden an mehreren Orten statt (Staatsoper
-- Großes Haus, Elbphilharmonie Großer Saal als Gastspielort, Werkstätten
-- Rothenburgsort, auswärtige Gastspiele, ...), venueName löst per
-- Fuzzy-Match auf. Keine Detail-URL pro Termin im HTML (Aufklapp-Panel
-- statt eigener Seite) -- url bleibt null, das ist laut RawEvent-Typ
-- vorgesehen.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Hamburgische Staatsoper – Spielplan (Scrape)',
  'scrape',
  'https://www.die-hamburgische-staatsoper.de/de',
  null,
  (select id from regions where type = 'city' and slug = 'hamburg'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || '"Allow: /" ohne Einschränkung, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": ".event-entry",
    "titleSelector": ".event__title span",
    "dateSelector": ".event__date",
    "timeSelector": "span.event__datetime",
    "venueSelector": ".event__location span",
    "titleExcludeIfContains": ["Führung"],
    "baseUrl": "https://www.die-hamburgische-staatsoper.de"
  }'::jsonb
);
