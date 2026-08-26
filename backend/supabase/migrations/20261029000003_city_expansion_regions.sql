-- Neue Städte für den Klangradar-Stadtkatalog-Import (Berlin, Hamburg,
-- Frankfurt am Main, Wien) -- siehe docs/12-city-expansion-import.md.
-- is_active bleibt bewusst false (Feature-Flag-Konvention aus
-- 20260819000005_regions.sql: München startet als einzige aktive Region;
-- Freischaltung ist eine separate redaktionelle/Produkt-Entscheidung,
-- nachdem Koordinaten/Bildrechte/Kontaktdaten vervollständigt wurden,
-- siehe QA-Blatt der Importdatei).
do $$
declare
  v_country_de uuid;
  v_country_at uuid;
begin
  select id into v_country_de from regions where slug = 'de';
  if v_country_de is null then
    insert into regions (type, name, slug, is_active) values ('country', 'Deutschland', 'de', true) returning id into v_country_de;
  end if;
  insert into regions (type, name, slug, is_active) values ('country', 'Österreich', 'at', false) returning id into v_country_at;

  insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_de, 'Berlin', 'berlin-land', false);
  insert into regions (type, parent_id, name, slug, is_active) values ('city', (select id from regions where slug = 'berlin-land'), 'Berlin', 'berlin', false);
  insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_de, 'Hamburg', 'hamburg-land', false);
  insert into regions (type, parent_id, name, slug, is_active) values ('city', (select id from regions where slug = 'hamburg-land'), 'Hamburg', 'hamburg', false);
  insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_de, 'Hessen', 'hessen', false);
  insert into regions (type, parent_id, name, slug, is_active) values ('city', (select id from regions where slug = 'hessen'), 'Frankfurt am Main', 'frankfurt', false);
  insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_at, 'Wien', 'wien-land', false);
  insert into regions (type, parent_id, name, slug, is_active) values ('city', (select id from regions where slug = 'wien-land'), 'Wien', 'vienna', false);
end $$;
