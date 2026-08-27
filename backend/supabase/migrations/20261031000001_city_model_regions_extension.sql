-- Multi-City-Erweiterung (Nutzerauftrag "Erweitere Klangradar ... um
-- folgende Konzertregionen: München, Berlin, Hamburg, Wien, Frankfurt am
-- Main"), Abschnitt 1 "Stadtmodell".
--
-- Entscheidung (mit dem Nutzer abgestimmt): KEINE neue Parallel-Tabelle
-- `cities` — es existiert bereits `regions` (Land→Bundesland→Stadt-
-- Hierarchie, siehe 20260819000005_regions.sql), an die das bereits
-- ausgelieferte iOS-Onboarding über profiles.preferred_region_id UND das
-- bestehende Admin-Regionen-Dashboard (admin/src/app/(dashboard)/regions)
-- gebunden sind. Eine zweite, unabhängige Stadt-Tabelle wäre genau die Art
-- von Entitäts-Duplikat, die die Abnahmekriterien dieser Aufgabe explizit
-- ausschließen. Stattdessen wird `regions` um die im Auftrag geforderten
-- Stadt-Felder ERGÄNZT (nullable, nur für type='city'-Zeilen befüllt) —
-- venues.region_id, profiles.preferred_region_id und die bestehende
-- Admin-Seite funktionieren dadurch unverändert weiter.
--
-- `region_name` aus der Auftragsspezifikation (Bundesland-Name) wird NICHT
-- als eigene Textspalte dupliziert — das bildet bereits die bestehende
-- parent_id-Hierarchie ab (state-Zeile als Parent der city-Zeile); siehe
-- die neue view city_regions unten für den bequemen Zugriff.
alter table regions
  add column short_name_de text,
  add column country_code text,
  add column latitude double precision,
  add column longitude double precision,
  add column default_zoom numeric,
  add column search_radius_km numeric,
  add column hero_image_url text,
  -- 'live' = im Client wählbar/im Feed sichtbar, 'soft_launch' = Daten
  -- werden befüllt, aber noch nicht beworben, 'planned' = existiert nur im
  -- Schema/Admin, noch keine Datenarbeit begonnen. is_active (bestehend)
  -- bleibt das reine App-Freischalt-Flag aus der Ursprungsmigration.
  add column editorial_status text not null default 'planned'
    check (editorial_status in ('planned', 'soft_launch', 'live')),
  add column sort_order int not null default 0,
  add column updated_at timestamptz not null default now();

create or replace function touch_regions_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger regions_touch_updated_at
  before update on regions
  for each row execute function touch_regions_updated_at();

-- Plausibilitätsprüfung für Abschnitt 10 "Stadt widerspricht den
-- Koordinaten": Lat/Lng müssen zusammen gesetzt oder beide leer sein, und
-- grob in einem plausiblen Bereich liegen (verhindert z.B. vertauschte
-- lat/lng-Werte beim Anlegen einer neuen Stadt).
alter table regions add constraint regions_latlng_together check (
  (latitude is null) = (longitude is null)
);
alter table regions add constraint regions_latlng_plausible check (
  latitude is null or (latitude between -90 and 90 and longitude between -180 and 180)
);

comment on column regions.short_name_de is 'Kurzform für UI-Chips/Auswahllisten, z.B. "Frankfurt" statt "Frankfurt am Main". Nur für type=city gepflegt.';
comment on column regions.country_code is 'ISO-3166-1-alpha-2, z.B. DE/AT. Nur für type=city gepflegt (auf country-Zeilen redundant zu name/slug, bewusst nicht zusätzlich dort befüllt).';
comment on column regions.editorial_status is 'Redaktioneller Ausbaustand einer Stadt, unabhängig vom App-Freischalt-Flag is_active.';

-- Bestehende München-Zeile auf das neue Slug-Schema heben (bisher
-- 'muenchen') und mit den Auftrags-Werten befüllen. Slug-Änderung ist
-- unkritisch: profiles.preferred_region_id/venues.region_id referenzieren
-- die Zeile über id, nicht über slug; kein Code im Repository (außerhalb
-- dieser Migration selbst) matcht hart auf den String 'muenchen'.
update regions
set slug = 'munich',
    short_name_de = 'München',
    country_code = 'DE',
    latitude = 48.1372,
    longitude = 11.5756,
    default_zoom = 11.5,
    search_radius_km = 40,
    editorial_status = 'live',
    sort_order = 0
where type = 'city' and slug = 'muenchen';

-- Die vier neuen Städte anlegen. Jede bekommt (wie München) eine
-- state-Zeile als Parent, damit die bestehende Land→Bundesland→Stadt-
-- Hierarchie konsistent bleibt und region_name sich weiterhin per Join
-- ableiten lässt. editorial_status='soft_launch': Schema/Datenmodell ist
-- fertig, echte Veranstaltungsdaten fehlen zu Beginn noch (siehe
-- 20261031000009_seed_new_city_sources.sql) — is_active bleibt bewusst
-- false, bis erste echte Daten vorhanden sind und die Redaktion die Stadt
-- freischaltet (siehe Admin-Regionen-Seite).
-- Reconciliation: auf einer frischen DB-Neuaufsetzung legt bereits
-- 20261029000003_city_expansion_regions.sql (chronologisch davor) 'de',
-- 'at' und alle acht state/city-Zeilen unten mit denselben Slugs an --
-- ohne Existenzprüfung würden die folgenden Inserts dort mit "duplicate
-- key value violates unique constraint regions_slug_key" scheitern. Auf
-- Produktion (diese Migration lief zuerst, 20261029000003 ist dort
-- inzwischen selbst idempotent dagegen) ändert sich am bisherigen
-- Verhalten nichts. Fehlt eine Zeile bereits (existiert nicht), wird sie
-- wie zuvor mit den vollen Auftrags-Werten neu angelegt; existiert sie
-- schon (frische DB-Reihenfolge), bleibt sie unverändert -- eine exakte
-- Rekonstruktion der reicheren Produktionsspalten (short_name_de,
-- Koordinaten etc.) für den rein-frischen Fall ist hier kein Ziel.
do $$
declare
  v_de_id uuid;
  v_at_id uuid;
  v_state_id uuid;
begin
  select id into v_de_id from regions where type = 'country' and slug = 'de';
  if v_de_id is null then
    insert into regions (type, name, slug, is_active) values ('country', 'Deutschland', 'de', true)
      returning id into v_de_id;
  end if;

  select id into v_at_id from regions where type = 'country' and slug = 'at';
  if v_at_id is null then
    insert into regions (type, name, slug, is_active) values ('country', 'Österreich', 'at', true)
      returning id into v_at_id;
  end if;

  -- Berlin (Stadtstaat: Bundesland = Stadt selbst, eigener Parent-Eintrag
  -- trotzdem für Konsistenz mit dem übrigen Modell)
  select id into v_state_id from regions where slug = 'berlin-land';
  if v_state_id is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_de_id, 'Berlin', 'berlin-land', true)
      returning id into v_state_id;
  end if;
  if not exists (select 1 from regions where slug = 'berlin') then
    insert into regions (
      type, parent_id, name, slug, is_active, short_name_de, country_code,
      latitude, longitude, default_zoom, search_radius_km, editorial_status, sort_order
    ) values (
      'city', v_state_id, 'Berlin', 'berlin', false, 'Berlin', 'DE',
      52.5200, 13.4050, 10.8, 45, 'soft_launch', 1
    );
  end if;

  -- Hamburg (ebenfalls Stadtstaat)
  select id into v_state_id from regions where slug = 'hamburg-land';
  if v_state_id is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_de_id, 'Hamburg', 'hamburg-land', true)
      returning id into v_state_id;
  end if;
  if not exists (select 1 from regions where slug = 'hamburg') then
    insert into regions (
      type, parent_id, name, slug, is_active, short_name_de, country_code,
      latitude, longitude, default_zoom, search_radius_km, editorial_status, sort_order
    ) values (
      'city', v_state_id, 'Hamburg', 'hamburg', false, 'Hamburg', 'DE',
      53.5511, 9.9937, 11.2, 40, 'soft_launch', 2
    );
  end if;

  -- Wien
  select id into v_state_id from regions where slug = 'wien-land';
  if v_state_id is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_at_id, 'Wien', 'wien-land', true)
      returning id into v_state_id;
  end if;
  if not exists (select 1 from regions where slug = 'vienna') then
    insert into regions (
      type, parent_id, name, slug, is_active, short_name_de, country_code,
      latitude, longitude, default_zoom, search_radius_km, editorial_status, sort_order
    ) values (
      'city', v_state_id, 'Wien', 'vienna', false, 'Wien', 'AT',
      48.2082, 16.3738, 11.2, 40, 'soft_launch', 3
    );
  end if;

  -- Frankfurt am Main (Bundesland Hessen)
  select id into v_state_id from regions where slug = 'hessen';
  if v_state_id is null then
    insert into regions (type, parent_id, name, slug, is_active) values ('state', v_de_id, 'Hessen', 'hessen', true)
      returning id into v_state_id;
  end if;
  if not exists (select 1 from regions where slug = 'frankfurt') then
    insert into regions (
      type, parent_id, name, slug, is_active, short_name_de, country_code,
      latitude, longitude, default_zoom, search_radius_km, editorial_status, sort_order
    ) values (
      'city', v_state_id, 'Frankfurt am Main', 'frankfurt', false, 'Frankfurt', 'DE',
      50.1109, 8.6821, 11.5, 35, 'soft_launch', 4
    );
  end if;
end $$;

-- Bequemer Zugriff für Admin/RPCs: nur die city-Zeilen, mit aufgelöstem
-- Bundesland-/Land-Namen (ersetzt das in der Auftragsspezifikation
-- geforderte, hier bewusst nicht duplizierte `region_name`-Feld).
create or replace view city_regions as
select
  c.id, c.slug, c.name as name_de, c.short_name_de, c.country_code,
  s.name as region_name, c.timezone, c.latitude, c.longitude,
  c.default_zoom, c.search_radius_km, c.hero_image_url, c.is_active,
  c.editorial_status, c.sort_order, c.created_at, c.updated_at
from regions c
left join regions s on s.id = c.parent_id
where c.type = 'city';

grant select on city_regions to anon, authenticated;

-- Helfer für Parameter-Defaults in RPCs (siehe 20261031000005 u.a.):
-- Postgres erlaubt KEINE Subquery direkt in einem DEFAULT-Ausdruck einer
-- Funktionssignatur ("cannot use subquery in DEFAULT expression"), ein
-- Funktionsaufruf ist dagegen erlaubt — daher dieser kleine stable-Wrapper
-- statt `default (select id from regions where slug = 'munich')` direkt
-- in den betroffenen create function-Signaturen.
create or replace function munich_city_id() returns uuid
language sql stable as $$
  select id from regions where type = 'city' and slug = 'munich';
$$;
