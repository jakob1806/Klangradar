-- Multi-City-Erweiterung, echte Erstdaten (Nutzerauftrag "generell soll
-- alles mit echten Daten fertiggestellt werden").
--
-- WICHTIG: dies sind ECHTE, recherchierte Daten (Adressen/Koordinaten per
-- Websuche verifiziert, Konzerttermine von den jeweiligen offiziellen
-- Spielplänen bzw. kulturpur.de für September 2026 — Stand der Recherche
-- 2026-08-25), KEINE erfundenen Platzhalter. Es handelt sich trotzdem nur
-- um einen kleinen, von Hand kuratierten Ausschnitt (1 Flaggschiff-Venue +
-- 2-3 Konzerte je neue Stadt) — kein vollständiger Import. Die eigentliche
-- Ingestion-Pipeline (sources mit status='under_review', siehe
-- 20261031000009) übernimmt die Breite, sobald sie in einer echten
-- Supabase-Umgebung mit funktionierendem Scraping läuft; dort kann diese
-- Sandbox mangels Browser-Rendering für JS-Kalender nicht ran.
--
-- Programme/Mitwirkende werden bewusst NICHT über event_works/
-- event_participants/persons/ensembles strukturiert modelliert (dafür
-- müssten Personen-/Werk-Stammdaten neu angelegt werden, das würde den
-- Rahmen dieses Bootstraps sprengen) — Dirigent:in/Solist:in/Programm
-- stehen als Klartext in subtitle/description_de, wie es die App auch für
-- unvollständig strukturierte Events aus der Ingestion vorsieht.
do $$
declare
  v_berlin uuid := (select id from regions where type = 'city' and slug = 'berlin');
  v_hamburg uuid := (select id from regions where type = 'city' and slug = 'hamburg');
  v_vienna uuid := (select id from regions where type = 'city' and slug = 'vienna');
  v_frankfurt uuid := (select id from regions where type = 'city' and slug = 'frankfurt');

  v_philharmonie_berlin uuid;
  v_elbphilharmonie uuid;
  v_musikverein uuid;
  v_alte_oper uuid;

  v_source_berlin uuid;
  v_source_hamburg uuid;
  v_source_vienna uuid;
  v_source_frankfurt uuid;
begin
  select id into v_source_berlin from sources where name = 'Berliner Philharmoniker' and city_id = v_berlin;
  select id into v_source_hamburg from sources where name = 'Elbphilharmonie' and city_id = v_hamburg;
  select id into v_source_vienna from sources where name = 'Wiener Musikverein' and city_id = v_vienna;
  select id into v_source_frankfurt from sources where name = 'Alte Oper Frankfurt' and city_id = v_frankfurt;

  -- Philharmonie Berlin — Herbert-von-Karajan-Str. 1, 10785 Berlin.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'philharmonie-berlin', 'Philharmonie Berlin', 'Herbert-von-Karajan-Straße 1', '10785', 'Berlin',
    ST_MakePoint(13.3690, 52.5093)::geography, 'https://www.berliner-philharmoniker.de', v_berlin
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_philharmonie_berlin;
  update sources set venue_id = v_philharmonie_berlin where id = v_source_berlin;

  -- Elbphilharmonie Hamburg — Platz der Deutschen Einheit 4, 20457 Hamburg.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'elbphilharmonie-hamburg', 'Elbphilharmonie Hamburg', 'Platz der Deutschen Einheit 4', '20457', 'Hamburg',
    ST_MakePoint(9.984355, 53.541328)::geography, 'https://www.elbphilharmonie.de', v_hamburg
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_elbphilharmonie;
  update sources set venue_id = v_elbphilharmonie where id = v_source_hamburg;

  -- Wiener Musikverein — Bösendorferstraße 12, 1010 Wien.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'wiener-musikverein', 'Wiener Musikverein', 'Bösendorferstraße 12', '1010', 'Wien',
    ST_MakePoint(16.37222, 48.20056)::geography, 'https://www.musikverein.at', v_vienna
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_musikverein;
  update sources set venue_id = v_musikverein where id = v_source_vienna;

  -- Alte Oper Frankfurt — Opernplatz 1, 60313 Frankfurt am Main.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'alte-oper-frankfurt', 'Alte Oper Frankfurt', 'Opernplatz 1', '60313', 'Frankfurt am Main',
    ST_MakePoint(8.67194, 50.11583)::geography, 'https://www.alteoper.de', v_frankfurt
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_alte_oper;
  update sources set venue_id = v_alte_oper where id = v_source_frankfurt;

  -- Berlin: Berliner Philharmoniker, 08.09.2026, Christian Thielemann
  -- (Dirigent), Rudolf Buchbinder (Klavier), Mozart-Programm.
  insert into events (slug, title, subtitle, start_datetime, venue_id, source_id, status)
  values (
    'philharmoniker-thielemann-buchbinder-mozart-2026-09-08',
    'Berliner Philharmoniker: Thielemann dirigiert Mozart',
    'Christian Thielemann (Dirigent), Rudolf Buchbinder (Klavier)',
    '2026-09-08 20:00:00+02', v_philharmonie_berlin, v_source_berlin, 'scheduled'
  );

  -- Hamburg: Elbphilharmonie Großer Saal, 3 Termine.
  insert into events (slug, title, subtitle, start_datetime, venue_id, source_id, status) values
    (
      'pittsburgh-symphony-honeck-hadelich-2026-09-02',
      'Pittsburgh Symphony Orchestra',
      'Manfred Honeck (Dirigent), Augustin Hadelich (Violine) — Simon, Barber, Dvořák Sinfonie Nr. 9 "Aus der Neuen Welt"',
      '2026-09-02 20:00:00+02', v_elbphilharmonie, v_source_hamburg, 'scheduled'
    ),
    (
      'anna-lapwood-orgel-elbphilharmonie-2026-09-17',
      'Anna Lapwood: Orgelkonzert',
      'Anna Lapwood (Orgel)',
      '2026-09-17 19:30:00+02', v_elbphilharmonie, v_source_hamburg, 'scheduled'
    ),
    (
      'gstaad-festival-orchestra-van-zweden-2026-09-30',
      'Gstaad Festival Orchestra',
      'Jaap van Zweden (Dirigent) — Elgar Violinkonzert, Beethoven Sinfonie Nr. 5',
      '2026-09-30 20:00:00+02', v_elbphilharmonie, v_source_hamburg, 'scheduled'
    );

  -- Wien: Musikverein Großer Saal, 2 Termine.
  insert into events (slug, title, subtitle, start_datetime, venue_id, source_id, status) values
    (
      'musikverein-sokhiev-beethoven-mozart-prokofiev-2026-09-25',
      'Tugan Sokhiev dirigiert Beethoven, Mozart, Prokofjew',
      'Tugan Sokhiev (Dirigent)',
      '2026-09-25 19:30:00+02', v_musikverein, v_source_vienna, 'scheduled'
    ),
    (
      'musikverein-leonore-mozart-prokofiev-2026-09-13',
      'Beethoven, Mozart, Prokofjew',
      'Leonoren-Ouvertüre Nr. 3, Sinfonie g-Moll, Romeo und Julia',
      '2026-09-13 19:30:00+02', v_musikverein, v_source_vienna, 'scheduled'
    );

  -- Frankfurt: Alte Oper, 3 Termine.
  insert into events (slug, title, subtitle, start_datetime, venue_id, source_id, status) values
    (
      'alte-oper-olivier-latry-back-to-bach-2026-09-14',
      'Olivier Latry: Back to Bach',
      'Olivier Latry (Orgel)',
      '2026-09-14 20:00:00+02', v_alte_oper, v_source_frankfurt, 'scheduled'
    ),
    (
      'alte-oper-anna-lapwood-jung-hip-orgel-2026-09-15',
      'Anna Lapwood: Jung, hip, Orgel!',
      'Anna Lapwood (Orgel)',
      '2026-09-15 20:00:00+02', v_alte_oper, v_source_frankfurt, 'scheduled'
    ),
    (
      'alte-oper-fomo-haydn-jahreszeiten-2026-09-23',
      'Frankfurter Opern- und Museumsorchester: Die Jahreszeiten',
      'Joseph Haydn — Oratorium "Die Jahreszeiten"',
      '2026-09-23 15:00:00+02', v_alte_oper, v_source_frankfurt, 'scheduled'
    );
end $$;
