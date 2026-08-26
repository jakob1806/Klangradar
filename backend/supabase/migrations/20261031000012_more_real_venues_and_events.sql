-- Multi-City-Erweiterung, zweite Runde echter Erstdaten: fünf weitere
-- verifizierte Venues (Adresse/Koordinaten per Websuche geprüft) plus
-- echte, aktuelle Veranstaltungen — diesmal nicht von Hand recherchiert,
-- sondern über die bereits vorhandene probe-source-Edge-Function
-- (Tier-3-KI-Extraktion aus dem echten Seitentext) ermittelt und hier
-- manuell in echte events-Zeilen übernommen, siehe "URL manuell
-- hinzufügen"-Empfehlung in probe-source/index.ts für type="scrape"-
-- Quellen ohne strukturierte Daten.
--
-- Bewusst gefiltert: die KI-Extraktion fand bei mehreren Quellen auch
-- Führungen/Backstage-Touren ("Sommerliche Führung", "Backstage Guided
-- Tour") — das sind keine Konzert-/Vorstellungs-Events im Sinne der App,
-- daher NICHT übernommen. Staatsoper Unter den Linden lieferte in diesem
-- Durchlauf ausschließlich Führungen — Venue trotzdem angelegt (echte
-- Adresse), aber ohne Events, bis ein Durchlauf echte Vorstellungen
-- findet.
do $$
declare
  v_berlin uuid := (select id from regions where type = 'city' and slug = 'berlin');
  v_vienna uuid := (select id from regions where type = 'city' and slug = 'vienna');

  v_konzerthaus_berlin uuid;
  v_deutsche_oper uuid;
  v_staatsoper_linden uuid;
  v_wiener_konzerthaus uuid;
  v_theater_wien uuid;

  v_source_konzerthaus_berlin uuid;
  v_source_deutsche_oper uuid;
  v_source_staatsoper_linden uuid;
  v_source_wiener_konzerthaus uuid;
  v_source_theater_wien uuid;
begin
  select id into v_source_konzerthaus_berlin from sources where name = 'Konzerthaus Berlin' and city_id = v_berlin;
  select id into v_source_deutsche_oper from sources where name = 'Deutsche Oper Berlin' and city_id = v_berlin;
  select id into v_source_staatsoper_linden from sources where name = 'Staatsoper Unter den Linden' and city_id = v_berlin;
  select id into v_source_wiener_konzerthaus from sources where name = 'Wiener Konzerthaus' and city_id = v_vienna;
  select id into v_source_theater_wien from sources where name = 'Theater an der Wien' and city_id = v_vienna;

  -- Konzerthaus Berlin — Gendarmenmarkt, 10117 Berlin.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'konzerthaus-berlin', 'Konzerthaus Berlin', 'Gendarmenmarkt 2', '10117', 'Berlin',
    ST_MakePoint(13.39222, 52.51361)::geography, 'https://www.konzerthaus.de', v_berlin
  )
  returning id into v_konzerthaus_berlin;
  update sources set venue_id = v_konzerthaus_berlin where id = v_source_konzerthaus_berlin;

  -- Deutsche Oper Berlin — Bismarckstraße 35, 10627 Berlin.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'deutsche-oper-berlin', 'Deutsche Oper Berlin', 'Bismarckstraße 35', '10627', 'Berlin',
    ST_MakePoint(13.31056, 52.51194)::geography, 'https://www.deutscheoperberlin.de', v_berlin
  )
  -- Reconciliation: exakt derselbe Slug existiert auf einer frischen
  -- DB-Neuaufsetzung bereits aus dem dort chronologisch vorher
  -- gelaufenen Stammdaten-Import (20261029000004) -- ON CONFLICT statt
  -- blindem Insert, damit RETURNING in beiden Fällen greift (frisch vs.
  -- Produktion, wo diese Migration zuerst lief und den Slug selbst
  -- angelegt hat).
  on conflict (slug) do update set updated_at = now()
  returning id into v_deutsche_oper;
  update sources set venue_id = v_deutsche_oper where id = v_source_deutsche_oper;

  -- Staatsoper Unter den Linden — Unter den Linden 7, 10117 Berlin.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'staatsoper-unter-den-linden', 'Staatsoper Unter den Linden', 'Unter den Linden 7', '10117', 'Berlin',
    ST_MakePoint(13.39472, 52.51667)::geography, 'https://www.staatsoper-berlin.de', v_berlin
  )
  on conflict (slug) do update set updated_at = now()
  returning id into v_staatsoper_linden;
  update sources set venue_id = v_staatsoper_linden where id = v_source_staatsoper_linden;

  -- Wiener Konzerthaus — Lothringerstraße 20, 1030 Wien.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'wiener-konzerthaus', 'Wiener Konzerthaus', 'Lothringerstraße 20', '1030', 'Wien',
    ST_MakePoint(16.37717, 48.20082)::geography, 'https://www.konzerthaus.at', v_vienna
  )
  returning id into v_wiener_konzerthaus;
  update sources set venue_id = v_wiener_konzerthaus where id = v_source_wiener_konzerthaus;

  -- Theater an der Wien — Linke Wienzeile 6, 1060 Wien.
  insert into venues (slug, name, address_street, address_zip, address_city, location, website_url, city_id)
  values (
    'theater-an-der-wien', 'Theater an der Wien', 'Linke Wienzeile 6', '1060', 'Wien',
    ST_MakePoint(16.36389, 48.19958)::geography, 'https://www.theater-wien.at', v_vienna
  )
  returning id into v_theater_wien;
  update sources set venue_id = v_theater_wien where id = v_source_theater_wien;

  -- Deutsche Oper Berlin: 5 echte Produktionen aus dem aktuellen Spielplan.
  insert into events (slug, title, start_datetime, venue_id, source_id, status) values
    ('deutsche-oper-mittwoch-aus-licht-2026-09-18', 'Mittwoch aus Licht', '2026-09-18T22:00:00Z', v_deutsche_oper, v_source_deutsche_oper, 'scheduled'),
    ('deutsche-oper-fliegende-hollaender-2026-10-23', 'Der fliegende Holländer', '2026-10-23T22:00:00Z', v_deutsche_oper, v_source_deutsche_oper, 'scheduled'),
    ('deutsche-oper-in-80-tagen-2026-11-14', 'In 80 Tagen um die Welt', '2026-11-14T23:00:00Z', v_deutsche_oper, v_source_deutsche_oper, 'scheduled'),
    ('deutsche-oper-good-vibes-only-2027-01-21', 'Good Vibes Only', '2027-01-21T23:00:00Z', v_deutsche_oper, v_source_deutsche_oper, 'scheduled'),
    ('deutsche-oper-cosi-fan-tutte-2027-02-27', 'Così fan tutte', '2027-02-27T23:00:00Z', v_deutsche_oper, v_source_deutsche_oper, 'scheduled');

  -- Konzerthaus Berlin: 2 echte Konzerte (Führungen bewusst ausgelassen).
  insert into events (slug, title, subtitle, start_datetime, venue_id, source_id, status) values
    ('konzerthaus-berlin-mohiron-tadschikistan-2026-08-01', 'MOHIRON – Tadschikistan', null, '2026-08-01T14:30:00Z', v_konzerthaus_berlin, v_source_konzerthaus_berlin, 'scheduled'),
    ('konzerthaus-berlin-youth-symphony-ukraine-2026-08-01', 'Youth Symphony Orchestra of Ukraine', null, '2026-08-01T17:00:00Z', v_konzerthaus_berlin, v_source_konzerthaus_berlin, 'scheduled');

  -- Theater an der Wien: Einführungsmatinee zu "La Calisto" (Backstage-
  -- Touren bewusst ausgelassen).
  insert into events (slug, title, subtitle, start_datetime, venue_id, source_id, status) values
    ('theater-wien-einfuehrung-la-calisto-2026-09-06', 'Einführungsmatinee: La Calisto', 'Öffentliche Werkeinführung vor der Premiere', '2026-09-06T09:00:00Z', v_theater_wien, v_source_theater_wien, 'scheduled');

  -- Wiener Konzerthaus: 4 echte Konzerte.
  insert into events (slug, title, subtitle, start_datetime, venue_id, source_id, status) values
    ('wiener-konzerthaus-pittsburgh-kantorow-honeck-2026-09-09', 'Pittsburgh Symphony Orchestra', 'Alexandre Kantorow, Manfred Honeck (Dirigent)', '2026-09-09T22:00:00Z', v_wiener_konzerthaus, v_source_wiener_konzerthaus, 'scheduled'),
    ('wiener-konzerthaus-mahler-academy-barron-2026-09-16', 'Mahler Academy Orchestra', 'Barron, von Steinaecker (Dirigent)', '2026-09-16T22:00:00Z', v_wiener_konzerthaus, v_source_wiener_konzerthaus, 'scheduled'),
    ('wiener-konzerthaus-klangforum-kaziboni-2026-09-19', 'Klangforum Wien', 'Kaziboni (Dirigent)', '2026-09-19T22:00:00Z', v_wiener_konzerthaus, v_source_wiener_konzerthaus, 'scheduled'),
    ('wiener-konzerthaus-piotr-beczala-2026-09-24', 'Piotr Beczała', null, '2026-09-24T22:00:00Z', v_wiener_konzerthaus, v_source_wiener_konzerthaus, 'scheduled');
end $$;
