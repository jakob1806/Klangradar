-- Multi-City-Erweiterung, dritte Runde echter Erstdaten: vier weitere
-- verifizierte Venues (Kampnagel, Pierre Boulez Saal, Volksoper Wien,
-- Wiener Staatsoper) plus deren echte Veranstaltungen aus der
-- probe-source-KI-Extraktion, außerdem zwei echte Hamburgische-Staatsoper-
-- Konzerte, die laut Quelle tatsächlich in der bereits existierenden
-- Elbphilharmonie stattfinden (kein neues Venue nötig).
--
-- Wiener Staatsoper hatte in diesem Durchlauf nur einen Open-Air-Termin
-- im Burggarten (andere Location) — Venue trotzdem angelegt (real,
-- prominent), aber ohne Event, bis ein Durchlauf echte Vorstellungen im
-- Haus selbst findet.
do $$
declare
  v_hamburg uuid := (select id from regions where type = 'city' and slug = 'hamburg');
  v_berlin uuid := (select id from regions where type = 'city' and slug = 'berlin');
  v_vienna uuid := (select id from regions where type = 'city' and slug = 'vienna');

  v_elbphilharmonie uuid;
  v_kampnagel uuid;
  v_boulez uuid;
  v_volksoper uuid;
  v_staatsoper_wien uuid;

  v_source_hamburgische_staatsoper uuid;
  v_source_kampnagel uuid;
  v_source_boulez uuid;
  v_source_volksoper uuid;
  v_source_staatsoper_wien uuid;
begin
  select id into v_elbphilharmonie from venues where slug = 'elbphilharmonie-hamburg';
  select id into v_source_hamburgische_staatsoper from sources where name = 'Hamburgische Staatsoper' and city_id = v_hamburg;
  select id into v_source_kampnagel from sources where name = 'Kampnagel' and city_id = v_hamburg;
  select id into v_source_boulez from sources where name = 'Pierre Boulez Saal' and city_id = v_berlin;
  select id into v_source_volksoper from sources where name = 'Volksoper Wien' and city_id = v_vienna;
  select id into v_source_staatsoper_wien from sources where name = 'Wiener Staatsoper' and city_id = v_vienna;

  -- Kampnagel — Jarrestraße 20, 22303 Hamburg.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'kampnagel-hamburg', 'Kampnagel', 'Jarrestraße 20', '22303', 'Hamburg',
    ST_MakePoint(10.0193846, 53.5837067)::geography, 'https://www.kampnagel.de', v_hamburg
  )
  returning id into v_kampnagel;
  update sources set venue_id = v_kampnagel where id = v_source_kampnagel;

  -- Pierre Boulez Saal — Französische Straße 33 D, 10117 Berlin.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'pierre-boulez-saal', 'Pierre Boulez Saal', 'Französische Straße 33 D', '10117', 'Berlin',
    ST_MakePoint(13.3961422, 52.515313)::geography, 'https://www.boulezsaal.de', v_berlin
  )
  returning id into v_boulez;
  update sources set venue_id = v_boulez where id = v_source_boulez;

  -- Volksoper Wien — Währinger Straße 78, 1090 Wien.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'volksoper-wien', 'Volksoper Wien', 'Währinger Straße 78', '1090', 'Wien',
    ST_MakePoint(16.3501, 48.2245)::geography, 'https://www.volksoper.at', v_vienna
  )
  returning id into v_volksoper;
  update sources set venue_id = v_volksoper where id = v_source_volksoper;

  -- Wiener Staatsoper — Opernring 2, 1010 Wien.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'wiener-staatsoper', 'Wiener Staatsoper', 'Opernring 2', '1010', 'Wien',
    ST_MakePoint(16.36889, 48.20306)::geography, 'https://www.wiener-staatsoper.at', v_vienna
  )
  returning id into v_staatsoper_wien;
  update sources set venue_id = v_staatsoper_wien where id = v_source_staatsoper_wien;

  -- Hamburgische Staatsoper: 2 echte Konzerte in der Elbphilharmonie
  -- (bereits existierendes Venue, kein neues nötig).
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('hamburgische-staatsoper-zeitenlos-2026-08-30', '1. Philharmonisches Konzert: ZEITENLOS', '2026-08-30T09:00:00Z', v_elbphilharmonie, v_source_hamburgische_staatsoper, 'scheduled'),
    ('hamburgische-staatsoper-zeitenlos-2026-08-31', '1. Philharmonisches Konzert: ZEITENLOS', '2026-08-31T18:00:00Z', v_elbphilharmonie, v_source_hamburgische_staatsoper, 'scheduled');

  -- Kampnagel: 5 echte Programmpunkte.
  insert into events (slug, title, start_datetime, venue_id, source_id, status, is_free) values
    ('kampnagel-halberstam-keynote-2026-08-28', 'Jack Halberstam: Keynote – Anarchitecture After Everything', '2026-08-28T16:00:00Z', v_kampnagel, v_source_kampnagel, 'scheduled', null),
    ('kampnagel-tossi-touch-lab-2026-09-04', 'Ursina Tossi #TOUCH_LAB', '2026-09-04T14:00:00Z', v_kampnagel, v_source_kampnagel, 'scheduled', true),
    ('kampnagel-duah-to-build-2026-09-05', 'Sarah Ama Duah: To Build To Bury To Remember', '2026-09-05T17:00:00Z', v_kampnagel, v_source_kampnagel, 'scheduled', true),
    ('kampnagel-theaternacht-hajusom-showing-2026-09-05', 'Theaternacht Hamburg 2026: Hajusom Showing – Hip-Hop-Tanzkurs', '2026-09-05T17:15:00Z', v_kampnagel, v_source_kampnagel, 'scheduled', null),
    ('kampnagel-theaternacht-hajusom-kollektiv-2026-09-05', 'Theaternacht Hamburg 2026: Hajusom / Newsom Kollektiv – Aber vielleicht heute noch nicht', '2026-09-05T17:15:00Z', v_kampnagel, v_source_kampnagel, 'scheduled', null);

  -- Pierre Boulez Saal: 2 echte Konzerte.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('boulez-saal-andras-schiff-2026-12-20', 'Chamber Music Cycle: Sir András Schiff', '2026-12-20T23:00:00Z', v_boulez, v_source_boulez, 'scheduled'),
    ('boulez-saal-arabic-music-days-2026-09-14', 'Arabic Music Days', '2026-09-14T22:00:00Z', v_boulez, v_source_boulez, 'scheduled');

  -- Volksoper Wien: 2 echte Vorstellungen.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('volksoper-fledermaus-singalong-2026-09-04', 'Sing-Along zur Fledermaus (Saisonauftakt)', '2026-09-04T00:00:00Z', v_volksoper, v_source_volksoper, 'scheduled'),
    ('volksoper-ronja-raeubertochter-premiere-2026-09-20', 'Ronja Räubertochter (Premiere)', '2026-09-20T00:00:00Z', v_volksoper, v_source_volksoper, 'scheduled');
end $$;
