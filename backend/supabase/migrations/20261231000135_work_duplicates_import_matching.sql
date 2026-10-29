-- Erstellt von Claude Code (Nutzerwunsch 29.10.2026):
--
-- 1. Werk-Duplikate zielsicherer. Der Import merkt Werke mit ähnlichem
--    Titel zur Prüfung vor (find_similar_works, pg_trgm). Alle 23 bisherigen
--    Vorschläge waren falsch, z. B. "Klavierkonzert op. 19" / "op. 73",
--    "Fantasie KV 475" / "BWV 1121", "III. Allegro" / "IV. Allegro aus
--    Symphonie Nr. 5", "Auftragskomposition für Fagott" / "für Orgel".
--    Ein Insert-Trigger verwirft Paare mit Gegenbeweis: anderer Komponist,
--    andere Werkverzeichnisnummer, andere Nummer ("Nr. 2"), andere Tonart,
--    anderer Satz (römische Ziffer) oder andere Besetzung ("für …").
-- 2. Duplikate früher abfangen: Bekommt eine Person (neu oder nachträglich)
--    eine Wikidata-ID oder einen Namen, den es schon gibt, entsteht sofort
--    ein Vorschlag; eindeutige Fälle werden stündlich zusammengeführt (statt
--    einmal nachts). Gleiches für Ensembles mit gleicher Wikidata-ID.

-- ===========================================================================
-- 1. Werke
-- ===========================================================================
create or replace function public.work_match_text(p_title text, p_catalog text)
returns text language sql immutable parallel safe as $$
  select lower(translate(coalesce(p_title, '') || ' ' || coalesce(p_catalog, ''), 'ÄÖÜäöü–—', 'AOUaou--'));
$$;

-- Werkverzeichnis-Schlüssel, z. B. "kv 475", "bwv 1121", "op 18/1", "hob iii:78".
create or replace function public.work_catalog_key(p_text text)
returns text language sql immutable parallel safe as $$
  select regexp_replace(lower(regexp_replace(m[1], '\.', '', 'g')), '^k$', 'kv') || ' ' || regexp_replace(lower(m[2]), '\s+', '', 'g')
  from regexp_matches(p_text, '\m(kv|k\.|bwv|hwv|woo|op\.?|hob\.?|d\.|wab|rv|trv|sz\.?|bb|s\.)\s*([ivx]+\s*[:.]\s*\d+|\d+[a-z]?(\s*/\s*\d+)?)', 'i') m
  limit 1;
$$;

create or replace function public.work_number(p_text text)
returns text language sql immutable parallel safe as $$
  select (regexp_match(p_text, '\m(nr|no|n°)\.?\s*(\d+)', 'i'))[2];
$$;

create or replace function public.work_tonality(p_text text)
returns text language sql immutable parallel safe as $$
  select lower(m[1]) || '-' || lower(m[2])
  from regexp_matches(p_text, '\m([a-h](?:is|es|s)?)[- ](dur|moll)\M', 'i') m
  limit 1;
$$;

create or replace function public.work_movement(p_text text)
returns text language sql immutable parallel safe as $$
  select lower((regexp_match(p_text, '^\s*([ivx]{1,5})\.\s', 'i'))[1]);
$$;

create or replace function public.work_scoring(p_text text)
returns text language sql immutable parallel safe as $$
  select lower((regexp_match(p_text, '\mf(?:u|ü)r\s+([a-z]+)', 'i'))[1]);
$$;

create or replace function public.works_clearly_different(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from works a, works b,
      lateral (select work_match_text(a.title, a.catalog_number) as ta, work_match_text(b.title, b.catalog_number) as tb) t
    where a.id = p_a and b.id = p_b and (
      (a.composer_id is not null and b.composer_id is not null and a.composer_id <> b.composer_id)
      or (work_catalog_key(t.ta) is not null and work_catalog_key(t.tb) is not null and work_catalog_key(t.ta) <> work_catalog_key(t.tb))
      or (work_number(t.ta) is not null and work_number(t.tb) is not null and work_number(t.ta) <> work_number(t.tb))
      or (coalesce(lower(a.key_signature), work_tonality(t.ta)) is not null
          and coalesce(lower(b.key_signature), work_tonality(t.tb)) is not null
          and replace(coalesce(lower(a.key_signature), work_tonality(t.ta)), ' ', '-')
              <> replace(coalesce(lower(b.key_signature), work_tonality(t.tb)), ' ', '-'))
      or (work_movement(t.ta) is not null and work_movement(t.tb) is not null and work_movement(t.ta) <> work_movement(t.tb))
      or (work_scoring(t.ta) is not null and work_scoring(t.tb) is not null and work_scoring(t.ta) <> work_scoring(t.tb))
    ));
$$;

create or replace function public.work_duplicate_candidates_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.status, 'pending') = 'pending' and works_clearly_different(new.work_a_id, new.work_b_id) then
    return null;
  end if;
  return new;
end;
$$;
drop trigger if exists work_duplicate_candidates_guard on public.work_duplicate_candidates;
create trigger work_duplicate_candidates_guard before insert on public.work_duplicate_candidates
  for each row execute function public.work_duplicate_candidates_guard();

update public.work_duplicate_candidates c
   set status = 'dismissed', reviewed_at = now()
 where c.status = 'pending' and works_clearly_different(c.work_a_id, c.work_b_id);

-- Prüfansicht mit Signalen.
create or replace function public.admin_work_duplicate_review()
returns table (candidate_id uuid, confidence int, similarity numeric, created_at timestamptz, a jsonb, b jsonb, same_catalog boolean, same_composer boolean)
language sql stable security definer set search_path = public as $$
  with c as (select c.* from work_duplicate_candidates c where c.status = 'pending'),
  card as (
    select w.id, work_catalog_key(work_match_text(w.title, w.catalog_number)) as catalog_key, w.composer_id, jsonb_build_object(
      'id', w.id, 'title', w.title, 'catalog_number', w.catalog_number, 'key_signature', w.key_signature,
      'composer', p.full_name, 'introduction', left(w.introduction_de, 200),
      'events', (select count(*) from event_works ew where ew.work_id = w.id),
      'upcoming', (select count(*) from event_works ew join events e on e.id = ew.event_id where ew.work_id = w.id and e.start_datetime >= now())
    ) as data
    from works w left join persons p on p.id = w.composer_id
    where w.id in (select work_a_id from c union select work_b_id from c)
  )
  select c.id,
    case
      when ca.catalog_key is not null and ca.catalog_key = cb.catalog_key and ca.composer_id = cb.composer_id then 95
      when ca.catalog_key is not null and ca.catalog_key = cb.catalog_key then 85
      else round(coalesce(c.similarity_score, 0) * 80)::int
    end,
    c.similarity_score, c.created_at, ca.data, cb.data,
    coalesce(ca.catalog_key = cb.catalog_key, false),
    coalesce(ca.composer_id = cb.composer_id, false)
  from c join card ca on ca.id = c.work_a_id join card cb on cb.id = c.work_b_id
  where is_admin_or_editor()
  order by 2 desc, c.created_at desc;
$$;
revoke all on function public.admin_work_duplicate_review() from public, anon;
grant execute on function public.admin_work_duplicate_review() to authenticated;

-- ===========================================================================
-- 2. Duplikate beim Anlegen erkennen
-- ===========================================================================
create index if not exists persons_wikidata_id_idx on public.persons (wikidata_id) where wikidata_id is not null;
create index if not exists persons_name_key_idx on public.persons (public.person_name_key(full_name));
create index if not exists ensembles_wikidata_id_idx on public.ensembles (wikidata_id) where wikidata_id is not null;

create or replace function public.flag_person_duplicate_on_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_key text := person_name_key(new.full_name);
begin
  if new.wikidata_id is not null then
    insert into person_duplicate_candidates (person_a_id, person_b_id, reason)
    select least(p.id, new.id), greatest(p.id, new.id), 'same_wikidata'
    from persons p
    where p.wikidata_id = new.wikidata_id and p.id <> new.id
      and not exists (select 1 from person_duplicate_candidates c
        where least(c.person_a_id, c.person_b_id) = least(p.id, new.id) and greatest(c.person_a_id, c.person_b_id) = greatest(p.id, new.id));
  end if;
  if v_key <> '' and v_key not in ('nn', 'n n', 'moderation', 'tba', 'n a') then
    insert into person_duplicate_candidates (person_a_id, person_b_id, reason)
    select least(p.id, new.id), greatest(p.id, new.id), 'exact_name'
    from persons p
    where person_name_key(p.full_name) = v_key and p.id <> new.id
      and not exists (select 1 from person_duplicate_candidates c
        where least(c.person_a_id, c.person_b_id) = least(p.id, new.id) and greatest(c.person_a_id, c.person_b_id) = greatest(p.id, new.id));
  end if;
  return null;
exception when others then
  -- Ein Vorschlag darf nie einen Import oder eine Redaktionsänderung blockieren.
  raise warning 'flag_person_duplicate_on_write: %', sqlerrm;
  return null;
end;
$$;
drop trigger if exists flag_person_duplicate_on_write on public.persons;
create trigger flag_person_duplicate_on_write
  after insert or update of wikidata_id, full_name on public.persons
  for each row execute function public.flag_person_duplicate_on_write();

create or replace function public.flag_ensemble_duplicate_on_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.wikidata_id is not null then
    insert into ensemble_duplicate_candidates (ensemble_a_id, ensemble_b_id, similarity_score)
    select least(e.id, new.id), greatest(e.id, new.id), 1
    from ensembles e
    where e.wikidata_id = new.wikidata_id and e.id <> new.id
      and not exists (select 1 from ensemble_duplicate_candidates c
        where least(c.ensemble_a_id, c.ensemble_b_id) = least(e.id, new.id) and greatest(c.ensemble_a_id, c.ensemble_b_id) = greatest(e.id, new.id));
  end if;
  return null;
exception when others then
  raise warning 'flag_ensemble_duplicate_on_write: %', sqlerrm;
  return null;
end;
$$;
drop trigger if exists flag_ensemble_duplicate_on_write on public.ensembles;
create trigger flag_ensemble_duplicate_on_write
  after insert or update of wikidata_id on public.ensembles
  for each row execute function public.flag_ensemble_duplicate_on_write();

-- Eindeutige Personen-Fälle stündlich statt nur nachts zusammenführen.
select cron.unschedule(jobid) from cron.job where jobname = 'person-duplicates-hourly-merge';
select cron.schedule('person-duplicates-hourly-merge', '52 * * * *', $$ select public.auto_merge_exact_person_duplicates(); $$);

notify pgrst, 'reload schema';
