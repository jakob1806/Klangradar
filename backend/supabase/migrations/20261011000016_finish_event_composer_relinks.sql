-- Expliziter Abschluss für zwei Altprofile, deren diakritische bzw. bereits
-- vorhandene Alias-Schreibweise die generische Bereinigung nicht erfasst hat.
with name_map(short_name, canonical_name) as (
  values
    ('Mozart'::text, 'Wolfgang Amadeus Mozart'::text),
    ('Dvořák'::text, 'Antonín Dvořák'::text)
), replacements as (
  select short.id as short_id, canonical.id as canonical_id, short.full_name as alias
  from name_map nm
  join persons short on short.full_name = nm.short_name
  join persons canonical on canonical.full_name = nm.canonical_name
)
update works w
set composer_id = r.canonical_id
from replacements r
where w.composer_id = r.short_id;

with name_map(short_name, canonical_name) as (
  values
    ('Mozart'::text, 'Wolfgang Amadeus Mozart'::text),
    ('Dvořák'::text, 'Antonín Dvořák'::text)
), replacements as (
  select short.id as short_id, canonical.id as canonical_id
  from name_map nm
  join persons short on short.full_name = nm.short_name
  join persons canonical on canonical.full_name = nm.canonical_name
)
update event_participants ep
set person_id = r.canonical_id
from replacements r
where ep.person_id = r.short_id
  and ep.role = 'komponist';

with name_map(short_name, canonical_name) as (
  values
    ('Mozart'::text, 'Wolfgang Amadeus Mozart'::text),
    ('Dvořák'::text, 'Antonín Dvořák'::text)
)
insert into entity_aliases (entity_type, entity_id, alias)
select 'person', canonical.id, short.full_name
from name_map nm
join persons short on short.full_name = nm.short_name
join persons canonical on canonical.full_name = nm.canonical_name
on conflict do nothing;
