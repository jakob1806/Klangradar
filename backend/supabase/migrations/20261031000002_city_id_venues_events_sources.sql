-- Multi-City-Erweiterung, Abschnitt 2 "Zuordnung zu Venues und Events".
--
-- venues.region_id existiert bereits (siehe 20260819000005_regions.sql)
-- und ist an das bestehende Admin-Regionen-Dashboard sowie
-- festivals.region_id/discover-sources gebunden — wird NICHT umbenannt,
-- um dort nichts zu brechen. Stattdessen wird `city_id` als eigene,
-- vom Auftrag geforderte Spalte ergänzt und beim Backfill aus dem
-- bestehenden region_id übernommen. city_id ist ab sofort die "operative"
-- Spalte für alle neuen stadtbezogenen Abfragen/RPCs/Admin-Filter;
-- region_id bleibt unverändert für den bestehenden Code bestehen.
-- "if not exists": auf einer frischen DB-Neuaufsetzung legt bereits
-- 20261029000004_city_import_berlin.sql die Spalte vorab an (ihr Import
-- braucht city_id schon, läuft aber chronologisch vor dieser Migration
-- hier) -- ohne den Guard würde diese Migration dort mit "column already
-- exists" scheitern. Auf Produktion (Spalte existiert längst) ändert der
-- Guard nichts am bereits gelaufenen Verhalten.
alter table venues add column if not exists city_id uuid references regions(id);
update venues set city_id = region_id where city_id is null and region_id is not null;
-- Für die (laut Prüfung vor 20260819000005_regions.sql) 37 Alt-Venues ohne
-- region_id: ebenfalls München, mit derselben Begründung wie im
-- ursprünglichen Backfill.
update venues set city_id = (select id from regions where type = 'city' and slug = 'munich')
where city_id is null;
alter table venues alter column city_id set not null;

alter table events add column if not exists city_id uuid references regions(id);
-- events.city_id wird primär aus der Venue übernommen (siehe Trigger
-- unten); zusätzlich eine explizite redaktionelle Override-Möglichkeit,
-- die der Trigger respektiert (siehe events_city_override).
alter table events add column city_override boolean not null default false;

update events e set city_id = v.city_id
from venues v
where e.venue_id = v.id and e.city_id is null;

-- Events ohne (auflösbare) Venue-Stadt bleiben city_id=null — werden über
-- die Qualitätsprüfung sichtbar gemacht (Abschnitt 10), nicht hart auf
-- München gezwungen: eine falsche Stadtzuordnung wäre schlechter als eine
-- sichtbare Lücke.

alter table sources add column if not exists city_id uuid references regions(id);
-- Bestehende Quellen sind aktuell ausschließlich Münchner Quellen (siehe
-- Prüfung analog zur ursprünglichen Venue-Migration); neue Quellen für
-- Berlin/Hamburg/Wien/Frankfurt werden ab dieser Migration mit city_id
-- angelegt (siehe 20261031000009_seed_new_city_sources.sql).
update sources set city_id = (select id from regions where type = 'city' and slug = 'munich')
where city_id is null;

alter table editorial_collections add column if not exists city_id uuid references regions(id);
-- Redaktionelle Sammlungen sind optional stadtspezifisch (z.B. "Diese
-- Woche in Berlin"); bestehende Sammlungen bleiben city_id=null =
-- stadtübergreifend/München-Kontext, keine erzwungene Zuordnung.

-- Automatische Übernahme der Venue-Stadt auf das Event, außer bei
-- explizitem redaktionellem Override (city_override=true) — siehe
-- Auftrag: "Die Stadt eines Events soll automatisch aus seiner Venue
-- übernommen werden. Wenn sich die Venue ändert, muss die Event-Stadt
-- aktualisiert werden. Eine explizite redaktionelle Event-Zuordnung darf
-- möglich sein."
create or replace function sync_event_city_from_venue() returns trigger as $$
begin
  if not new.city_override then
    select city_id into new.city_id from venues where id = new.venue_id;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger events_sync_city_from_venue
  before insert or update of venue_id on events
  for each row execute function sync_event_city_from_venue();

-- Wenn sich die Stadt EINER Venue ändert (Admin-Korrektur), müssen alle
-- nicht-überschriebenen Events dieser Venue nachgezogen werden.
create or replace function cascade_venue_city_to_events() returns trigger as $$
begin
  if new.city_id is distinct from old.city_id then
    update events set city_id = new.city_id
    where venue_id = new.id and city_override = false;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger venues_cascade_city_to_events
  after update of city_id on venues
  for each row execute function cascade_venue_city_to_events();

-- Geforderte Indizes (Auftrag Abschnitt 2).
create index events_city_start_idx on events(city_id, start_datetime);
create index events_city_status_start_idx on events(city_id, status, start_datetime);
create index venues_city_name_idx on venues(city_id, name);
create index sources_city_status_idx on sources(city_id, status);
-- editorial_collections hat kein published_at (nur is_published boolean,
-- siehe 20261002000017_editorial_collections.sql) — Index entsprechend auf
-- dem tatsächlich vorhandenen Sichtbarkeits-/Sortierfeld statt eines
-- fiktiven published_at.
create index editorial_collections_city_published_idx
  on editorial_collections(city_id, is_published, sort_order);

comment on column events.city_override is 'true = Stadt wurde redaktionell explizit gesetzt und wird NICHT mehr automatisch aus der Venue nachgezogen (z.B. Gastspiel, Kooperationsevent in einer anderen Stadt als die Heim-Venue).';
