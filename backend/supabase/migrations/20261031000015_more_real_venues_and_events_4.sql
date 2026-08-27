-- Multi-City-Erweiterung, fünfte Runde echter Erstdaten: sechs weitere
-- verifizierte Venues (resonanzraum Hamburg, KunstKulturKirche
-- Allerheiligen, Haus der Deutschen Ensemble Akademie, Radialsystem,
-- Künstlerhaus Mousonturm, Hochschule für Musik und Theater Hamburg)
-- plus deren echte Veranstaltungen aus der probe-source-KI-Extraktion,
-- außerdem weitere Berliner Philharmoniker-/DSO-Berlin-/Wiener
-- Philharmoniker-Konzerte, die laut Quelle tatsächlich in bereits
-- angelegten Venues stattfinden (Philharmonie Berlin, Wiener Musikverein)
-- — kein neues Venue nötig, nur die Events verknüpfen.
--
-- Bewusst ausgelassen: "Momi Maiga & Friends" (Ensemble Resonanz) mit
-- Venue-Angabe "Telekom Forum" — laut Websuche existiert ein "Telekom
-- Forum" nachweislich nur in Bonn, keine gleichnamige Location in Hamburg
-- konnte verifiziert werden. "Tag im Grünen 2026" (Berliner Philharmoniker,
-- Venue "Kulturforum Berlin") ebenfalls ausgelassen — andere Location als
-- die Philharmonie selbst, nicht sicher als Konzert-Event einzuordnen.
-- Wiener Philharmoniker "Summer Night Concert 2026" (bereits in der
-- Vergangenheit, 2026-06-19) und "83nd Vienna Philharmonic Ball" (kein
-- Konzert) ebenfalls ausgelassen.
do $$
declare
  v_berlin uuid := (select id from regions where type = 'city' and slug = 'berlin');
  v_hamburg uuid := (select id from regions where type = 'city' and slug = 'hamburg');
  v_vienna uuid := (select id from regions where type = 'city' and slug = 'vienna');
  v_frankfurt uuid := (select id from regions where type = 'city' and slug = 'frankfurt');

  v_philharmonie_berlin uuid := (select id from venues where slug = 'philharmonie-berlin-grosser-saal');
  v_musikverein uuid := (select id from venues where slug = 'musikverein-wien-grosser-saal');

  v_resonanzraum uuid;
  v_kunstkulturkirche uuid;
  v_dea_haus uuid;
  v_radialsystem uuid;
  v_mousonturm uuid;
  v_hfmt_hamburg uuid;

  v_source_ensemble_resonanz uuid;
  v_source_ensemble_modern uuid;
  v_source_radialsystem uuid;
  v_source_mousonturm uuid;
  v_source_hfmt_hamburg uuid;
  v_source_berliner_philharmoniker uuid;
  v_source_dso_berlin uuid;
  v_source_wiener_philharmoniker uuid;
begin
  select id into v_source_ensemble_resonanz from sources where name = 'Ensemble Resonanz' and city_id = v_hamburg;
  select id into v_source_ensemble_modern from sources where name = 'Ensemble Modern' and city_id = v_frankfurt;
  select id into v_source_radialsystem from sources where name = 'Radialsystem' and city_id = v_berlin;
  select id into v_source_mousonturm from sources where name = 'Künstlerhaus Mousonturm' and city_id = v_frankfurt;
  select id into v_source_hfmt_hamburg from sources where name = 'Hochschule für Musik und Theater Hamburg' and city_id = v_hamburg;
  select id into v_source_berliner_philharmoniker from sources where name = 'Berliner Philharmoniker' and city_id = v_berlin;
  select id into v_source_dso_berlin from sources where name = 'Deutsches Symphonie-Orchester Berlin' and city_id = v_berlin;
  select id into v_source_wiener_philharmoniker from sources where name = 'Wiener Philharmoniker' and city_id = v_vienna;

  -- resonanzraum (Ensemble Resonanz) — Feldstraße 66, 20359 Hamburg
  -- (Bunker St. Pauli, 1. OG).
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'resonanzraum-hamburg', 'resonanzraum', 'Feldstraße 66', '20359', 'Hamburg',
    ST_MakePoint(9.9636, 53.5606)::geography, 'https://www.ensembleresonanz.com', v_hamburg
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_resonanzraum;
  update sources set venue_id = v_resonanzraum where id = v_source_ensemble_resonanz;

  -- KunstKulturKirche Allerheiligen — Thüringer Straße 35, 60316
  -- Frankfurt am Main.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'kunstkulturkirche-allerheiligen', 'KunstKulturKirche Allerheiligen', 'Thüringer Straße 35', '60316', 'Frankfurt am Main',
    ST_MakePoint(8.6923, 50.1145)::geography, 'https://www.kunstkulturkirche.de', v_frankfurt
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_kunstkulturkirche;

  -- Haus der Deutschen Ensemble Akademie — Schwedlerstraße 2-4, 60314
  -- Frankfurt am Main.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'haus-der-deutschen-ensemble-akademie', 'Haus der Deutschen Ensemble Akademie', 'Schwedlerstraße 2-4', '60314', 'Frankfurt am Main',
    ST_MakePoint(8.7048, 50.1101)::geography, 'https://www.deutsche-ensemble-akademie.de', v_frankfurt
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_dea_haus;
  update sources set venue_id = v_dea_haus where id = v_source_ensemble_modern;

  -- Radialsystem — Holzmarktstraße 33, 10243 Berlin.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'radialsystem-berlin', 'Radialsystem', 'Holzmarktstraße 33', '10243', 'Berlin',
    ST_MakePoint(13.4392, 52.5097)::geography, 'https://www.radialsystem.de', v_berlin
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_radialsystem;
  update sources set venue_id = v_radialsystem where id = v_source_radialsystem;

  -- Künstlerhaus Mousonturm — Waldschmidtstraße 4, 60316 Frankfurt am Main.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'kuenstlerhaus-mousonturm', 'Künstlerhaus Mousonturm', 'Waldschmidtstraße 4', '60316', 'Frankfurt am Main',
    ST_MakePoint(8.6912, 50.1214)::geography, 'https://www.mousonturm.de', v_frankfurt
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_mousonturm;
  update sources set venue_id = v_mousonturm where id = v_source_mousonturm;

  -- Hochschule für Musik und Theater Hamburg (Campus Außenalster, mit
  -- JazzHall) — Harvestehuder Weg 12, 20148 Hamburg.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'hfmt-hamburg', 'Hochschule für Musik und Theater Hamburg', 'Harvestehuder Weg 12', '20148', 'Hamburg',
    ST_MakePoint(9.9975, 53.5691)::geography, 'https://www.hfmt-hamburg.de', v_hamburg
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_hfmt_hamburg;
  update sources set venue_id = v_hfmt_hamburg where id = v_source_hfmt_hamburg;

  -- Ensemble Resonanz: 2 echte Programmpunkte im resonanzraum.
  insert into events (slug, title, start_datetime, venue_id, source_id, status, is_free) values
    ('resonanzraum-urban-string-sinn-2026-08-26', 'urban string »sinn ist ein unding«', '2026-08-26T18:00:00Z', v_resonanzraum, v_source_ensemble_resonanz, 'scheduled', null),
    ('resonanzraum-werkstatt-ich-ist-ein-anderer-2026-09-11', 'werkstatt »ich ist ein anderer«', '2026-09-11T14:00:00Z', v_resonanzraum, v_source_ensemble_resonanz, 'scheduled', true);

  -- Ensemble Modern: 2 echte Programmpunkte.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('ensemble-modern-iema-allerheiligen-2026-08-28', 'IEMA-Ensemble 2025/26 zu Gast in der KunstKulturKirche Allerheiligen', '2026-08-28T17:30:00Z', v_kunstkulturkirche, v_source_ensemble_modern, 'scheduled'),
    ('ensemble-modern-open-young-ears-eisler-2026-08-31', 'Open Young Ears! - Hanns Eisler', '2026-08-31T07:00:00Z', v_dea_haus, v_source_ensemble_modern, 'scheduled');

  -- Radialsystem: 5 echte Programmpunkte.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('radialsystem-for-the-time-being-2026-08-26', 'for the time being', '2026-08-26T17:00:00Z', v_radialsystem, v_source_radialsystem, 'scheduled'),
    ('radialsystem-for-the-time-being-2026-08-27', 'for the time being', '2026-08-27T17:00:00Z', v_radialsystem, v_source_radialsystem, 'scheduled'),
    ('radialsystem-zweiland-2026-08-27', 'Zweiland', '2026-08-27T19:00:00Z', v_radialsystem, v_source_radialsystem, 'scheduled'),
    ('radialsystem-for-the-time-being-2026-08-29', 'for the time being', '2026-08-29T17:00:00Z', v_radialsystem, v_source_radialsystem, 'scheduled'),
    ('radialsystem-for-the-time-being-2026-08-30', 'for the time being', '2026-08-30T17:00:00Z', v_radialsystem, v_source_radialsystem, 'scheduled');

  -- Hochschule für Musik und Theater Hamburg: 1 echtes Konzert in der
  -- hauseigenen JazzHall (Führungen/interne Vorspiele ohne verifizierbare
  -- Einzel-Locations bewusst ausgelassen).
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('hfmt-hamburg-stegreif-echo-chamber-2026-09-10', 'Stegreif Ensemble – echo:chamber', '2026-09-10T17:30:00Z', v_hfmt_hamburg, v_source_hfmt_hamburg, 'scheduled');

  -- Berliner Philharmoniker: 4 weitere echte Konzerte im Großen Saal der
  -- Philharmonie Berlin (bereits existierendes Venue).
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('philharmoniker-brett-dean-2026-09-12', 'Brett Dean dirigiert Brett Dean', '2026-09-12T17:00:00Z', v_philharmonie_berlin, v_source_berliner_philharmoniker, 'scheduled'),
    ('philharmoniker-matinee-orgel-harfe-2026-09-13', 'Matinee: Orgel & Harfe', '2026-09-13T09:00:00Z', v_philharmonie_berlin, v_source_berliner_philharmoniker, 'scheduled'),
    ('philharmoniker-rattle-de-falla-janacek-2026-09-19', 'Sir Simon Rattle dirigiert de Falla, Janáček und eine Uraufführung', '2026-09-19T17:00:00Z', v_philharmonie_berlin, v_source_berliner_philharmoniker, 'scheduled'),
    ('philharmoniker-late-night-down-under-2026-09-19', 'Late Night »Down Under«', '2026-09-19T20:00:00Z', v_philharmonie_berlin, v_source_berliner_philharmoniker, 'scheduled');

  -- Deutsches Symphonie-Orchester Berlin: 3 echte Musikfest-Berlin-
  -- Konzerte, laut Programm in der Philharmonie Berlin.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('dso-berlin-saisoneroeffnung-musikfest-2026-09-15', 'Saisoneröffnung beim Musikfest', '2026-09-15T22:00:00Z', v_philharmonie_berlin, v_source_dso_berlin, 'scheduled'),
    ('dso-berlin-rias-kammerchor-musikfest-2026-09-22', 'RIAS-Kammerchor beim Musikfest', '2026-09-22T22:00:00Z', v_philharmonie_berlin, v_source_dso_berlin, 'scheduled'),
    ('dso-berlin-ollikainen-shaham-2026-09-26', 'Eva Ollikainen und Gil Shaham', '2026-09-26T22:00:00Z', v_philharmonie_berlin, v_source_dso_berlin, 'scheduled');

  -- Wiener Philharmoniker: Neujahrskonzert im Wiener Musikverein
  -- (bereits existierendes Venue).
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('wiener-philharmoniker-neujahrskonzert-2027', 'New Year''s Concert 2027', '2027-01-01T00:00:00Z', v_musikverein, v_source_wiener_philharmoniker, 'scheduled');
end $$;
