-- Qualitätsprüfung: Ein falscher Entitätstyp ist keine Feldkorrektur.
-- Diese atomaren RPCs verschieben alle Verknüpfungen, bevor der fehlerhafte
-- Ensemble-Datensatz entfernt wird. Damit funktionieren die Aktionen auch
-- bei Datensätzen, die bereits Events, Favoriten, Bilder oder Quellen haben.

create or replace function public.quality_unique_slug(p_table regclass, p_name text)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  base text := trim(both '-' from regexp_replace(
    lower(translate(coalesce(p_name, ''), 'äöüßÄÖÜ', 'aousAOU')),
    '[^a-z0-9]+', '-', 'g'
  ));
  candidate text;
  attempt integer := 0;
  occupied boolean;
begin
  if base = '' then base := 'eintrag'; end if;
  loop
    candidate := case when attempt = 0 then left(base, 80) else left(base, 72) || '-' || (attempt + 1)::text end;
    execute format('select exists(select 1 from %s where slug = $1)', p_table)
      into occupied using candidate;
    if not occupied then return candidate; end if;
    attempt := attempt + 1;
    if attempt > 100 then return left(base, 60) || '-' || substr(gen_random_uuid()::text, 1, 8); end if;
  end loop;
end;
$$;

revoke all on function public.quality_unique_slug(regclass, text) from public;
grant execute on function public.quality_unique_slug(regclass, text) to authenticated;

create or replace function public.quality_ensure_person(
  p_name text,
  p_website_url text default null,
  p_biography_de text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare target_id uuid;
begin
  if not is_admin_or_editor() then raise exception 'Keine Admin- oder Redaktionsberechtigung.'; end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Personenname fehlt.'; end if;

  select id into target_id from persons
  where normalize_entity_name(full_name) = normalize_entity_name(p_name)
  order by is_verified desc, created_at asc limit 1;

  if target_id is null then
    insert into persons(slug, full_name, roles, biography_de, website_url, is_verified)
    values (
      quality_unique_slug('public.persons'::regclass, p_name),
      btrim(p_name),
      array['solist'::participant_role],
      p_biography_de,
      p_website_url,
      false
    ) returning id into target_id;
  else
    update persons set
      website_url = coalesce(website_url, p_website_url),
      biography_de = coalesce(biography_de, p_biography_de)
    where id = target_id;
  end if;
  return target_id;
end;
$$;

revoke all on function public.quality_ensure_person(text, text, text) from public;
grant execute on function public.quality_ensure_person(text, text, text) to authenticated;

create or replace function public.quality_move_ensemble_to_person(p_ensemble_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare source_row ensembles%rowtype; target_id uuid;
begin
  if not is_admin_or_editor() then raise exception 'Keine Admin- oder Redaktionsberechtigung.'; end if;
  select * into source_row from ensembles where id = p_ensemble_id for update;
  if not found then raise exception 'Ensemble nicht gefunden.'; end if;

  target_id := quality_ensure_person(source_row.name, source_row.website_url, source_row.description_de);

  delete from event_participants old_link
  where old_link.ensemble_id = source_row.id
    and exists (
      select 1 from event_participants kept
      where kept.event_id = old_link.event_id and kept.person_id = target_id
    );
  update event_participants
    set person_id = target_id, ensemble_id = null
    where ensemble_id = source_row.id;

  insert into user_favorite_persons(user_id, person_id, notify_new_events)
  select user_id, target_id, notify_new_events from user_favorite_ensembles
  where ensemble_id = source_row.id
  on conflict (user_id, person_id) do nothing;
  delete from user_favorite_ensembles where ensemble_id = source_row.id;

  update sources set person_id = coalesce(person_id, target_id), ensemble_id = null where ensemble_id = source_row.id;
  update entity_candidates set
    created_person_id = coalesce(created_person_id, target_id),
    created_ensemble_id = null,
    status = case when status = 'pending' then 'approved' else status end
  where created_ensemble_id = source_row.id;

  update images set is_primary = false
  where origin_type = 'ensemble' and origin_id = source_row.id and is_primary
    and exists(select 1 from images where origin_type = 'person' and origin_id = target_id and is_primary);
  update images set origin_type = 'person', origin_id = target_id
  where origin_type = 'ensemble' and origin_id = source_row.id;

  delete from field_provenance old_source
  where old_source.entity_type = 'ensemble' and old_source.entity_id = source_row.id
    and exists (
      select 1 from field_provenance kept
      where kept.entity_type = 'person' and kept.entity_id = target_id
        and kept.field_name = old_source.field_name
    );
  update field_provenance set entity_type = 'person', entity_id = target_id
  where entity_type = 'ensemble' and entity_id = source_row.id;

  insert into entity_aliases(entity_type, entity_id, alias)
  values ('person', target_id, source_row.name) on conflict do nothing;
  update persons set member_of_ensemble_id = null where member_of_ensemble_id = source_row.id;
  update ensembles set parent_ensemble_id = null where parent_ensemble_id = source_row.id;
  delete from ensemble_duplicate_candidates where ensemble_a_id = source_row.id or ensemble_b_id = source_row.id;
  delete from ensembles where id = source_row.id;
  return target_id;
end;
$$;

grant execute on function public.quality_move_ensemble_to_person(uuid) to authenticated;

create or replace function public.quality_split_ensemble_into_people(
  p_ensemble_id uuid,
  p_names text[]
)
returns uuid[]
language plpgsql
security invoker
set search_path = public
as $$
declare source_row ensembles%rowtype; person_name text; target_id uuid; target_ids uuid[] := '{}'; link record;
begin
  if not is_admin_or_editor() then raise exception 'Keine Admin- oder Redaktionsberechtigung.'; end if;
  select * into source_row from ensembles where id = p_ensemble_id for update;
  if not found then raise exception 'Ensemble nicht gefunden.'; end if;
  if coalesce(array_length(p_names, 1), 0) < 2 or array_length(p_names, 1) > 8 then
    raise exception 'Zum Aufteilen sind 2 bis 8 Personennamen erforderlich.';
  end if;

  foreach person_name in array p_names loop
    person_name := btrim(person_name);
    if nullif(person_name, '') is null or person_name !~ '[[:space:]]' then
      raise exception 'Unvollständiger Personenname: %', person_name;
    end if;
    target_id := quality_ensure_person(person_name, null, null);
    target_ids := array_append(target_ids, target_id);
    for link in select * from event_participants where ensemble_id = source_row.id loop
      if not exists(select 1 from event_participants where event_id = link.event_id and person_id = target_id) then
        insert into event_participants(event_id, person_id, role, role_label, display_order)
        values (link.event_id, target_id, link.role, link.role_label, link.display_order);
      end if;
    end loop;
  end loop;

  delete from event_participants where ensemble_id = source_row.id;
  update sources set ensemble_id = null where ensemble_id = source_row.id;
  update entity_candidates set created_ensemble_id = null where created_ensemble_id = source_row.id;
  delete from user_favorite_ensembles where ensemble_id = source_row.id;
  delete from images where origin_type = 'ensemble' and origin_id = source_row.id;
  delete from field_provenance where entity_type = 'ensemble' and entity_id = source_row.id;
  update persons set member_of_ensemble_id = null where member_of_ensemble_id = source_row.id;
  update ensembles set parent_ensemble_id = null where parent_ensemble_id = source_row.id;
  delete from ensemble_duplicate_candidates where ensemble_a_id = source_row.id or ensemble_b_id = source_row.id;
  delete from ensembles where id = source_row.id;
  return target_ids;
end;
$$;

grant execute on function public.quality_split_ensemble_into_people(uuid, text[]) to authenticated;

create or replace function public.quality_move_ensemble_to_organizer(p_ensemble_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare source_row ensembles%rowtype; target_id uuid;
begin
  if not is_admin_or_editor() then raise exception 'Keine Admin- oder Redaktionsberechtigung.'; end if;
  select * into source_row from ensembles where id = p_ensemble_id for update;
  if not found then raise exception 'Ensemble nicht gefunden.'; end if;

  select id into target_id from organizers
  where normalize_entity_name(name) = normalize_entity_name(source_row.name)
  order by created_at asc limit 1;
  if target_id is null then
    insert into organizers(slug, name, description_de, website_url)
    values (
      quality_unique_slug('public.organizers'::regclass, source_row.name),
      source_row.name,
      source_row.description_de,
      source_row.website_url
    ) returning id into target_id;
  end if;

  update events e set organizer_id = target_id
  where e.organizer_id is null and exists (
    select 1 from event_participants ep where ep.event_id = e.id and ep.ensemble_id = source_row.id
  );
  delete from event_participants where ensemble_id = source_row.id;
  update sources set organizer_id = coalesce(organizer_id, target_id), ensemble_id = null where ensemble_id = source_row.id;
  update entity_candidates set
    created_organizer_id = coalesce(created_organizer_id, target_id),
    created_ensemble_id = null,
    status = case when status = 'pending' then 'approved' else status end
  where created_ensemble_id = source_row.id;
  delete from user_favorite_ensembles where ensemble_id = source_row.id;

  update images set is_primary = false
  where origin_type = 'ensemble' and origin_id = source_row.id and is_primary
    and exists(select 1 from images where origin_type = 'organizer' and origin_id = target_id and is_primary);
  update images set origin_type = 'organizer', origin_id = target_id
  where origin_type = 'ensemble' and origin_id = source_row.id;

  delete from field_provenance old_source
  where old_source.entity_type = 'ensemble' and old_source.entity_id = source_row.id
    and exists (
      select 1 from field_provenance kept
      where kept.entity_type = 'organizer' and kept.entity_id = target_id
        and kept.field_name = old_source.field_name
    );
  update field_provenance set entity_type = 'organizer', entity_id = target_id
  where entity_type = 'ensemble' and entity_id = source_row.id;

  insert into entity_aliases(entity_type, entity_id, alias)
  values ('organizer', target_id, source_row.name) on conflict do nothing;
  update persons set member_of_ensemble_id = null where member_of_ensemble_id = source_row.id;
  update ensembles set parent_ensemble_id = null where parent_ensemble_id = source_row.id;
  delete from ensemble_duplicate_candidates where ensemble_a_id = source_row.id or ensemble_b_id = source_row.id;
  delete from ensembles where id = source_row.id;
  return target_id;
end;
$$;

grant execute on function public.quality_move_ensemble_to_organizer(uuid) to authenticated;

comment on function public.quality_move_ensemble_to_person(uuid) is
  'Qualitätsprüfung: verschiebt ein falsch als Ensemble gespeichertes Individuum atomar nach persons.';
comment on function public.quality_split_ensemble_into_people(uuid, text[]) is
  'Qualitätsprüfung: teilt einen kombinierten Ensemble-Eintrag in einzelne Personen und verschiebt Event-Verknüpfungen.';
comment on function public.quality_move_ensemble_to_organizer(uuid) is
  'Qualitätsprüfung: verschiebt eine falsch als Ensemble gespeicherte Institution atomar nach organizers.';

-- Letzte DB-Grenze: Selbst ein neuer/vergessener Importpfad oder die manuelle
-- Kandidatenfreigabe darf offensichtliche Fragmente nicht mehr speichern.
create or replace function public.guard_ensemble_name_quality()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  cleaned text;
  normalized text;
  has_ensemble_marker boolean;
begin
  cleaned := btrim(regexp_replace(
    replace(replace(replace(regexp_replace(new.name, '<[^>]+>', ' ', 'g'), '&nbsp;', ' '), '&amp;', '&'), '**', ''),
    '[[:space:]]+', ' ', 'g'
  ));
  normalized := normalize_entity_name(cleaned);
  has_ensemble_marker := cleaned ~* '(chor|choir|orchester|orchestra|ensemble|philharmoni|sinfoniker|symphoniker|symphony|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)';

  if normalized = any(array[
    'ballett','blechblaser','chor','chore','ensemble','extrachor','kinderchor',
    'operchor','opernstudio','orchester','quatuor','quartett','statisterie',
    'kinderstatisterie','zusatzchor'
  ]) then
    raise exception 'Kein konkreter Ensemblename: "%".', cleaned;
  end if;
  if cleaned ~* '(ticketverkauf|abendkasse|vorverkauf|weitere informationen|jetzt buchen|zahlen können|zahlen möchten|erleben sie|entscheiden anschließend|&nbsp;)' then
    raise exception 'Werbe-/Informationstext darf nicht als Ensemble gespeichert werden: "%".', cleaned;
  end if;
  if cleaned ~* '(^|[[:space:](*])(n\.?[[:space:]]*n\.?|tba|tbd|unbekannt|unknown)([[:space:]),.;]|$)'
     or cleaned ~* '(ballettmeister|choreographie|choreografie|statisterie|kinderstatisterie|kostümbild|bühnenbild|dramaturgie)' then
    raise exception 'Rolle, Platzhalter oder Abteilung darf nicht als Ensemble gespeichert werden: "%".', cleaned;
  end if;
  if not has_ensemble_marker and cleaned ~* '(staatsoper|opernhaus|theater|rundfunk|foundation|stiftung|konzertdirektion|agentur|production|produktionsfirma|verein|e\.?[[:space:]]*v\.?$)' then
    raise exception 'Institution/Veranstalter darf nicht als Ensemble gespeichert werden: "%".', cleaned;
  end if;

  new.name := cleaned;
  return new;
end;
$$;

drop trigger if exists ensembles_quality_name_guard on public.ensembles;
create trigger ensembles_quality_name_guard
before insert or update of name on public.ensembles
for each row execute function public.guard_ensemble_name_quality();

-- Deterministisch falsche Altlasten aus dem gemeldeten Bestand können ohne
-- Raten entfernt werden. Personen/Institutionen bleiben dagegen bewusst für
-- die strukturellen RPC-Aktionen erhalten, damit ihre Verknüpfungen nicht
-- verloren gehen.
do $$
declare bad_id uuid;
begin
  for bad_id in
    select id from ensembles
    where normalize_entity_name(name) = any(array[
      'ballett','blechblaser','chor','chore','ensemble','extrachor','kinderchor',
      'operchor','opernstudio','orchester','quatuor','quartett','statisterie',
      'kinderstatisterie','zusatzchor'
    ])
    or name ~* '(ticketverkauf|abendkasse|vorverkauf|weitere informationen|jetzt buchen|zahlen können|zahlen möchten|erleben sie|entscheid(?:en|et) anschließend|&nbsp;)'
    or name ~* '(^|[[:space:](*])(n\.?[[:space:]]*n\.?|tba|tbd|unbekannt|unknown)([[:space:]),.;]|$)'
    or name ~* '(ballettmeister|statisterie|kinderstatisterie|choreographie|choreografie)'
  loop
    delete from event_participants where ensemble_id = bad_id;
    update sources set ensemble_id = null where ensemble_id = bad_id;
    update entity_candidates set created_ensemble_id = null where created_ensemble_id = bad_id;
    delete from user_favorite_ensembles where ensemble_id = bad_id;
    delete from images where origin_type = 'ensemble' and origin_id = bad_id;
    delete from field_provenance where entity_type = 'ensemble' and entity_id = bad_id;
    update persons set member_of_ensemble_id = null where member_of_ensemble_id = bad_id;
    update ensembles set parent_ensemble_id = null where parent_ensemble_id = bad_id;
    delete from ensemble_duplicate_candidates where ensemble_a_id = bad_id or ensemble_b_id = bad_id;
    delete from ensembles where id = bad_id;
  end loop;
end;
$$;

-- Die Bulk-Prüfung lud bisher auf jeder 200er-Seite bis zu 80.000 Namen in
-- die Edge Function. Exakte Duplikate und falsche Typen werden nun in einer
-- einzigen indexgestützten DB-Abfrage verglichen.
create index if not exists persons_audit_normalized_name_idx
  on public.persons (public.normalize_entity_name(full_name));
create index if not exists ensembles_audit_normalized_name_idx
  on public.ensembles (public.normalize_entity_name(name));
create index if not exists venues_audit_normalized_name_idx
  on public.venues (public.normalize_entity_name(name));
create index if not exists works_audit_normalized_name_idx
  on public.works (public.normalize_entity_name(title));
create index if not exists events_audit_normalized_name_idx
  on public.events (public.normalize_entity_name(title));

create or replace function public.audit_exact_name_matches(
  p_entity_type text,
  p_rows jsonb
)
returns table(source_id uuid, match_type text, match_id uuid, match_name text)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  source_table text;
  source_field text;
  other_type text;
  target_table text;
  target_field text;
begin
  select x.table_name, x.name_field into source_table, source_field
  from (values
    ('person','persons','full_name'),
    ('ensemble','ensembles','name'),
    ('venue','venues','name'),
    ('work','works','title'),
    ('event','events','title')
  ) as x(entity_type, table_name, name_field)
  where x.entity_type = p_entity_type;
  if source_table is null then raise exception 'Unbekannter Entitätstyp.'; end if;

  return query execute format($query$
    with input_rows as (
      select id, name from jsonb_to_recordset($1) as r(id uuid, name text)
    )
    select input_rows.id, %L::text, target.id, target.%I::text
    from input_rows
    join %I target
      on public.normalize_entity_name(target.%I) = public.normalize_entity_name(input_rows.name)
     and target.id <> input_rows.id
  $query$, p_entity_type, source_field, source_table, source_field) using p_rows;

  foreach other_type in array array['person','ensemble','venue','work'] loop
    if other_type = p_entity_type then continue; end if;
    select x.table_name, x.name_field into target_table, target_field
    from (values
      ('person','persons','full_name'),
      ('ensemble','ensembles','name'),
      ('venue','venues','name'),
      ('work','works','title')
    ) as x(entity_type, table_name, name_field)
    where x.entity_type = other_type;

    return query execute format($query$
      with input_rows as (
        select id, name from jsonb_to_recordset($1) as r(id uuid, name text)
      )
      select input_rows.id, %L::text, target.id, target.%I::text
      from input_rows
      join %I target
        on public.normalize_entity_name(target.%I) = public.normalize_entity_name(input_rows.name)
    $query$, other_type, target_field, target_table, target_field) using p_rows;
  end loop;
end;
$$;

grant execute on function public.audit_exact_name_matches(text, jsonb) to authenticated;
