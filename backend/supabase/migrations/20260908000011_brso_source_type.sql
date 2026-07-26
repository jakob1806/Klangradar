-- Neuer source_type für den BRSO-Konzertkalender-Connector
-- (parsers/brso.ts) — braucht einen eigenen Typ statt 'scrape', weil der
-- Fetch-Ablauf grundlegend anders ist (zweistufig: Kalenderseite -> Nonce
-- -> JSON-POST an den WordPress-REST-Endpunkt, kein CSS-Scraping möglich,
-- siehe Datei-Kommentar in parsers/brso.ts).
alter type source_type add value 'brso';
