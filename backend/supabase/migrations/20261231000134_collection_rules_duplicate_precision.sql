-- Erstellt von Claude Code (Nutzerwunsch 29.10.2026):
--
-- 1. Redaktionelle Sammlungen automatisch befüllen: Regeln "alle Konzerte
--    mit Person/Ensemble/Spielstätte X". Neue passende Termine kommen
--    stündlich dazu; manuell hinzugefügte bleiben, manuell entfernte
--    automatische Termine kommen nicht wieder.
-- 2. Werkeinführungen: "Jetzt einen Lauf starten" stößt den Lauf über
--    pg_net im Hintergrund an (vorher wartete die Server Action bis zu zwei
--    Minuten und lief in den Vercel-Timeout → Fehlerseite).
-- 3. Duplikatprüfung zielsicherer:
--    Personen: Bisher 23 verworfene, 0 zusammengeführte Vorschläge. Paare mit
--    unterschiedlicher Wikidata-ID oder widersprüchlichem Geburts-/Sterbejahr
--    werden nicht mehr vorgeschlagen (Trigger, gilt für alle Erkenner);
--    gleiche Wikidata-ID gilt als sicher und wird automatisch
--    zusammengeführt; Datumsabgleich nur noch auf Jahresebene (Platzhalter
--    "1. Januar" blockierte z. B. Piazzolla).
--    Ensembles: Bisher reine Namensähnlichkeit ≥ 0,5 ("Orchester des
--    Staatstheaters …" ~ "Chor des Staatstheaters …"). Jetzt muss die Art
--    übereinstimmen (Orchester, Chor, Ballett, Opernstudio …) und der Name
--    ohne Füllwörter sehr ähnlich sein.
--    Für die Prüfseite liefern admin_person_duplicate_review() und
--    admin_ensemble_duplicate_review() Konfidenz und Signale.

-- ===========================================================================
-- 1. Sammlungs-Regeln
-- ===========================================================================
create table if not exists public.editorial_collection_rules (
  collection_id uuid not null references public.editorial_collections(id) on delete cascade,
  entity_type text not null check (entity_type in ('person', 'ensemble', 'venue')),
  entity_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (collection_id, entity_type, entity_id)
);
alter table public.editorial_collection_rules enable row level security;
create policy "Redaktion verwaltet Sammlungsregeln" on public.editorial_collection_rules
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

alter table public.editorial_collection_events
  add column if not exists source text not null default 'manual' check (source in ('manual', 'rule'));

create table if not exists public.editorial_collection_exclusions (
  collection_id uuid not null references public.editorial_collections(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (collection_id, event_id)
);
alter table public.editorial_collection_exclusions enable row level security;
create policy "Redaktion verwaltet Sammlungsausschlüsse" on public.editorial_collection_exclusions
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

create or replace function public.collection_rule_events(p_collection_id uuid)
returns table (event_id uuid)
language sql stable security definer set search_path = public as $$
  select distinct e.id
  from editorial_collection_rules r
  join events e on (
       (r.entity_type = 'venue' and e.venue_id = r.entity_id)
    or (r.entity_type = 'person' and exists (select 1 from event_participants ep where ep.event_id = e.id and ep.person_id = r.entity_id))
    or (r.entity_type = 'ensemble' and exists (select 1 from event_participants ep where ep.event_id = e.id and ep.ensemble_id = r.entity_id))
  )
  where r.collection_id = p_collection_id
    and e.start_datetime >= now()
    and e.status in ('scheduled', 'sold_out');
$$;
revoke all on function public.collection_rule_events(uuid) from public, anon;

-- Gleicht eine (oder alle) Sammlungen mit ihren Regeln ab. Kommende
-- automatische Termine ohne passende Regel fallen heraus; vergangene bleiben.
create or replace function public.sync_editorial_collection_rules(p_collection_id uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_collection uuid;
  v_added int := 0;
  n int;
begin
  if auth.uid() is not null and not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  for v_collection in
    select c.id from editorial_collections c
    where (p_collection_id is null or c.id = p_collection_id)
      and (p_collection_id is not null or exists (select 1 from editorial_collection_rules r where r.collection_id = c.id)
           or exists (select 1 from editorial_collection_events x where x.collection_id = c.id and x.source = 'rule'))
  loop
    delete from editorial_collection_events ce
    using events e
    where ce.collection_id = v_collection and ce.source = 'rule' and e.id = ce.event_id
      and e.start_datetime >= now()
      and ce.event_id not in (select event_id from collection_rule_events(v_collection));

    insert into editorial_collection_events (collection_id, event_id, position, source)
    select v_collection, m.event_id,
      coalesce((select max(position) from editorial_collection_events where collection_id = v_collection), -1)
        + row_number() over (order by e.start_datetime),
      'rule'
    from collection_rule_events(v_collection) m
    join events e on e.id = m.event_id
    where not exists (select 1 from editorial_collection_events ce where ce.collection_id = v_collection and ce.event_id = m.event_id)
      and not exists (select 1 from editorial_collection_exclusions x where x.collection_id = v_collection and x.event_id = m.event_id);
    get diagnostics n = row_count;
    v_added := v_added + n;
  end loop;
  return v_added;
end;
$$;
revoke all on function public.sync_editorial_collection_rules(uuid) from public, anon;
grant execute on function public.sync_editorial_collection_rules(uuid) to authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'editorial-collection-rules';
select cron.schedule('editorial-collection-rules', '41 * * * *', $$ select public.sync_editorial_collection_rules(); $$);

-- Suche für die Regel-Auswahl: Personen, Ensembles, Spielstätten mit Anzahl
-- kommender Termine.
create or replace function public.admin_collection_rule_search(p_query text)
returns table (entity_type text, entity_id uuid, label text, detail text, upcoming int)
language sql stable security definer set search_path = public as $$
  with q as (select nullif(btrim(p_query), '') as q),
  hits as (
    select 'person'::text as entity_type, p.id, p.full_name as label,
      coalesce(p.instrument, array_to_string(p.roles, ', ')) as detail
    from persons p, q where q.q is not null and p.full_name ilike '%' || q.q || '%'
    union all
    select 'ensemble', en.id, en.name, en.type from ensembles en, q
    where q.q is not null and en.name ilike '%' || q.q || '%' and not coalesce(en.is_resolution_placeholder, false)
    union all
    select 'venue', v.id, v.name, v.address_city from venues v, q where q.q is not null and v.name ilike '%' || q.q || '%'
  )
  select h.entity_type, h.id, h.label, h.detail,
    (select count(distinct e.id)::int from events e
      where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out') and (
        (h.entity_type = 'venue' and e.venue_id = h.id)
        or (h.entity_type <> 'venue' and exists (select 1 from event_participants ep where ep.event_id = e.id
              and (ep.person_id = h.id or ep.ensemble_id = h.id)))))
  from hits h
  where is_admin_or_editor()
  order by 5 desc, h.label
  limit 20;
$$;
revoke all on function public.admin_collection_rule_search(text) from public, anon;
grant execute on function public.admin_collection_rule_search(text) to authenticated;

create or replace function public.admin_collection_rules(p_collection_id uuid)
returns table (entity_type text, entity_id uuid, label text, upcoming int)
language sql stable security definer set search_path = public as $$
  select r.entity_type, r.entity_id,
    coalesce(p.full_name, en.name, v.name, '(gelöscht)'),
    (select count(distinct e.id)::int from events e
      where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out') and (
        (r.entity_type = 'venue' and e.venue_id = r.entity_id)
        or (r.entity_type <> 'venue' and exists (select 1 from event_participants ep where ep.event_id = e.id
              and (ep.person_id = r.entity_id or ep.ensemble_id = r.entity_id)))))
  from editorial_collection_rules r
  left join persons p on r.entity_type = 'person' and p.id = r.entity_id
  left join ensembles en on r.entity_type = 'ensemble' and en.id = r.entity_id
  left join venues v on r.entity_type = 'venue' and v.id = r.entity_id
  where r.collection_id = p_collection_id and is_admin_or_editor()
  order by r.created_at;
$$;
revoke all on function public.admin_collection_rules(uuid) from public, anon;
grant execute on function public.admin_collection_rules(uuid) to authenticated;

-- ===========================================================================
-- 2. Werkeinführungen im Hintergrund anstoßen
-- ===========================================================================
create or replace function public.admin_trigger_work_introductions()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  perform run_work_introductions();
end;
$$;
revoke all on function public.admin_trigger_work_introductions() from public, anon;
grant execute on function public.admin_trigger_work_introductions() to authenticated;

-- ===========================================================================
-- 3. Duplikatprüfung
-- ===========================================================================
create or replace function public.persons_clearly_different(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from persons a, persons b
    where a.id = p_a and b.id = p_b and (
      (a.wikidata_id is not null and b.wikidata_id is not null and a.wikidata_id <> b.wikidata_id)
      or (a.birth_date is not null and b.birth_date is not null
          and abs(extract(year from a.birth_date) - extract(year from b.birth_date)) > 1)
      or (a.death_date is not null and b.death_date is not null
          and abs(extract(year from a.death_date) - extract(year from b.death_date)) > 1)
    ));
$$;

create or replace function public.person_duplicate_candidates_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' and persons_clearly_different(new.person_a_id, new.person_b_id) then
    return null;
  end if;
  return new;
end;
$$;
drop trigger if exists person_duplicate_candidates_guard on public.person_duplicate_candidates;
create trigger person_duplicate_candidates_guard before insert on public.person_duplicate_candidates
  for each row execute function public.person_duplicate_candidates_guard();

-- Offene Vorschläge, die sicher verschiedene Personen betreffen, verwerfen;
-- alten Vorschlägen ohne Grund den passenden Grund geben.
update public.person_duplicate_candidates c
   set status = 'dismissed', reviewed_at = now()
 where c.status = 'pending' and persons_clearly_different(c.person_a_id, c.person_b_id);

update public.person_duplicate_candidates c
   set reason = case
     when a.wikidata_id is not null and a.wikidata_id = b.wikidata_id then 'same_wikidata'
     when person_name_key(a.full_name) = person_name_key(b.full_name) then 'exact_name'
     else coalesce(c.reason, 'similar_name') end
  from persons a, persons b
 where a.id = c.person_a_id and b.id = c.person_b_id and c.status = 'pending'
   and (c.reason is null or (a.wikidata_id is not null and a.wikidata_id = b.wikidata_id));

-- Gleiche Wikidata-ID: neue Stufe vor allen Namensregeln.
create or replace function public.detect_same_wikidata_persons()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into person_duplicate_candidates (person_a_id, person_b_id, reason)
  select a.id, b.id, 'same_wikidata'
  from persons a join persons b on a.wikidata_id = b.wikidata_id and a.id < b.id
  where a.wikidata_id is not null
    and not exists (
      select 1 from person_duplicate_candidates c
      where least(c.person_a_id, c.person_b_id) = a.id and greatest(c.person_a_id, c.person_b_id) = b.id);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.detect_same_wikidata_persons() from public, anon, authenticated;

-- Automatisch zusammenführen: gleiche Wikidata-ID immer, gleicher Name nur
-- ohne widersprüchliche Jahre (Tag/Monat sind oft Platzhalter).
create or replace function public.auto_merge_exact_person_duplicates()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cand record;
  keep_id uuid;
  merged integer := 0;
begin
  perform set_config('klangradar.system_merge', 'on', true);
  for cand in
    select c.id, c.person_a_id, c.person_b_id
    from person_duplicate_candidates c
    join persons a on a.id = c.person_a_id
    join persons b on b.id = c.person_b_id
    where c.status = 'pending'
      and (
        -- Gleiche Wikidata-ID nur bei verträglichen Namen: die ID stammt aus
        -- automatischer Zuordnung, und "Johann Strauss" vs. "Johann Strauss
        -- (Sohn)" darf nicht ungeprüft verschmelzen.
        (c.reason = 'same_wikidata' and a.wikidata_id = b.wikidata_id
         and similarity(person_name_key(a.full_name), person_name_key(b.full_name)) >= 0.25
         and (person_name_key(a.full_name) ~ '\m(junior|jun|jr|senior|sen|sr|sohn|vater|der juengere|der aeltere|ii|iii)\M')
             = (person_name_key(b.full_name) ~ '\m(junior|jun|jr|senior|sen|sr|sohn|vater|der juengere|der aeltere|ii|iii)\M'))
        or (c.reason = 'exact_name' and not persons_clearly_different(a.id, b.id))
      )
    order by c.created_at
  loop
    if not exists (select 1 from person_duplicate_candidates where id = cand.id and status = 'pending') then continue; end if;
    select p.id into keep_id
    from persons p
    where p.id in (cand.person_a_id, cand.person_b_id)
    order by (p.photo_url is not null) desc,
             (p.biography_de is not null) desc,
             (select count(*) from event_participants ep where ep.person_id = p.id) desc,
             p.created_at
    limit 1;
    begin
      perform public.merge_person_duplicate_candidate(cand.id, keep_id);
      merged := merged + 1;
    exception when others then
      raise warning 'auto_merge_exact_person_duplicates: Kandidat % übersprungen: %', cand.id, sqlerrm;
    end;
  end loop;
  perform set_config('klangradar.system_merge', 'off', true);
  return merged;
end;
$$;
revoke all on function public.auto_merge_exact_person_duplicates() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'person-duplicates-auto';
select cron.schedule(
  'person-duplicates-auto',
  '30 4 * * *',
  $$ select public.detect_same_wikidata_persons(); select public.detect_person_duplicate_candidates(); select public.auto_merge_exact_person_duplicates(); $$
);

-- Ensembles: Art aus dem Namen und Name ohne Füllwörter.
create or replace function public.ensemble_kind_signature(p_name text)
returns text language sql immutable parallel safe as $$
  select coalesce(string_agg(distinct kind, ',' order by kind), '')
  from (
    select case
      when t ~ '^(kinderchor|knabenchor|maedchenchor|jugendchor|kinder)' then 'kinderchor'
      when t ~ '^extrachor' then 'extrachor'
      when t ~ '^(junge|jung|jugend|youth|studenten|hochschul|universitaet|university)' then 'jugend'
      when t ~ '^(kammer|chamber)' then 'kammer'
      when t ~ '(chor|choir|chorus|choral|vokal|vocal|voices|singer|kantorei)' then 'chor'
      when t ~ '(orchest|philharmoni|symphon|sinfoni|kammerorch|camerata|sinfonietta|band)' then 'orchester'
      when t ~ '^(ballett|ballet|tanz|dance|compagnie|company)' then 'ballett'
      when t ~ '^(opernstudio|studio)' then 'opernstudio'
      when t ~ '(quartet|quartett)' then 'quartett'
      when t ~ '(trio)' then 'trio'
      when t ~ '(quintet|quintett)' then 'quintett'
      when t ~ '^(solist|solisten|solistinnen|mitglied|musiker|musikerinnen|ensemble)' then 'mitglieder'
      when t ~ '^(akademie|academy)' then 'akademie'
      when t ~ '^(oper|opera|staatsoper|theater|theatre)$' then 'haus'
    end as kind
    from regexp_split_to_table(person_name_key(p_name), ' ') t
  ) k
  where kind is not null;
$$;

create or replace function public.ensemble_core_key(p_name text)
returns text language sql immutable parallel safe as $$
  select trim(regexp_replace(person_name_key(p_name),
    '\m(des|der|die|das|und|and|of|the|am|im|in|zu|von|de|du|la|le|il|mitglieder|mitgliedern|musikerinnen|musiker|solistinnen|solisten)\M', ' ', 'g'));
$$;

create or replace function public.detect_ensemble_duplicate_candidates(p_name_similarity_threshold numeric default 0.5)
returns integer language plpgsql as $$
declare v_inserted int := 0;
begin
  update ensemble_duplicate_candidates c set status = 'dismissed', reviewed_at = now()
  from ensembles a, ensembles b where a.id = c.ensemble_a_id and b.id = c.ensemble_b_id and c.status = 'pending'
    and (a.is_family_root or b.is_family_root or a.is_resolution_placeholder or b.is_resolution_placeholder
      or a.parent_ensemble_id = b.id or b.parent_ensemble_id = a.id
      or (a.parent_ensemble_id is not null and a.parent_ensemble_id = b.parent_ensemble_id)
      or ensemble_kind_signature(a.name) <> ensemble_kind_signature(b.name)
      or (a.wikidata_id is not null and b.wikidata_id is not null and a.wikidata_id <> b.wikidata_id)
      or (a.founded_year is not null and b.founded_year is not null and abs(a.founded_year - b.founded_year) > 1));

  insert into ensemble_duplicate_candidates(ensemble_a_id, ensemble_b_id, similarity_score)
  select a.id, b.id, round(greatest(similarity(ensemble_core_key(a.name), ensemble_core_key(b.name)),
                                    case when a.wikidata_id = b.wikidata_id then 1 else 0 end)::numeric, 3)
  from ensembles a join ensembles b on a.id < b.id
  where not a.is_family_root and not b.is_family_root
    and not a.is_resolution_placeholder and not b.is_resolution_placeholder
    and not coalesce(a.parent_ensemble_id = b.id or b.parent_ensemble_id = a.id, false)
    and not (a.parent_ensemble_id is not null and a.parent_ensemble_id = b.parent_ensemble_id)
    and not (a.wikidata_id is not null and b.wikidata_id is not null and a.wikidata_id <> b.wikidata_id)
    and not (a.founded_year is not null and b.founded_year is not null and abs(a.founded_year - b.founded_year) > 1)
    and (
      (a.wikidata_id is not null and a.wikidata_id = b.wikidata_id)
      or (ensemble_kind_signature(a.name) = ensemble_kind_signature(b.name)
          and ensemble_core_key(a.name) <> ''
          and (ensemble_core_key(a.name) = ensemble_core_key(b.name)
               or similarity(ensemble_core_key(a.name), ensemble_core_key(b.name)) >= greatest(p_name_similarity_threshold, 0.75)))
    )
    and not exists (select 1 from ensemble_duplicate_candidates c
      where least(c.ensemble_a_id, c.ensemble_b_id) = least(a.id, b.id) and greatest(c.ensemble_a_id, c.ensemble_b_id) = greatest(a.id, b.id));
  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

-- Prüfseite: "Eindeutige zusammenführen" (gleiche Wikidata-ID bzw. gleicher
-- Name ohne Widerspruch) per Klick statt erst im nächtlichen Lauf.
create or replace function public.admin_auto_merge_person_duplicates()
returns int language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  perform detect_same_wikidata_persons();
  return auto_merge_exact_person_duplicates();
end;
$$;
revoke all on function public.admin_auto_merge_person_duplicates() from public, anon;
grant execute on function public.admin_auto_merge_person_duplicates() to authenticated;

select public.detect_ensemble_duplicate_candidates();
select public.detect_same_wikidata_persons();
select public.auto_merge_exact_person_duplicates();

-- Prüfansicht: Konfidenz, Signale und Kennzahlen je Paar.
create or replace function public.admin_person_duplicate_review()
returns table (
  candidate_id uuid, reason text, confidence int, ai_recommends_merge boolean, ai_reasoning text, created_at timestamptz,
  a jsonb, b jsonb, shared_events int, shared_ensembles int
)
language sql stable security definer set search_path = public as $$
  with c as (
    select c.* from person_duplicate_candidates c where c.status = 'pending'
  ),
  card as (
    select p.id, jsonb_build_object(
      'id', p.id, 'name', p.full_name, 'photo_url', p.photo_url, 'birth_date', p.birth_date, 'death_date', p.death_date,
      'wikidata_id', p.wikidata_id, 'instrument', p.instrument, 'roles', p.roles,
      'biography', left(p.biography_de, 220),
      'events', (select count(*) from event_participants ep where ep.person_id = p.id),
      'upcoming', (select count(*) from event_participants ep join events e on e.id = ep.event_id
                   where ep.person_id = p.id and e.start_datetime >= now()),
      'works', (select count(*) from works w where w.composer_id = p.id),
      'followers', (select count(*) from user_favorite_persons f where f.person_id = p.id)
    ) as data
    from persons p where p.id in (select person_a_id from c union select person_b_id from c)
  )
  select c.id, c.reason,
    case
      when pa.wikidata_id is not null and pa.wikidata_id = pb.wikidata_id then 98
      when c.reason = 'exact_name' then 90
      when c.ai_recommends_merge then 85
      when c.reason = 'extra_names' then 70
      when c.reason = 'surname_only' and (pa.wikidata_id is null or pb.wikidata_id is null) then 60
      when c.reason = 'similar_name' then 55
      else 40
    end
    + case when exists (select 1 from event_participants x join event_participants y on x.event_id = y.event_id
                        where x.person_id = c.person_a_id and y.person_id = c.person_b_id) then -20 else 0 end,
    c.ai_recommends_merge, c.ai_reasoning, c.created_at,
    ca.data, cb.data,
    (select count(*)::int from event_participants x join event_participants y on x.event_id = y.event_id
      where x.person_id = c.person_a_id and y.person_id = c.person_b_id),
    (select count(*)::int from (
      select distinct ep2.ensemble_id from event_participants ep1
      join event_participants ep2 on ep2.event_id = ep1.event_id and ep2.ensemble_id is not null
      where ep1.person_id = c.person_a_id
      intersect
      select distinct ep2.ensemble_id from event_participants ep1
      join event_participants ep2 on ep2.event_id = ep1.event_id and ep2.ensemble_id is not null
      where ep1.person_id = c.person_b_id) s)
  from c
  join persons pa on pa.id = c.person_a_id
  join persons pb on pb.id = c.person_b_id
  join card ca on ca.id = c.person_a_id
  join card cb on cb.id = c.person_b_id
  where is_admin_or_editor()
  order by 3 desc, c.created_at desc;
$$;
revoke all on function public.admin_person_duplicate_review() from public, anon;
grant execute on function public.admin_person_duplicate_review() to authenticated;

create or replace function public.admin_ensemble_duplicate_review()
returns table (candidate_id uuid, confidence int, same_kind boolean, created_at timestamptz, a jsonb, b jsonb)
language sql stable security definer set search_path = public as $$
  with c as (select c.* from ensemble_duplicate_candidates c where c.status = 'pending'),
  card as (
    select en.id, jsonb_build_object(
      'id', en.id, 'name', en.name, 'type', en.type, 'photo_url', en.photo_url, 'founded_year', en.founded_year,
      'wikidata_id', en.wikidata_id, 'description', left(en.description_de, 220), 'kind', ensemble_kind_signature(en.name),
      'events', (select count(*) from event_participants ep where ep.ensemble_id = en.id),
      'upcoming', (select count(*) from event_participants ep join events e on e.id = ep.event_id
                   where ep.ensemble_id = en.id and e.start_datetime >= now()),
      'followers', (select count(*) from user_favorite_ensembles f where f.ensemble_id = en.id)
    ) as data
    from ensembles en where en.id in (select ensemble_a_id from c union select ensemble_b_id from c)
  )
  select c.id,
    case
      when ea.wikidata_id is not null and ea.wikidata_id = eb.wikidata_id then 98
      when ensemble_core_key(ea.name) = ensemble_core_key(eb.name) then 90
      else round(coalesce(c.similarity_score, 0) * 80)::int
    end,
    ensemble_kind_signature(ea.name) = ensemble_kind_signature(eb.name),
    c.created_at, ca.data, cb.data
  from c
  join ensembles ea on ea.id = c.ensemble_a_id
  join ensembles eb on eb.id = c.ensemble_b_id
  join card ca on ca.id = c.ensemble_a_id
  join card cb on cb.id = c.ensemble_b_id
  where is_admin_or_editor()
  order by 2 desc, c.created_at desc;
$$;
revoke all on function public.admin_ensemble_duplicate_review() from public, anon;
grant execute on function public.admin_ensemble_duplicate_review() to authenticated;

notify pgrst, 'reload schema';
