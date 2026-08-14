-- Bereinigt Komponisten-Kurzprofile, die noch an Werken/Veranstaltungen hängen.
-- Eindeutige Dubletten werden auf das vollständige Profil umgehängt. Begriffe
-- wie "Traditional" bleiben erhalten, weil sie keine abgekürzten Personennamen sind.

-- Vollprofile, die beim Altimport ihre Rolle verloren haben, korrekt klassifizieren.
update persons
set roles = array_append(roles, 'komponist'::participant_role)
where full_name = 'Antonín Dvořák'
  and not ('komponist' = any(roles));

-- Bei Berlioz und Seami existiert kein zweites Vollprofil: das bestehende Profil
-- wird deshalb verlustfrei vervollständigt und die alte Schreibweise als Alias bewahrt.
insert into entity_aliases (entity_type, entity_id, alias)
select 'person', id, full_name from persons where full_name in ('Berlioz', 'Seami')
on conflict do nothing;

update persons
set full_name = case full_name
  when 'Berlioz' then 'Hector Berlioz'
  when 'Seami' then 'Zeami Motokiyo'
end,
roles = case
  when 'komponist' = any(roles) then roles
  else array_append(roles, 'komponist'::participant_role)
end
where full_name in ('Berlioz', 'Seami');

-- Alle eindeutigen Einwort-Dubletten auf das vom zentralen Matcher bevorzugte
-- Vollprofil umhängen. Der hohe Schwellwert verhindert unsichere Familiennamen.
with replacements as (
  select p.id as short_id, matched.id as canonical_id
  from persons p
  cross join lateral (
    select m.id, m.full_name, m.similarity
    from find_matching_person(p.full_name, 0.95, 1) m
  ) matched
  where position(' ' in trim(p.full_name)) = 0
    and 'komponist' = any(p.roles)
    and matched.id <> p.id
    and position(' ' in trim(matched.full_name)) > 0
    and matched.similarity >= 0.95
)
update works w
set composer_id = r.canonical_id
from replacements r
where w.composer_id = r.short_id;

with replacements as (
  select p.id as short_id, matched.id as canonical_id
  from persons p
  cross join lateral (
    select m.id, m.full_name, m.similarity
    from find_matching_person(p.full_name, 0.95, 1) m
  ) matched
  where position(' ' in trim(p.full_name)) = 0
    and 'komponist' = any(p.roles)
    and matched.id <> p.id
    and position(' ' in trim(matched.full_name)) > 0
    and matched.similarity >= 0.95
)
update event_participants ep
set person_id = r.canonical_id
from replacements r
where ep.person_id = r.short_id
  and ep.role = 'komponist';

-- Kurzformen als Such-/Importalias am vollständigen Profil hinterlegen.
with replacements as (
  select p.id as short_id, p.full_name as alias, matched.id as canonical_id
  from persons p
  cross join lateral (
    select m.id, m.full_name, m.similarity
    from find_matching_person(p.full_name, 0.95, 1) m
  ) matched
  where position(' ' in trim(p.full_name)) = 0
    and 'komponist' = any(p.roles)
    and matched.id <> p.id
    and position(' ' in trim(matched.full_name)) > 0
    and matched.similarity >= 0.95
)
insert into entity_aliases (entity_type, entity_id, alias)
select 'person', canonical_id, alias from replacements
on conflict do nothing;
