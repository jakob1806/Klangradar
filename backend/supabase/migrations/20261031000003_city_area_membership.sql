-- Multi-City-Erweiterung, Abschnitt 5 "Konzertregionen".
--
-- Frankfurt soll optional Kronberg im Taunus, Offenbach am Main und Bad
-- Homburg einschließen, OHNE die tatsächliche venues.address_city zu
-- verändern und OHNE Frankfurt-Sonderlogik im Code — "Dasselbe Prinzip
-- soll später auch für angrenzende Orte anderer Städte verwendbar sein."
--
-- Lösung: eine generische n:m-Zuordnung "welche Postleitzahl-Orte zählen
-- redaktionell zu welcher Stadt-Region", unabhängig vom tatsächlichen
-- venues.address_city. Eine Venue kann optional auch DIREKT einer
-- zusätzlichen Region zugeordnet werden (city_area_venue_overrides), für
-- den Fall, dass eine PLZ/Ortsname-Regel zu grob ist.
create table city_area_localities (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references regions(id),
  locality_name text not null,
  postal_code_prefix text,
  created_at timestamptz not null default now(),
  unique (city_id, locality_name)
);
create index city_area_localities_city_idx on city_area_localities(city_id);

comment on table city_area_localities is 'Generische Ortszuordnung zu einer Konzertregion (z.B. Kronberg/Offenbach/Bad Homburg -> Frankfurt), unabhängig von venues.address_city. Für jede Stadt separat pflegbar, keine Stadt hat hartcodierte Sonderfälle im Anwendungscode.';

alter table city_area_localities enable row level security;
create policy "Ortszuordnungen sind öffentlich lesbar" on city_area_localities for select using (true);
create policy "Redaktion verwaltet Ortszuordnungen" on city_area_localities for all
  using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Direkte Venue-Ausnahme, falls Ortsname/PLZ-Matching für einen Einzelfall
-- nicht passt (z.B. eine Venue mit uneindeutigem Ortsnamen).
alter table venues add column city_area_id uuid references regions(id);
comment on column venues.city_area_id is 'Optionale zusätzliche Konzertregion für Venues in einem Nachbarort (z.B. Casals Forum Kronberg -> Frankfurt), zusätzlich zur eigentlichen city_id. address_city bleibt der reale Ortsname.';

insert into city_area_localities (city_id, locality_name, postal_code_prefix)
select id, locality, prefix from (
  select
    (select id from regions where type = 'city' and slug = 'frankfurt') as id,
    unnest(array['Kronberg im Taunus', 'Offenbach am Main', 'Bad Homburg', 'Bad Homburg vor der Höhe']) as locality,
    unnest(array['61476', '63', '61350', '61350']) as prefix
) seed
where id is not null;

-- Erweitert venues_with_latlng-artige/Feed-Abfragen: alle Venues, die zu
-- einer Stadt-Region gehören, sei es über city_id direkt, über eine
-- explizite city_area_id-Ausnahme, oder über den Ortsnamen-Abgleich in
-- city_area_localities.
create or replace view venues_in_city_region as
select v.id as venue_id, r.id as region_city_id
from venues v
join regions r on r.id = v.city_id
where r.type = 'city'
union
select v.id, v.city_area_id
from venues v
where v.city_area_id is not null
union
select v.id, cal.city_id
from venues v
join city_area_localities cal
  on cal.locality_name = v.address_city
  and cal.city_id != v.city_id;

grant select on venues_in_city_region to anon, authenticated;

comment on view venues_in_city_region is 'Alle Venue<->Stadt-Region-Zuordnungen inkl. Nachbarort-Konzertregionen (Abschnitt 5) — event- und venue-bezogene stadtgefilterte Abfragen sollten hierüber joinen statt nur auf venues.city_id, damit z.B. Kronberg im Frankfurt-Feed erscheint.';
