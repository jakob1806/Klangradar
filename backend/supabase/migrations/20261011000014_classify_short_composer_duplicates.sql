-- Manche historisch importierten Kurzprofile tragen noch keine Komponistenrolle
-- (z.B. "Rossini"), obwohl ein vollständiges Komponistenprofil mit demselben
-- eindeutigen Nachnamen existiert. Klassifizieren und zur Prüfung vormerken,
-- aber nicht automatisch zusammenführen.
with short_variants as (
  select short.id as short_id, canonical.id as canonical_id
  from persons short
  join persons canonical
    on lower(short.full_name) = regexp_replace(lower(canonical.full_name), '^.* ', '')
   and short.id <> canonical.id
  where position(' ' in trim(short.full_name)) = 0
    and (
      'komponist' = any(canonical.roles)
      or exists (select 1 from works w where w.composer_id = canonical.id)
    )
), unique_variants as (
  select short_id, min(canonical_id::text)::uuid as canonical_id
  from short_variants
  group by short_id
  having count(*) = 1
)
update persons p
set roles = array_append(p.roles, 'komponist'::participant_role)
from unique_variants uv
where p.id = uv.short_id
  and not ('komponist' = any(p.roles));

with short_variants as (
  select short.id as short_id, canonical.id as canonical_id
  from persons short
  join persons canonical
    on lower(short.full_name) = regexp_replace(lower(canonical.full_name), '^.* ', '')
   and short.id <> canonical.id
  where position(' ' in trim(short.full_name)) = 0
    and 'komponist' = any(canonical.roles)
), unique_variants as (
  select short_id, min(canonical_id::text)::uuid as canonical_id
  from short_variants
  group by short_id
  having count(*) = 1
)
insert into person_duplicate_candidates (person_a_id, person_b_id, status)
select short_id, canonical_id, 'pending'
from unique_variants
on conflict do nothing;
