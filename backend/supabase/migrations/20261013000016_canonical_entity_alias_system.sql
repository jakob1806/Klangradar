-- Zentrales System für Hauptschreibweisen und alternative Schreibweisen.
-- `persons.full_name`, `ensembles.name`, `venues.name`, `works.title` bleiben
-- die kanonischen Anzeigenamen. `entity_aliases` enthält ausschließlich
-- alternative Eingaben und verweist immer auf den kanonischen Datensatz.

alter table public.entity_aliases
  drop constraint if exists entity_aliases_entity_type_check;
alter table public.entity_aliases
  add constraint entity_aliases_entity_type_check check (
    entity_type in ('person', 'ensemble', 'venue', 'work', 'organizer', 'festival')
  );

create or replace function public.normalize_entity_name(p_value text)
returns text
language sql
immutable
parallel safe
as $$
  select lower(trim(regexp_replace(coalesce(p_value, ''), '[^[:alnum:]]+', ' ', 'g')));
$$;

alter table public.entity_aliases
  add column if not exists alias_normalized text
  generated always as (public.normalize_entity_name(alias)) stored;

-- Bereits vorhandene Groß-/Kleinschreibungsvarianten derselben Alias-Zeile
-- deterministisch zusammenführen, bevor der normalisierte Unique-Index kommt.
delete from public.entity_aliases older
using public.entity_aliases newer
where older.entity_type = newer.entity_type
  and older.entity_id = newer.entity_id
  and public.normalize_entity_name(older.alias) = public.normalize_entity_name(newer.alias)
  and older.id > newer.id;

create unique index if not exists entity_aliases_entity_normalized_uniq
  on public.entity_aliases (entity_type, entity_id, alias_normalized);
create index if not exists entity_aliases_normalized_lookup_idx
  on public.entity_aliases (entity_type, alias_normalized);

create or replace function public.validate_entity_alias_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_exists boolean;
  target_name text;
begin
  if new.entity_type = 'person' then select full_name into target_name from persons where id = new.entity_id;
  elsif new.entity_type = 'ensemble' then select name into target_name from ensembles where id = new.entity_id;
  elsif new.entity_type = 'venue' then select name into target_name from venues where id = new.entity_id;
  elsif new.entity_type = 'work' then select title into target_name from works where id = new.entity_id;
  elsif new.entity_type = 'organizer' then select name into target_name from organizers where id = new.entity_id;
  elsif new.entity_type = 'festival' then select name into target_name from festivals where id = new.entity_id;
  end if;
  target_exists := target_name is not null;
  if not target_exists then
    raise exception 'Alias target %/% does not exist', new.entity_type, new.entity_id;
  end if;
  if public.normalize_entity_name(new.alias) = '' then
    raise exception 'Alias must not be empty';
  end if;
  if public.normalize_entity_name(new.alias) = public.normalize_entity_name(target_name) then
    raise exception 'Alias must differ from canonical name';
  end if;
  return new;
end;
$$;

-- Historisch verwaiste polymorphe Aliaszeilen besitzen keinen FK und können
-- daher nach dem Löschen ihres Zielobjekts zurückbleiben. Vor Aktivierung der
-- strikten Validierung entfernen; sie können ohnehin nie aufgelöst werden.
delete from public.entity_aliases a where
  (a.entity_type = 'person' and not exists(select 1 from persons p where p.id=a.entity_id))
  or (a.entity_type = 'ensemble' and not exists(select 1 from ensembles e where e.id=a.entity_id))
  or (a.entity_type = 'venue' and not exists(select 1 from venues v where v.id=a.entity_id))
  or (a.entity_type = 'work' and not exists(select 1 from works w where w.id=a.entity_id))
  or (a.entity_type = 'organizer' and not exists(select 1 from organizers o where o.id=a.entity_id))
  or (a.entity_type = 'festival' and not exists(select 1 from festivals f where f.id=a.entity_id));

drop trigger if exists validate_entity_alias_target_trigger on public.entity_aliases;
create trigger validate_entity_alias_target_trigger
before insert or update on public.entity_aliases
for each row execute function public.validate_entity_alias_target();

-- Wenn die Redaktion eine neue Hauptschreibweise festlegt, bleibt die alte
-- automatisch als Alias erhalten. Veranstaltungen zeigen weiterhin den
-- Namen aus der kanonischen Entitätszeile an.
create or replace function public.remember_previous_canonical_name()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
  v_old_name text;
  v_new_name text;
begin
  if tg_table_name = 'persons' then v_type := 'person'; v_old_name := old.full_name; v_new_name := new.full_name;
  elsif tg_table_name = 'ensembles' then v_type := 'ensemble'; v_old_name := old.name; v_new_name := new.name;
  elsif tg_table_name = 'venues' then v_type := 'venue'; v_old_name := old.name; v_new_name := new.name;
  elsif tg_table_name = 'works' then v_type := 'work'; v_old_name := old.title; v_new_name := new.title;
  else return new;
  end if;

  if public.normalize_entity_name(v_old_name) <> public.normalize_entity_name(v_new_name) then
    insert into entity_aliases(entity_type, entity_id, alias)
    values (v_type, new.id, v_old_name)
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists persons_remember_canonical_name on public.persons;
create trigger persons_remember_canonical_name after update of full_name on public.persons
for each row execute function public.remember_previous_canonical_name();
drop trigger if exists ensembles_remember_canonical_name on public.ensembles;
create trigger ensembles_remember_canonical_name after update of name on public.ensembles
for each row execute function public.remember_previous_canonical_name();
drop trigger if exists venues_remember_canonical_name on public.venues;
create trigger venues_remember_canonical_name after update of name on public.venues
for each row execute function public.remember_previous_canonical_name();
drop trigger if exists works_remember_canonical_name on public.works;
create trigger works_remember_canonical_name after update of title on public.works
for each row execute function public.remember_previous_canonical_name();

create or replace function public.remove_deleted_entity_aliases()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  v_type := case tg_table_name when 'persons' then 'person' when 'ensembles' then 'ensemble' when 'venues' then 'venue' when 'works' then 'work' end;
  if v_type is not null then delete from entity_aliases where entity_type = v_type and entity_id = old.id; end if;
  return old;
end;
$$;
drop trigger if exists persons_remove_aliases on public.persons;
create trigger persons_remove_aliases after delete on public.persons for each row execute function public.remove_deleted_entity_aliases();
drop trigger if exists ensembles_remove_aliases on public.ensembles;
create trigger ensembles_remove_aliases after delete on public.ensembles for each row execute function public.remove_deleted_entity_aliases();
drop trigger if exists venues_remove_aliases on public.venues;
create trigger venues_remove_aliases after delete on public.venues for each row execute function public.remove_deleted_entity_aliases();
drop trigger if exists works_remove_aliases on public.works;
create trigger works_remove_aliases after delete on public.works for each row execute function public.remove_deleted_entity_aliases();

-- Explizit gepflegte Aliasse sind eine redaktionelle Entscheidung. Existiert
-- noch eine alte Stammdatenzeile genau unter diesem Aliasnamen, werden ihre
-- fachlichen Verweise auf die kanonische Zeile umgebogen. Die alte Zeile
-- wird bewusst nicht automatisch gelöscht, damit Biografie/Bilder weiterhin
-- über die vorhandene Duplikate-Prüfung kontrolliert zusammengeführt werden.
create or replace function public.canonicalize_alias_references()
returns trigger language plpgsql security definer set search_path = public as $$
declare alt_id uuid;
begin
  if new.entity_type = 'person' then
    for alt_id in select id from persons where id <> new.entity_id and normalize_entity_name(full_name) = normalize_entity_name(new.alias) loop
      delete from event_participants old_link where old_link.person_id = alt_id
        and exists(select 1 from event_participants canonical_link where canonical_link.event_id = old_link.event_id and canonical_link.person_id = new.entity_id);
      update event_participants set person_id = new.entity_id where person_id = alt_id;
      delete from user_favorite_persons old_favorite where old_favorite.person_id = alt_id
        and exists(select 1 from user_favorite_persons canonical_favorite where canonical_favorite.user_id = old_favorite.user_id and canonical_favorite.person_id = new.entity_id);
      update user_favorite_persons set person_id = new.entity_id where person_id = alt_id;
      update works set composer_id = new.entity_id where composer_id = alt_id;
      update sources set person_id = new.entity_id where person_id = alt_id;
      update entity_candidates set created_person_id = new.entity_id where created_person_id = alt_id;
    end loop;
  elsif new.entity_type = 'ensemble' then
    for alt_id in select id from ensembles where id <> new.entity_id and normalize_entity_name(name) = normalize_entity_name(new.alias) loop
      delete from event_participants old_link where old_link.ensemble_id = alt_id
        and exists(select 1 from event_participants canonical_link where canonical_link.event_id = old_link.event_id and canonical_link.ensemble_id = new.entity_id);
      update event_participants set ensemble_id = new.entity_id where ensemble_id = alt_id;
      delete from user_favorite_ensembles old_favorite where old_favorite.ensemble_id = alt_id
        and exists(select 1 from user_favorite_ensembles canonical_favorite where canonical_favorite.user_id = old_favorite.user_id and canonical_favorite.ensemble_id = new.entity_id);
      update user_favorite_ensembles set ensemble_id = new.entity_id where ensemble_id = alt_id;
      update sources set ensemble_id = new.entity_id where ensemble_id = alt_id;
      update entity_candidates set created_ensemble_id = new.entity_id where created_ensemble_id = alt_id;
    end loop;
  elsif new.entity_type = 'venue' then
    for alt_id in select id from venues where id <> new.entity_id and normalize_entity_name(name) = normalize_entity_name(new.alias) loop
      update events set venue_id = new.entity_id where venue_id = alt_id;
      delete from user_favorite_venues old_favorite where old_favorite.venue_id = alt_id
        and exists(select 1 from user_favorite_venues canonical_favorite where canonical_favorite.user_id = old_favorite.user_id and canonical_favorite.venue_id = new.entity_id);
      update user_favorite_venues set venue_id = new.entity_id where venue_id = alt_id;
      update sources set venue_id = new.entity_id where venue_id = alt_id;
    end loop;
  elsif new.entity_type = 'work' then
    for alt_id in select id from works where id <> new.entity_id and normalize_entity_name(title) = normalize_entity_name(new.alias) loop
      delete from event_works old_link where old_link.work_id = alt_id
        and exists(select 1 from event_works canonical_link where canonical_link.event_id = old_link.event_id and canonical_link.work_id = new.entity_id);
      update event_works set work_id = new.entity_id where work_id = alt_id;
      delete from user_favorite_works old_favorite where old_favorite.work_id = alt_id
        and exists(select 1 from user_favorite_works canonical_favorite where canonical_favorite.user_id = old_favorite.user_id and canonical_favorite.work_id = new.entity_id);
      update user_favorite_works set work_id = new.entity_id where work_id = alt_id;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists canonicalize_alias_references_trigger on public.entity_aliases;
create trigger canonicalize_alias_references_trigger
after insert or update of alias, entity_id on public.entity_aliases
for each row execute function public.canonicalize_alias_references();

-- Bestehende Aliaszeilen einmal durch dieselbe kanonische Reparatur führen.
-- Historisch eventuell redundant gespeicherte Aliasse, die lediglich der
-- aktuellen Hauptschreibweise entsprechen, vorher entfernen.
delete from public.entity_aliases a where
  (a.entity_type = 'person' and exists(select 1 from persons p where p.id=a.entity_id and normalize_entity_name(p.full_name)=a.alias_normalized))
  or (a.entity_type = 'ensemble' and exists(select 1 from ensembles e where e.id=a.entity_id and normalize_entity_name(e.name)=a.alias_normalized))
  or (a.entity_type = 'venue' and exists(select 1 from venues v where v.id=a.entity_id and normalize_entity_name(v.name)=a.alias_normalized))
  or (a.entity_type = 'work' and exists(select 1 from works w where w.id=a.entity_id and normalize_entity_name(w.title)=a.alias_normalized));
update public.entity_aliases set alias = alias;

-- Einheitliche exakte Aliasauflösung für Importer und Redaktion.
create or replace function public.resolve_entity_alias(p_entity_type text, p_name text)
returns table (id uuid, canonical_name text, matched_by text)
language sql
stable
security invoker
as $$
  with candidates as (
    select p.id, p.full_name as canonical_name, 'canonical'::text as matched_by
    from persons p where p_entity_type = 'person' and public.normalize_entity_name(p.full_name) = public.normalize_entity_name(p_name)
    union all
    select e.id, e.name, 'canonical' from ensembles e where p_entity_type = 'ensemble' and public.normalize_entity_name(e.name) = public.normalize_entity_name(p_name)
    union all
    select v.id, v.name, 'canonical' from venues v where p_entity_type = 'venue' and public.normalize_entity_name(v.name) = public.normalize_entity_name(p_name)
    union all
    select w.id, w.title, 'canonical' from works w where p_entity_type = 'work' and public.normalize_entity_name(w.title) = public.normalize_entity_name(p_name)
    union all
    select a.entity_id,
      case a.entity_type
        when 'person' then (select full_name from persons where id = a.entity_id)
        when 'ensemble' then (select name from ensembles where id = a.entity_id)
        when 'venue' then (select name from venues where id = a.entity_id)
        when 'work' then (select title from works where id = a.entity_id)
      end,
      'alias'
    from entity_aliases a
    where a.entity_type = p_entity_type
      and a.alias_normalized = public.normalize_entity_name(p_name)
  )
  select candidates.id, candidates.canonical_name, candidates.matched_by
  from candidates
  where candidates.canonical_name is not null
  order by case when matched_by = 'canonical' then 0 else 1 end
  limit 1;
$$;

grant execute on function public.resolve_entity_alias(text, text) to anon, authenticated, service_role;

-- Ensemble-/Venue-/Werk-Matcher berücksichtigen nun Aliasse. Der bestehende
-- Personen-Matcher tut dies bereits und behält seine Komponistenlogik.
create or replace function public.find_matching_ensemble(
  p_name text, p_similarity_threshold numeric default 0.5, p_result_limit int default 3
)
returns table (id uuid, name text, similarity numeric)
language sql stable as $$
  select e.id, e.name, greatest(
    similarity(e.name, p_name),
    case when public.normalize_entity_name(e.name) = public.normalize_entity_name(p_name) then 1 else 0 end,
    coalesce((select max(case when a.alias_normalized = public.normalize_entity_name(p_name) then 1 else similarity(a.alias, p_name) end)
      from entity_aliases a where a.entity_type = 'ensemble' and a.entity_id = e.id), 0)
  )::numeric
  from ensembles e
  where greatest(similarity(e.name, p_name), coalesce((select max(similarity(a.alias, p_name)) from entity_aliases a where a.entity_type = 'ensemble' and a.entity_id = e.id), 0)) >= p_similarity_threshold
     or public.normalize_entity_name(e.name) = public.normalize_entity_name(p_name)
     or exists(select 1 from entity_aliases a where a.entity_type = 'ensemble' and a.entity_id = e.id and a.alias_normalized = public.normalize_entity_name(p_name))
  order by 3 desc, length(e.name) desc limit p_result_limit;
$$;

create or replace function public.find_matching_venue(
  p_name text, p_similarity_threshold numeric default 0.4, p_result_limit int default 3
)
returns table (id uuid, name text, similarity numeric)
language sql stable as $$
  select v.id, v.name, greatest(
    similarity(v.name, p_name),
    case when public.normalize_entity_name(v.name) = public.normalize_entity_name(p_name) then 1 else 0 end,
    coalesce((select max(case when a.alias_normalized = public.normalize_entity_name(p_name) then 1 else similarity(a.alias, p_name) end)
      from entity_aliases a where a.entity_type = 'venue' and a.entity_id = v.id), 0)
  )::numeric
  from venues v
  where greatest(similarity(v.name, p_name), coalesce((select max(similarity(a.alias, p_name)) from entity_aliases a where a.entity_type = 'venue' and a.entity_id = v.id), 0)) >= p_similarity_threshold
     or public.normalize_entity_name(v.name) = public.normalize_entity_name(p_name)
     or exists(select 1 from entity_aliases a where a.entity_type = 'venue' and a.entity_id = v.id and a.alias_normalized = public.normalize_entity_name(p_name))
  order by 3 desc, length(v.name) desc limit p_result_limit;
$$;

create or replace function public.find_matching_work(
  p_title text, p_composer_id uuid default null, p_similarity_threshold numeric default 0.6, p_result_limit int default 5
)
returns table (id uuid, title text, composer_id uuid, similarity numeric)
language sql stable as $$
  select w.id, w.title, w.composer_id, greatest(
    similarity(w.title, p_title),
    case when public.normalize_entity_name(w.title) = public.normalize_entity_name(p_title) then 1 else 0 end,
    coalesce((select max(case when a.alias_normalized = public.normalize_entity_name(p_title) then 1 else similarity(a.alias, p_title) end)
      from entity_aliases a where a.entity_type = 'work' and a.entity_id = w.id), 0)
  )::numeric
  from works w
  where (p_composer_id is null or w.composer_id = p_composer_id)
    and (similarity(w.title, p_title) >= p_similarity_threshold
      or public.normalize_entity_name(w.title) = public.normalize_entity_name(p_title)
      or exists(select 1 from entity_aliases a where a.entity_type = 'work' and a.entity_id = w.id and (a.alias_normalized = public.normalize_entity_name(p_title) or similarity(a.alias, p_title) >= p_similarity_threshold)))
  order by 4 desc, length(w.title) desc limit p_result_limit;
$$;

grant execute on function public.find_matching_ensemble(text, numeric, int) to anon, authenticated, service_role;
grant execute on function public.find_matching_venue(text, numeric, int) to anon, authenticated, service_role;
grant execute on function public.find_matching_work(text, uuid, numeric, int) to anon, authenticated, service_role;

-- Eine globale Suche liefert bei Alias-Treffern immer den kanonischen Titel
-- und dieselbe kanonische ID zurück. Auch Veranstaltungen sind über Aliasse
-- ihrer Mitwirkenden, Ensembles, Komponisten und Werke auffindbar.
drop function if exists public.search_all(text, int);
create function public.search_all(q text, result_limit int default 8)
returns table (
  result_type text, id uuid, slug text, title text, subtitle text, score real,
  photo_url text, start_datetime timestamptz, price_min numeric, is_free boolean
)
language sql stable as $$
  with pattern as (select '%' || trim(q) || '%' as p, trim(q) as raw)
  (
    select distinct 'event'::text, e.id, e.slug, e.title,
      v.name || ' · ' || to_char(e.start_datetime at time zone 'Europe/Berlin', 'DD.MM.YYYY'),
      greatest(similarity(e.title, pattern.raw),
        similarity(v.name, pattern.raw),
        coalesce((select max(similarity(va.alias, pattern.raw)) from entity_aliases va where va.entity_type='venue' and va.entity_id=v.id),0),
        coalesce((select max(greatest(similarity(w.title, pattern.raw), coalesce(similarity(wa.alias, pattern.raw), 0))) from event_works ew join works w on w.id=ew.work_id left join entity_aliases wa on wa.entity_type='work' and wa.entity_id=w.id where ew.event_id=e.id),0),
        coalesce((select max(greatest(similarity(p.full_name, pattern.raw), coalesce(similarity(pa.alias, pattern.raw),0))) from event_works ew join works w on w.id=ew.work_id join persons p on p.id=w.composer_id left join entity_aliases pa on pa.entity_type='person' and pa.entity_id=p.id where ew.event_id=e.id),0),
        coalesce((select max(greatest(coalesce(similarity(pp.full_name, pattern.raw),0),coalesce(similarity(en.name, pattern.raw),0),coalesce(similarity(a.alias, pattern.raw),0))) from event_participants ep left join persons pp on pp.id=ep.person_id left join ensembles en on en.id=ep.ensemble_id left join entity_aliases a on (a.entity_type='person' and a.entity_id=pp.id) or (a.entity_type='ensemble' and a.entity_id=en.id) where ep.event_id=e.id),0)
      )::real,
      null::text, e.start_datetime, e.price_min, e.is_free
    from events e join venues v on v.id=e.venue_id cross join pattern
    where e.status != 'draft' and (
      e.title ilike pattern.p or e.subtitle ilike pattern.p
      or v.name ilike pattern.p
      or exists(select 1 from entity_aliases va where va.entity_type='venue' and va.entity_id=v.id and va.alias ilike pattern.p)
      or exists(select 1 from event_works ew join works w on w.id=ew.work_id left join entity_aliases a on a.entity_type='work' and a.entity_id=w.id where ew.event_id=e.id and (w.title ilike pattern.p or a.alias ilike pattern.p))
      or exists(select 1 from event_works ew join works w on w.id=ew.work_id join persons p on p.id=w.composer_id left join entity_aliases a on a.entity_type='person' and a.entity_id=p.id where ew.event_id=e.id and (p.full_name ilike pattern.p or a.alias ilike pattern.p))
      or exists(select 1 from event_participants ep left join persons pp on pp.id=ep.person_id left join ensembles en on en.id=ep.ensemble_id left join entity_aliases a on (a.entity_type='person' and a.entity_id=pp.id) or (a.entity_type='ensemble' and a.entity_id=en.id) where ep.event_id=e.id and (pp.full_name ilike pattern.p or en.name ilike pattern.p or a.alias ilike pattern.p))
    ) order by 6 desc limit result_limit
  ) union all (
    select 'person', p.id, p.slug, p.full_name, array_to_string(p.roles::text[], ', '),
      greatest(similarity(p.full_name, pattern.raw),coalesce((select max(similarity(a.alias,pattern.raw)) from entity_aliases a where a.entity_type='person' and a.entity_id=p.id),0))::real,
      p.photo_url,null::timestamptz,null::numeric,null::boolean
    from persons p cross join pattern where p.full_name ilike pattern.p or exists(select 1 from entity_aliases a where a.entity_type='person' and a.entity_id=p.id and a.alias ilike pattern.p)
    order by 6 desc limit result_limit
  ) union all (
    select 'ensemble',e.id,e.slug,e.name,e.type::text,greatest(similarity(e.name,pattern.raw),coalesce((select max(similarity(a.alias,pattern.raw)) from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id),0))::real,e.photo_url,null::timestamptz,null::numeric,null::boolean
    from ensembles e cross join pattern where e.name ilike pattern.p or exists(select 1 from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id and a.alias ilike pattern.p) order by 6 desc limit result_limit
  ) union all (
    select 'venue',v.id,v.slug,v.name,v.address_city,greatest(similarity(v.name,pattern.raw),coalesce((select max(similarity(a.alias,pattern.raw)) from entity_aliases a where a.entity_type='venue' and a.entity_id=v.id),0))::real,v.photo_url,null::timestamptz,null::numeric,null::boolean
    from venues v cross join pattern where v.name ilike pattern.p or exists(select 1 from entity_aliases a where a.entity_type='venue' and a.entity_id=v.id and a.alias ilike pattern.p) order by 6 desc limit result_limit
  ) union all (
    select 'work',w.id,null::text,w.title,p.full_name,greatest(similarity(w.title,pattern.raw),coalesce((select max(similarity(a.alias,pattern.raw)) from entity_aliases a where a.entity_type='work' and a.entity_id=w.id),0))::real,null::text,null::timestamptz,null::numeric,null::boolean
    from works w left join persons p on p.id=w.composer_id cross join pattern where w.title ilike pattern.p or exists(select 1 from entity_aliases a where a.entity_type='work' and a.entity_id=w.id and a.alias ilike pattern.p) order by 6 desc limit result_limit
  ) order by 6 desc;
$$;

grant execute on function public.search_all(text, int) to anon, authenticated;
