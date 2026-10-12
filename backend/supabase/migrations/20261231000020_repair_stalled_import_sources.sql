-- Erstellt mit Claude Code.
--
-- Quellen-Audit 2026-10-12: Reparatur der Importquellen, die seit Wochen
-- nicht mehr liefen (siehe auch run-all-sources-Fix im selben PR).
--
-- 1. 17 aktive Quellen standen auf type = 'rendered_scrape'. Diesen Typ
--    kennt ingest-source in main nicht (SUPPORTED_TYPES), run-all-sources
--    hat sie deshalb seit 2026-08-28 still übersprungen. Der in main
--    vorgesehene Weg ist type = 'scrape' (+ config.renderJs = true nur, wo
--    der Kalender wirklich per JavaScript nachgeladen wird). Alle Configs
--    wurden am 2026-10-12 lokal mit dem Parser dieses PRs gegen die
--    Live-Seiten geprüft.
-- 2. Doppelte Quellen für dieselbe Website: jeweils die ergiebigere bzw.
--    vollständigere Config bleibt aktiv, die andere wird pausiert (keine
--    Löschung, verknüpfte Events bleiben unverändert).
-- 3. mdw: feste daterange-URL (ab 27.08.2026) durch die rollierende
--    Standardliste ersetzt — die feste Spanne lieferte zunehmend
--    vergangene Termine ohne Jahreszahl.

-- 1a. Kalender, die schon im rohen HTML vollständig sind (geprüfte Anzahl
--     kommender Termine in Klammern).
update sources
set type = 'scrape',
    config = config - 'parser' - 'browserlessTokenEnvVar' - 'renderTimeoutMs' - 'httpCache',
    last_run_at = null,
    consecutive_failures = 0
where id in (
  'd3610eb4-358c-4886-91c1-fffeaeb7973f', -- Staatsoper Unter den Linden (5)
  '8b04ea3f-73a8-4b62-b811-44251950fed7', -- ORF Radio-Symphonieorchester Wien (6)
  '0a8ce0d2-bd07-499a-abe0-290a58294db4', -- Wiener Musikverein (100)
  '2e28646f-6127-4569-8a87-969c3e9a643c', -- Symphoniker Hamburg (47)
  '565884e2-94d8-4d4e-923a-5e08f520265d', -- Konzerthaus Berlin (32)
  '77646c08-1f55-4356-a2ec-42b95e6d550b', -- NDR Elbphilharmonie Orchester (7)
  'ab02c3a3-cc80-4a8e-90b9-7a532e070cdb', -- Wiener Symphoniker (20)
  '6aa1bef6-0b1a-4099-acd9-fbcc1b8e161c', -- Ensemble Resonanz (55)
  '7715049d-7052-4c3f-b824-8c59e502ba98', -- Rundfunk-Sinfonieorchester Berlin (14)
  '8f3bc5a8-f188-4667-8bae-598b9e238b9f', -- Hamburgische Staatsoper (28)
  'e0518d57-0435-4b9c-9dcb-35c44f569c3b', -- Hochschule für Musik und Theater Hamburg (~110)
  'eb7041fa-a7b9-403b-96b5-b1401e219fc4'  -- Theater an der Wien (126)
)
and type = 'rendered_scrape';

-- 1b. Kalender, die im rohen HTML leer sind bzw. kein Datum tragen und daher
--     über Browserless (Secret BROWSERLESS_API_TOKEN ist gesetzt) gerendert
--     werden müssen.
update sources
set type = 'scrape',
    config = (config - 'parser' - 'browserlessTokenEnvVar' - 'renderTimeoutMs' - 'httpCache')
      || '{"renderJs": true, "renderJsWaitMs": 6000}'::jsonb,
    last_run_at = null,
    consecutive_failures = 0
where id in (
  '801a4946-2bf0-446e-954a-dbac6be60d06', -- Deutsche Oper Berlin
  'b69f5380-da56-48a0-8a05-d6a341088529'  -- Wiener Staatsoper
)
and type = 'rendered_scrape';

-- 2. Duplikate pausieren.
update sources
set status = 'paused'
where id in (
  '2de3e3ba-a0e2-4f40-86f2-bffca1e281e1', -- Berliner Philharmoniker (rendered_scrape) -> "… Konzertkalender (Rendered Scrape)" bleibt
  '98083bad-8aa9-42fa-9485-c1bc9dae9af5', -- Volksoper Wien (rendered_scrape) -> "… Spielplan (Scrape)" bleibt
  '8ec8793e-901b-480e-aba3-74b40bb590f6', -- Komische Oper Berlin (rendered_scrape) -> "… Spielplan (Scrape)" bleibt
  '3959ada2-5a57-4263-aa04-42f70cb3f9ff', -- Wiener Philharmoniker (rendered_scrape) -> "… Konzerte (Rendered Scrape)" bleibt
  '7ce2e1a2-9159-47d5-bed5-a65c79fc85c4', -- RSB – Konzerte (Scrape), ohne Spielstätten -> RSB (1a) bleibt
  '117d89e6-2826-480f-8f92-e80e3618bc30', -- Hamburgische Staatsoper – Spielplan (Scrape) -> Hamburgische Staatsoper (1a) bleibt
  '33e34a8f-9d63-428e-a325-2ebbab1f71d4', -- Wiener Konzerthaus, ohne Spielstätten -> "… Kalender (Scrape)" bleibt
  'bfcf6cea-cb90-4271-842e-c137c9d6a31c'  -- DSO (Rendered Scrape), Markup geändert -> DSO-API-Quelle bleibt
);

-- Wiener Philharmoniker: Kalender ist im rohen HTML vollständig (93
-- kommende Termine), Browserless-Rendering unnötig.
update sources
set config = config - 'renderJs' - 'renderJsWaitMs',
    last_run_at = null,
    consecutive_failures = 0
where id = 'daac8f27-6396-43c5-8a7c-81701c84863a';

-- 3. mdw: rollierende Standardliste statt fester Datumsspanne.
update sources
set url = 'https://www.mdw.ac.at/veranstaltung/',
    config = config - 'httpCache',
    last_run_at = null,
    consecutive_failures = 0
where id = 'fd148ef6-ad4c-4fba-908f-6ebbf9075be8';

-- Quellen, deren Läufe durch die run-all-sources-Endlosschleife bzw. das
-- München-only-Venue-Matching gescheitert sind: Fehlerzähler zurücksetzen,
-- damit die Zuverlässigkeits-Gewichtung (write.ts) sie nicht weiter abwertet.
update sources
set consecutive_failures = 0
where status = 'active'
  and consecutive_failures > 0
  and type in ('scrape', 'api', 'schema_org', 'staatsoper', 'brso', 'gaertnerplatz');
