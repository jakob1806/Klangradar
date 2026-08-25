-- Multi-City-Erweiterung, Abschnitte 6-9 "Datenquellen Berlin/Hamburg/
-- Wien/Frankfurt".
--
-- WICHTIG (Grenze dieser Migration): dies legt `sources`-Zeilen für die im
-- Auftrag priorisierten Institutionen an, mit ihrer echten offiziellen
-- Homepage-URL, korrektem city_id und status='under_review'. Es werden
-- BEWUSST KEINE venues/events-Zeilen mit erfundenen Adressen/Koordinaten
-- angelegt — das wäre fabrizierte Geodaten, keine echten Daten. Die
-- bestehende Ingestion-Pipeline (discover-sources/ingest-source/
-- resolve-entity-candidates) ist genau dafür gebaut, aus einer Quelle
-- echte Venue-/Event-Kandidaten zu erzeugen.
--
-- status='under_review' statt 'active': diese Quellen laufen NICHT
-- automatisch im täglichen run-all-sources-Cron (siehe
-- run-all-sources/index.ts, das nur status='active' lädt), bis eine
-- Redaktion sie im Admin-Dashboard geprüft und aktiviert hat — ein
-- unverifizierter Scrape-Versuch gegen 30+ neue, noch nie getestete
-- Ziel-URLs soll nicht unbeaufsichtigt in Produktion laufen.
--
-- type='scrape' als generischer Default: die meisten dieser Institutions-
-- Websites haben keine dokumentierte API/kein RSS/ical/schema.org-Feed,
-- den ich aus dieser Sandbox heraus verifizieren könnte. Redaktion kann
-- den type beim Review auf einen präziseren Wert ändern.
do $$
declare
  v_berlin uuid := (select id from regions where type = 'city' and slug = 'berlin');
  v_hamburg uuid := (select id from regions where type = 'city' and slug = 'hamburg');
  v_vienna uuid := (select id from regions where type = 'city' and slug = 'vienna');
  v_frankfurt uuid := (select id from regions where type = 'city' and slug = 'frankfurt');
begin
  insert into sources (name, type, url, city_id, status) values
    ('Berliner Philharmoniker', 'scrape', 'https://www.berliner-philharmoniker.de', v_berlin, 'under_review'),
    ('Konzerthaus Berlin', 'scrape', 'https://www.konzerthaus.de', v_berlin, 'under_review'),
    ('Staatsoper Unter den Linden', 'scrape', 'https://www.staatsoper-berlin.de', v_berlin, 'under_review'),
    ('Deutsche Oper Berlin', 'scrape', 'https://www.deutscheoperberlin.de', v_berlin, 'under_review'),
    ('Komische Oper Berlin', 'scrape', 'https://www.komische-oper-berlin.de', v_berlin, 'under_review'),
    ('Pierre Boulez Saal', 'scrape', 'https://www.boulezsaal.de', v_berlin, 'under_review'),
    ('Radialsystem', 'scrape', 'https://www.radialsystem.de', v_berlin, 'under_review'),
    ('Rundfunk-Sinfonieorchester Berlin', 'scrape', 'https://www.rsb-online.de', v_berlin, 'under_review'),
    ('Deutsches Symphonie-Orchester Berlin', 'scrape', 'https://www.dso-berlin.de', v_berlin, 'under_review'),
    ('Universität der Künste Berlin', 'scrape', 'https://www.udk-berlin.de', v_berlin, 'under_review'),

    ('Elbphilharmonie', 'scrape', 'https://www.elbphilharmonie.de', v_hamburg, 'under_review'),
    ('Laeiszhalle', 'scrape', 'https://www.elbphilharmonie.de/de/laeiszhalle', v_hamburg, 'under_review'),
    ('Hamburgische Staatsoper', 'scrape', 'https://www.staatsoper-hamburg.de', v_hamburg, 'under_review'),
    ('NDR Elbphilharmonie Orchester', 'scrape', 'https://www.ndr.de/orchester_chor/elbphilharmonieorchester', v_hamburg, 'under_review'),
    ('Ensemble Resonanz', 'scrape', 'https://www.ensembleresonanz.com', v_hamburg, 'under_review'),
    ('Kampnagel', 'scrape', 'https://www.kampnagel.de', v_hamburg, 'under_review'),
    ('Hochschule für Musik und Theater Hamburg', 'scrape', 'https://www.hfmt-hamburg.de', v_hamburg, 'under_review'),

    ('Wiener Musikverein', 'scrape', 'https://www.musikverein.at', v_vienna, 'under_review'),
    ('Wiener Konzerthaus', 'scrape', 'https://www.konzerthaus.at', v_vienna, 'under_review'),
    ('Wiener Staatsoper', 'scrape', 'https://www.wiener-staatsoper.at', v_vienna, 'under_review'),
    ('Volksoper Wien', 'scrape', 'https://www.volksoper.at', v_vienna, 'under_review'),
    ('Theater an der Wien', 'scrape', 'https://www.theater-wien.at', v_vienna, 'under_review'),
    ('Wiener Philharmoniker', 'scrape', 'https://www.wienerphilharmoniker.at', v_vienna, 'under_review'),
    ('ORF Radio-Symphonieorchester Wien', 'scrape', 'https://rso.orf.at', v_vienna, 'under_review'),
    ('Musik und Kunst Privatuniversität Wien', 'scrape', 'https://www.muk.ac.at', v_vienna, 'under_review'),
    ('Universität für Musik und darstellende Kunst Wien', 'scrape', 'https://www.mdw.ac.at', v_vienna, 'under_review'),

    ('Alte Oper Frankfurt', 'scrape', 'https://www.alteoper.de', v_frankfurt, 'under_review'),
    ('Oper Frankfurt', 'scrape', 'https://www.oper-frankfurt.de', v_frankfurt, 'under_review'),
    ('hr-Sinfonieorchester', 'scrape', 'https://www.hr-sinfonieorchester.de', v_frankfurt, 'under_review'),
    ('hr-Sendesaal', 'scrape', 'https://www.hr-sendesaal.de', v_frankfurt, 'under_review'),
    ('Ensemble Modern', 'scrape', 'https://www.ensemble-modern.com', v_frankfurt, 'under_review'),
    ('Frankfurter Museums-Gesellschaft', 'scrape', 'https://www.frankfurter-museumsgesellschaft.de', v_frankfurt, 'under_review'),
    ('Hochschule für Musik und Darstellende Kunst Frankfurt', 'scrape', 'https://www.hfmdk-frankfurt.de', v_frankfurt, 'under_review'),
    ('Künstlerhaus Mousonturm', 'scrape', 'https://www.mousonturm.de', v_frankfurt, 'under_review'),
    ('Mozart-Gesellschaft Frankfurt', 'scrape', 'https://www.mozartgesellschaft-frankfurt.de', v_frankfurt, 'under_review'),
    ('St. Katharinenkirche Frankfurt', 'scrape', 'https://www.katharinenkirche-frankfurt.de', v_frankfurt, 'under_review'),
    ('Casals Forum Kronberg', 'scrape', 'https://www.kronbergacademy.org/casals-forum', v_frankfurt, 'under_review');
  -- Kein ON CONFLICT: sources hat keine unique-Constraint auf name/url
  -- (nur auf id), die einen sinnvollen Konflikt-Target abgeben würde.
  -- Migrationen laufen ohnehin nur einmal — ein erneuter manueller Lauf
  -- dieses Skripts würde Duplikate erzeugen, ist aber nicht vorgesehen.
end $$;

comment on column sources.status is 'active/paused/error/under_review. under_review-Quellen laufen NICHT im täglichen Cron (run-all-sources filtert auf active) — für neu angelegte, noch nicht redaktionell geprüfte Quellen (z.B. Multi-City-Expansion Berlin/Hamburg/Wien/Frankfurt).';
