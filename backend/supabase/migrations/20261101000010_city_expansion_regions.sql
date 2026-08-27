-- Neue Städte für den Klangradar-Stadtkatalog-Import (Berlin, Hamburg,
-- Frankfurt am Main, Wien) -- siehe docs/12-city-expansion-import.md.
-- is_active bleibt bewusst false (Feature-Flag-Konvention aus
-- 20260819000005_regions.sql: München startet als einzige aktive Region;
-- Freischaltung ist eine separate redaktionelle/Produkt-Entscheidung,
-- nachdem Koordinaten/Bildrechte/Kontaktdaten vervollständigt wurden,
-- siehe QA-Blatt der Importdatei).
--
-- Idempotent nachgerüstet (jede insert-Zeile jetzt mit vorherigem
-- "if not exists"-Check statt blindem insert): eine parallel laufende
-- Session hat unabhängig dieselbe Städte-Erweiterung mit denselben Slugs
-- ('de', 'at', 'berlin-land', 'berlin', 'hamburg-land', 'hamburg',
-- 'hessen', 'frankfurt', 'wien-land', 'vienna') bereits gegen Produktion
-- angewendet (siehe 20261031000001_city_model_regions_extension.sql,
-- ebenfalls in diesem Repo) -- regions.slug ist unique, ein blinder
-- zweiter insert würde die gesamte Migration mit einem Constraint-Fehler
-- abbrechen. Bei bereits vorhandenem Slug wird die bestehende Zeile
-- unverändert übernommen (keine Werte überschrieben) statt dupliziert.
do $$
declare
  v_country_de uuid;
  v_country_at uuid;
  v_berlin_land uuid;
  v_hamburg_land uuid;
  v_hessen uuid;
  v_wien_land uuid;
begin
  select id into v_country_de from regions where slug = 'de';
  if v_country_de is null then
    insert into regions (type, name, slug, is_active) values ('country', 'Deutschland', 'de', true) returning id into v_country_de;
  end if;

  select id into v_country_at from regions where slug = 'at';
  if v_country_at is null then
    insert into regions (type, name, slug, is_active) values ('country', 'Österreich', 'at', false) returning id into v_country_at;
  end if;

  select id into v_berlin_land from regions where slug = 'berlin-land';
  if v_berlin_land is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_de, 'Berlin', 'berlin-land', false) returning id into v_berlin_land;
  end if;
  if not exists (select 1 from regions where slug = 'berlin') then
    insert into regions (type, parent_id, name, slug, is_active) values ('city', v_berlin_land, 'Berlin', 'berlin', false);
  end if;

  select id into v_hamburg_land from regions where slug = 'hamburg-land';
  if v_hamburg_land is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_de, 'Hamburg', 'hamburg-land', false) returning id into v_hamburg_land;
  end if;
  if not exists (select 1 from regions where slug = 'hamburg') then
    insert into regions (type, parent_id, name, slug, is_active) values ('city', v_hamburg_land, 'Hamburg', 'hamburg', false);
  end if;

  select id into v_hessen from regions where slug = 'hessen';
  if v_hessen is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_de, 'Hessen', 'hessen', false) returning id into v_hessen;
  end if;
  if not exists (select 1 from regions where slug = 'frankfurt') then
    insert into regions (type, parent_id, name, slug, is_active) values ('city', v_hessen, 'Frankfurt am Main', 'frankfurt', false);
  end if;

  select id into v_wien_land from regions where slug = 'wien-land';
  if v_wien_land is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_country_at, 'Wien', 'wien-land', false) returning id into v_wien_land;
  end if;
  if not exists (select 1 from regions where slug = 'vienna') then
    insert into regions (type, parent_id, name, slug, is_active) values ('city', v_wien_land, 'Wien', 'vienna', false);
  end if;
end $$;
