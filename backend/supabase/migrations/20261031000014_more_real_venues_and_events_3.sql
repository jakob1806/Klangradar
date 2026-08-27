-- Multi-City-Erweiterung, vierte Runde echter Erstdaten: drei weitere
-- verifizierte Venues (hr-Sendesaal, ORF RadioKulturhaus, Oper Frankfurt)
-- plus echte Events dort, UND — der eigentliche Mehrwert dieser Runde —
-- echte Konzerte von Rundfunkorchestern (NDR Elbphilharmonie Orchester,
-- Rundfunk-Sinfonieorchester Berlin, hr-Sinfonieorchester, ORF RSO Wien),
-- die laut probe-source-KI-Extraktion tatsächlich in bereits angelegten
-- Venues stattfinden (Elbphilharmonie, Philharmonie Berlin, Konzerthaus
-- Berlin, Alte Oper Frankfurt, Wiener Konzerthaus) — kein neues Venue
-- nötig, nur die Events verknüpfen.
--
-- Orchester-Quellen (NDR/RSB/hr-Sinfonieorchester/ORF RSO) bekommen
-- bewusst KEIN sources.venue_id gesetzt — es sind reisende Ensembles ohne
-- eine einzelne Heim-Venue (die KI-Extraktion fand für dieselbe Quelle
-- auch Termine in anderen Städten/Klöstern/Auslandsgastspielen).
do $$
declare
  v_hamburg uuid := (select id from regions where type = 'city' and slug = 'hamburg');
  v_berlin uuid := (select id from regions where type = 'city' and slug = 'berlin');
  v_vienna uuid := (select id from regions where type = 'city' and slug = 'vienna');
  v_frankfurt uuid := (select id from regions where type = 'city' and slug = 'frankfurt');

  -- Fallback auf die alten Slugs: die Umbenennung auf den kanonischen
  -- Slug läuft erst in den 20261101000011-014_city_import_*.sql-Dateien
  -- (später in der Zeitstempel-Reihenfolge als diese Datei), auf einer
  -- frischen DB existieren an dieser Stelle daher noch die alten Slugs.
  v_elbphilharmonie uuid := (select id from venues where slug in ('elbphilharmonie-grosser-saal', 'elbphilharmonie-hamburg'));
  v_philharmonie_berlin uuid := (select id from venues where slug in ('philharmonie-berlin-grosser-saal', 'philharmonie-berlin'));
  v_konzerthaus_berlin uuid := (select id from venues where slug in ('konzerthaus-berlin-grosser-saal', 'konzerthaus-berlin'));
  v_alte_oper uuid := (select id from venues where slug in ('alte-oper-frankfurt-grosser-saal', 'alte-oper-frankfurt'));
  v_wiener_konzerthaus uuid := (select id from venues where slug in ('wiener-konzerthaus-grosser-saal', 'wiener-konzerthaus'));

  v_hr_sendesaal uuid;
  v_orf_radiokulturhaus uuid;
  v_oper_frankfurt uuid;

  v_source_ndr uuid;
  v_source_rsb uuid;
  v_source_hr_sinfonieorchester uuid;
  v_source_hr_sendesaal uuid;
  v_source_orf_rso uuid;
  v_source_oper_frankfurt uuid;
begin
  select id into v_source_ndr from sources where name = 'NDR Elbphilharmonie Orchester' and city_id = v_hamburg;
  select id into v_source_rsb from sources where name = 'Rundfunk-Sinfonieorchester Berlin' and city_id = v_berlin;
  select id into v_source_hr_sinfonieorchester from sources where name = 'hr-Sinfonieorchester' and city_id = v_frankfurt;
  select id into v_source_hr_sendesaal from sources where name = 'hr-Sendesaal' and city_id = v_frankfurt;
  select id into v_source_orf_rso from sources where name = 'ORF Radio-Symphonieorchester Wien' and city_id = v_vienna;
  select id into v_source_oper_frankfurt from sources where name = 'Oper Frankfurt' and city_id = v_frankfurt;

  -- hr-Sendesaal — Bertramstraße 8, 60320 Frankfurt am Main.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'hr-sendesaal', 'hr-Sendesaal', 'Bertramstraße 8', '60320', 'Frankfurt am Main',
    ST_MakePoint(8.67583, 50.13583)::geography, 'https://www.hr-sendesaal.de', v_frankfurt
  )
  -- Reconciliation: exakte Slug-Kollision mit dem auf einer frischen DB
  -- chronologisch vorher laufenden Stammdaten-Import, siehe
  -- 20261031000012 für die ausführliche Begründung.
  on conflict (slug) do update set updated_at = now()
  returning id into v_hr_sendesaal;
  update sources set venue_id = v_hr_sendesaal where id = v_source_hr_sendesaal;

  -- ORF RadioKulturhaus — Argentinierstraße 30a, 1040 Wien.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'orf-radiokulturhaus', 'ORF RadioKulturhaus', 'Argentinierstraße 30a', '1040', 'Wien',
    ST_MakePoint(16.373, 48.1946)::geography, 'https://radiokulturhaus.orf.at', v_vienna
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_orf_radiokulturhaus;

  -- Oper Frankfurt — Willy-Brandt-Platz, 60311 Frankfurt am Main.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'oper-frankfurt', 'Oper Frankfurt', 'Willy-Brandt-Platz', '60311', 'Frankfurt am Main',
    ST_MakePoint(8.67417, 50.10806)::geography, 'https://www.oper-frankfurt.de', v_frankfurt
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_oper_frankfurt;
  update sources set venue_id = v_oper_frankfurt where id = v_source_oper_frankfurt;

  -- hr-Sendesaal: 1 echtes Konzert.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('hr-sendesaal-klarinettenzauber-2026-09-06', 'Klarinettenzauber', '2026-09-06T16:00:00Z', v_hr_sendesaal, v_source_hr_sinfonieorchester, 'scheduled');

  -- ORF RadioKulturhaus: 2 echte Konzerte.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('orf-rkh-familienkonzert-abenteuer-klassik-2026-09-18', 'ORF RSO Wien & Markus Poschner: Familienkonzert „Abenteuer Klassik"', '2026-09-18T00:00:00Z', v_orf_radiokulturhaus, v_source_orf_rso, 'scheduled'),
    ('orf-rkh-rso-at-work-2026-09-29', 'RSO@work', '2026-09-29T00:00:00Z', v_orf_radiokulturhaus, v_source_orf_rso, 'scheduled');

  -- Oper Frankfurt: 5 echte Produktionen aus dem aktuellen Spielplan.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('oper-frankfurt-cosi-fan-tutte-2026-08-28', 'Così fan tutte', '2026-08-28T16:30:00Z', v_oper_frankfurt, v_source_oper_frankfurt, 'scheduled'),
    ('oper-frankfurt-turandot-2026-08-28', 'Turandot', '2026-08-28T22:00:00Z', v_oper_frankfurt, v_source_oper_frankfurt, 'scheduled'),
    ('oper-frankfurt-mazeppa-2026-09-12', 'Mazeppa', '2026-09-12T22:00:00Z', v_oper_frankfurt, v_source_oper_frankfurt, 'scheduled'),
    ('oper-frankfurt-sechs-monologe-jedermann-2026-09-18', 'Sechs Monologe aus »Jedermann« / Warten auf heute', '2026-09-18T22:00:00Z', v_oper_frankfurt, v_source_oper_frankfurt, 'scheduled'),
    ('oper-frankfurt-liederabend-alder-peter-2026-09-07', 'Liederabend: Louise Alder und Mauro Peter', '2026-09-07T22:00:00Z', v_oper_frankfurt, v_source_oper_frankfurt, 'scheduled');

  -- NDR Elbphilharmonie Orchester: 3 echte Konzerte in der Elbphilharmonie
  -- + 1 in der Philharmonie Berlin (Tournee-Station, bestehendes Venue).
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('ndr-elbphil-opening-night-2026-09-03', 'Opening Night 2026', '2026-09-03T22:00:00Z', v_elbphilharmonie, v_source_ndr, 'scheduled'),
    ('ndr-elbphil-gilbert-jansen-2026-09-10', 'Alan Gilbert & Janine Jansen', '2026-09-10T18:00:00Z', v_elbphilharmonie, v_source_ndr, 'scheduled'),
    ('ndr-elbphil-meisterkurs-gilbert-2026-08-25', 'Meisterkurs mit Alan Gilbert in der Elphi', '2026-08-25T08:00:00Z', v_elbphilharmonie, v_source_ndr, 'scheduled'),
    ('ndr-elbphil-musikmetropole-berlin-2026-09-07', 'Musikmetropole Berlin: Alan Gilbert & Tamara Stefanovich', '2026-09-07T18:00:00Z', v_philharmonie_berlin, v_source_ndr, 'scheduled');

  -- Rundfunk-Sinfonieorchester Berlin: 2 echte Konzerte in bereits
  -- angelegten Berliner Venues.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('rsb-saisoneroeffnung-musikfest-2026-09-13', 'Saisoneröffnung beim Musikfest Berlin', '2026-09-13T18:00:00Z', v_philharmonie_berlin, v_source_rsb, 'scheduled'),
    ('rsb-opernkonzert-klaus-florian-vogt-2026-09-17', 'Opernkonzert mit Klaus Florian Vogt', '2026-09-17T18:00:00Z', v_konzerthaus_berlin, v_source_rsb, 'scheduled');

  -- hr-Sinfonieorchester: 1 echtes Konzert in der Alten Oper Frankfurt.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('hr-sinfonieorchester-beethoven-5-2026-09-17', 'Beethoven 5', '2026-09-17T17:00:00Z', v_alte_oper, v_source_hr_sinfonieorchester, 'scheduled');

  -- ORF Radio-Symphonieorchester Wien: 1 echtes Konzert im Wiener
  -- Konzerthaus.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('orf-rso-gala-beczala-2026-09-25', 'Gala Piotr Beczała', '2026-09-25T00:00:00Z', v_wiener_konzerthaus, v_source_orf_rso, 'scheduled');
end $$;
