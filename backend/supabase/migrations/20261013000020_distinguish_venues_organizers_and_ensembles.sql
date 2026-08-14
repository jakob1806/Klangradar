-- Spielstätten, veranstaltende Institutionen und auftretende Klangkörper
-- sind fachlich verschiedene Entitäten. Insbesondere dürfen die Bayerische
-- Staatsoper und das Staatstheater am Gärtnerplatz nicht als Mitwirkende
-- erscheinen; ihre Orchester/Chöre/Ballette dagegen schon.

insert into public.organizers (id, slug, name, description_de, website_url, contact_email)
values
  (
    'b1300000-0000-4000-8000-000000000001',
    'bayerische-staatsoper',
    'Bayerische Staatsoper',
    'Staatliches Dreispartenhaus für Oper, Ballett und Konzert. Spielstätten und auftretende Klangkörper werden separat geführt.',
    'https://www.staatsoper.de/',
    'besucher@staatsoper.de'
  ),
  (
    'b1300000-0000-4000-8000-000000000002',
    'staatstheater-am-gaertnerplatz',
    'Staatstheater am Gärtnerplatz',
    'Staatliches Musiktheater für Operette, Musical, Tanz und Oper. Das Orchester und die weiteren Sparten werden separat als Ensembles geführt.',
    'https://www.gaertnerplatztheater.de/',
    'info@gaertnerplatztheater.de'
  ),
  (
    'b1300000-0000-4000-8000-000000000003',
    'august-everding-stiftung',
    'August Everding Stiftung',
    'Stiftung zur Förderung der Bayerischen Theaterakademie August Everding.',
    'https://www.theaterakademie.de/',
    null
  ),
  (
    'b1300000-0000-4000-8000-000000000004',
    'junges-gaertnerplatztheater',
    'Junges Gärtnerplatztheater',
    'Vermittlungs- und Nachwuchsbereich des Staatstheaters am Gärtnerplatz; kein auftretendes Ensemble.',
    'https://www.gaertnerplatztheater.de/',
    null
  )
on conflict (slug) do update set
  name = excluded.name,
  description_de = excluded.description_de,
  website_url = excluded.website_url,
  contact_email = coalesce(public.organizers.contact_email, excluded.contact_email);

-- Der Sitz der Akademie ist das Prinzregententheater; der offizielle Name
-- der Institution enthält „Bayerische“, der Spielstättenname nicht.
update public.organizers
set name = 'Bayerische Theaterakademie August Everding',
    description_de = 'Staatliche Ausbildungsinstitution und Lehr- und Lerntheater mit Sitz im Münchner Prinzregententheater.',
    website_url = 'https://www.theaterakademie.de/'
where slug = 'theaterakademie-august-everding';

insert into public.entity_aliases (entity_type, entity_id, alias)
select 'organizer', id, 'Theaterakademie August Everding'
from public.organizers where slug = 'theaterakademie-august-everding'
on conflict do nothing;

-- Die offiziellen Quellen zielen auf die Institution. Ihre Termine behalten
-- unabhängig davon die konkrete Spielstätte (z.B. Nationaltheater oder
-- Prinzregententheater).
update public.sources
set venue_id = null,
    person_id = null,
    ensemble_id = null,
    organizer_id = (select id from public.organizers where slug = 'bayerische-staatsoper')
where type::text = 'staatsoper' or url ilike '%staatsoper.de/%';

update public.sources
set venue_id = null,
    person_id = null,
    ensemble_id = null,
    organizer_id = (select id from public.organizers where slug = 'staatstheater-am-gaertnerplatz')
where type::text = 'gaertnerplatz' or url ilike '%gaertnerplatztheater.de/%';

update public.sources
set venue_id = null,
    person_id = null,
    ensemble_id = null,
    organizer_id = (select id from public.organizers where slug = 'theaterakademie-august-everding')
where url ilike '%theaterakademie.de/%';

update public.events e
set organizer_id = (select id from public.organizers where slug = 'bayerische-staatsoper')
where e.organizer_id is null and (
  e.website_url ilike '%staatsoper.de/%'
  or exists (
    select 1 from public.sources s
    where s.id = e.source_id and (s.type::text = 'staatsoper' or s.url ilike '%staatsoper.de/%')
  )
);

update public.events e
set organizer_id = (select id from public.organizers where slug = 'staatstheater-am-gaertnerplatz')
where e.organizer_id is null and (
  e.website_url ilike '%gaertnerplatztheater.de/%'
  or exists (
    select 1 from public.sources s
    where s.id = e.source_id and (s.type::text = 'gaertnerplatz' or s.url ilike '%gaertnerplatztheater.de/%')
  )
);

update public.events e
set organizer_id = (select id from public.organizers where slug = 'theaterakademie-august-everding')
where e.organizer_id is null and e.website_url ilike '%theaterakademie.de/%';

-- Falsch als Mitwirkende verknüpfte Dachinstitutionen werden zu
-- Veranstaltern. Ihre echten Unterensembles bleiben unberührt.
update public.events e
set organizer_id = case
  when root.name = 'Bayerische Staatsoper'
    then (select id from public.organizers where slug = 'bayerische-staatsoper')
  when root.name = 'Staatstheater am Gärtnerplatz'
    then (select id from public.organizers where slug = 'staatstheater-am-gaertnerplatz')
  else e.organizer_id
end
from public.event_participants ep
join public.ensembles root on root.id = ep.ensemble_id and root.is_family_root
where ep.event_id = e.id and e.organizer_id is null
  and root.name in ('Bayerische Staatsoper', 'Staatstheater am Gärtnerplatz');

delete from public.event_participants ep
using public.ensembles root
where ep.ensemble_id = root.id and root.is_family_root;

-- Der importierte Datensatz „Opernschule“ ist keine zusätzliche Spielstätte,
-- sondern bezeichnet einen Ausbildungsbereich am selben Ort. Alle echten
-- Spielstättenbezüge werden auf das Prinzregententheater zusammengeführt.
do $$
declare
  wrong_venue_id uuid;
  prinzregententheater_id uuid;
  academy_id uuid;
begin
  select id into wrong_venue_id from public.venues
  where slug = 'theaterakademie-august-everding-opernschule' limit 1;
  select id into prinzregententheater_id from public.venues
  where slug = 'prinzregententheater' limit 1;
  select id into academy_id from public.organizers
  where slug = 'theaterakademie-august-everding' limit 1;

  if wrong_venue_id is not null and prinzregententheater_id is not null then
    update public.events set venue_id = prinzregententheater_id where venue_id = wrong_venue_id;
    update public.ensembles set home_venue_id = prinzregententheater_id where home_venue_id = wrong_venue_id;
    update public.sources
      set venue_id = null, organizer_id = academy_id
      where venue_id = wrong_venue_id;
    update public.entity_candidates set suggested_venue_id = prinzregententheater_id
      where suggested_venue_id = wrong_venue_id;
    update public.images set venue_id = prinzregententheater_id where venue_id = wrong_venue_id;

    delete from public.user_favorite_venues old_favorite
    where old_favorite.venue_id = wrong_venue_id
      and exists (
        select 1 from public.user_favorite_venues kept
        where kept.user_id = old_favorite.user_id
          and kept.venue_id = prinzregententheater_id
      );
    update public.user_favorite_venues set venue_id = prinzregententheater_id
      where venue_id = wrong_venue_id;

    -- Diese frühe MVP-Tabelle existiert nicht in jeder produktiven
    -- Installationshistorie; die aktuelle Favoritentabelle oben ist dagegen
    -- überall vorhanden. Darum nur migrieren, wenn sie tatsächlich existiert.
    if to_regclass('public.profile_interest_venues') is not null then
      execute $sql$
        delete from public.profile_interest_venues old_interest
        where old_interest.venue_id = $1
          and exists (
            select 1 from public.profile_interest_venues kept
            where kept.user_id = old_interest.user_id and kept.venue_id = $2
          )
      $sql$ using wrong_venue_id, prinzregententheater_id;
      execute 'update public.profile_interest_venues set venue_id = $1 where venue_id = $2'
        using prinzregententheater_id, wrong_venue_id;
    end if;

    -- Das vorhandene, redaktionell freigegebene Bild zeigt tatsächlich das
    -- Prinzregententheater und bleibt daher als zusätzliches Galeriebild erhalten.
    update public.images
      set origin_id = prinzregententheater_id, is_primary = false,
          sort_order = sort_order + 100
      where origin_type = 'venue' and origin_id = wrong_venue_id;

    delete from public.venue_duplicate_candidates
      where venue_a_id = wrong_venue_id or venue_b_id = wrong_venue_id;
    delete from public.entity_aliases duplicate_alias
      where duplicate_alias.entity_type = 'venue'
        and duplicate_alias.entity_id = wrong_venue_id
        and exists (
          select 1 from public.entity_aliases kept_alias
          where kept_alias.entity_type = 'venue'
            and kept_alias.entity_id = prinzregententheater_id
            and kept_alias.alias_normalized = duplicate_alias.alias_normalized
        );
    update public.entity_aliases set entity_id = prinzregententheater_id
      where entity_type = 'venue' and entity_id = wrong_venue_id;
    insert into public.entity_aliases(entity_type, entity_id, alias)
      values ('venue', prinzregententheater_id, 'Theaterakademie August Everding – Opernschule')
      on conflict do nothing;
    delete from public.venues where id = wrong_venue_id;
  end if;
end;
$$;

-- Zwei Organisations-/Bereichsnamen waren als Ensemble importiert worden.
-- Verweise werden auf die entsprechenden Organizer umgebogen; das unpassende
-- Stiftungsbild wird nicht in die Organizer-Galerie übernommen.
do $$
declare
  item record;
  target_organizer_id uuid;
begin
  for item in
    select e.id, e.name,
      case e.slug
        when 'august-everding-stiftung' then 'august-everding-stiftung'
        when 'junges-gaertnerplatztheater' then 'junges-gaertnerplatztheater'
      end as organizer_slug
    from public.ensembles e
    where e.slug in ('august-everding-stiftung', 'junges-gaertnerplatztheater')
  loop
    select id into target_organizer_id from public.organizers
      where slug = item.organizer_slug limit 1;

    update public.events e set organizer_id = target_organizer_id
      where e.organizer_id is null and exists (
        select 1 from public.event_participants ep
        where ep.event_id = e.id and ep.ensemble_id = item.id
      );
    delete from public.event_participants where ensemble_id = item.id;
    update public.sources
      set ensemble_id = null, organizer_id = target_organizer_id
      where ensemble_id = item.id;
    update public.entity_candidates
      set created_ensemble_id = null,
          created_organizer_id = coalesce(created_organizer_id, target_organizer_id),
          status = case when status = 'pending' then 'approved' else status end
      where created_ensemble_id = item.id;
    update public.persons set member_of_ensemble_id = null where member_of_ensemble_id = item.id;
    update public.ensembles set parent_ensemble_id = null where parent_ensemble_id = item.id;
    delete from public.user_favorite_ensembles where ensemble_id = item.id;
    delete from public.ensemble_duplicate_candidates
      where ensemble_a_id = item.id or ensemble_b_id = item.id;

    if item.organizer_slug = 'august-everding-stiftung' then
      delete from public.images where origin_type = 'ensemble' and origin_id = item.id;
    else
      update public.images
        set origin_type = 'organizer', origin_id = target_organizer_id
        where origin_type = 'ensemble' and origin_id = item.id;
    end if;

    insert into public.entity_aliases(entity_type, entity_id, alias)
      select 'organizer', target_organizer_id, item.name
      where not exists (
        select 1 from public.organizers target
        where target.id = target_organizer_id
          and public.normalize_entity_name(target.name) = public.normalize_entity_name(item.name)
      )
      on conflict do nothing;
    delete from public.ensembles where id = item.id;
  end loop;
end;
$$;

-- Korrektur eines grammatisch beschädigten Imports nach der offiziellen
-- Staatsoper-Bezeichnung. Der alte Text bleibt über den Alias-Trigger suchbar.
update public.ensembles
set name = 'ATTACCA – Jugendorchester des Bayerischen Staatsorchesters',
    slug = 'attacca-jugendorchester-des-bayerischen-staatsorchesters',
    type = 'orchester',
    family_role = 'orchestra',
    description_de = 'ATTACCA ist das eigenständige Jugendprojekt des Bayerischen Staatsorchesters und richtet sich an junge Musikerinnen und Musiker.',
    website_url = 'https://www.staatsoper.de/biographien/attacca-jugendorchester-des-bayerischen-staatsorchesters',
    is_verified = true
where slug = 'attacca-dem-jugendorchester-der-bayerischen-staatsoper';

insert into public.entity_aliases(entity_type, entity_id, alias)
select 'ensemble', id, alias_name
from public.ensembles
cross join (values ('ATTACCA Jugendorchester'), ('Jugendorchester ATTACCA')) aliases(alias_name)
where slug = 'attacca-jugendorchester-des-bayerischen-staatsorchesters'
on conflict do nothing;

-- Institutionsnamen und nicht auftretende Bereiche werden vom Resolver
-- bewusst ignoriert. Die manuelle Pflege der Regeln im Familienportal bleibt
-- vollständig erhalten.
insert into public.ensemble_resolution_rules(input_name, action, note)
values
  ('Bayerische Staatsoper', 'ignore', 'Veranstaltende Institution, kein auftretendes Ensemble'),
  ('Staatstheater am Gärtnerplatz', 'ignore', 'Veranstaltende Institution bzw. Spielstätte, kein auftretendes Ensemble'),
  ('Bayerische Theaterakademie August Everding', 'ignore', 'Ausbildungsinstitution, kein auftretendes Ensemble'),
  ('Theaterakademie August Everding', 'ignore', 'Ausbildungsinstitution, kein auftretendes Ensemble'),
  ('August Everding Stiftung', 'ignore', 'Stiftung, kein auftretendes Ensemble'),
  ('Junges Gärtnerplatztheater', 'ignore', 'Vermittlungsbereich, kein auftretendes Ensemble')
on conflict (input_normalized) do update
set action = excluded.action, note = excluded.note, family_root_id = null;

-- Familienwurzeln sind technische Dachdatensätze: exakte Treffer werden
-- ignoriert, Untergruppen werden weiterhin automatisch aufgelöst.
create or replace function public.resolve_ensemble_entities(p_name text)
returns table(id uuid,name text,resolution text)
language plpgsql stable security invoker as $$
declare n text:=normalize_ensemble_resolution_name(p_name); r ensemble_resolution_rules%rowtype; match_count int; root_id uuid;
begin
  if exists (
    select 1 from ensembles e
    where e.is_family_root and (
      normalize_ensemble_resolution_name(e.name)=n
      or exists (
        select 1 from entity_aliases a
        where a.entity_type='ensemble' and a.entity_id=e.id
          and normalize_ensemble_resolution_name(a.alias)=n
      )
    )
  ) then
    return query select null::uuid,p_name,'ignore'::text;
    return;
  end if;

  select * into r from ensemble_resolution_rules where input_normalized=n limit 1;
  if found then
    if r.action='ignore' then return query select null::uuid,p_name,'ignore'::text; return; end if;
    return query select e.id,e.name,'rule'::text from ensemble_resolution_rule_targets t join ensembles e on e.id=t.ensemble_id where t.rule_id=r.id order by t.display_order,e.name;
    return;
  end if;

  return query
    select e.id,e.name,'canonical'::text from ensembles e where normalize_ensemble_resolution_name(e.name)=n and not e.is_resolution_placeholder and not e.is_family_root
    union all
    select e.id,e.name,'alias' from entity_aliases a join ensembles e on e.id=a.entity_id where a.entity_type='ensemble' and normalize_ensemble_resolution_name(a.alias)=n and not e.is_resolution_placeholder and not e.is_family_root
    limit 1;
  get diagnostics match_count=row_count;
  if match_count>0 then return; end if;

  if n ~ 'kammerorchester des symphonieorchesters des bayerischen rundfunks' then
    select e.id into root_id from ensembles e where normalize_ensemble_resolution_name(e.name)='symphonieorchester des bayerischen rundfunks' limit 1;
  else
    root_id := detect_ensemble_family_root(p_name);
  end if;
  if root_id is not null and n ~ 'solistinnen und solisten|solisten und solistinnen' then
    return query select null::uuid,p_name,'ignore'::text; return;
  end if;
  if root_id is not null then
    return query
      with requested(role,ord) as (
        select 'orchestra',0 where n ~ 'orchester|musikerinnen und musiker'
        union all select 'choir',1 where regexp_replace(n,'kinderchor|extrachor|zusatzchor','','g') ~ 'chor'
        union all select 'childrens_choir',2 where n ~ 'kinderchor'
        union all select 'extra_choir',3 where n ~ 'extrachor|zusatzchor'
        union all select 'ballet',4 where n ~ 'ballett'
        union all select 'opera_studio',5 where n ~ 'opernstudio'
        union all select 'statisterie',6 where regexp_replace(n,'kinderstatisterie','','g') ~ 'statisterie'
        union all select 'child_statisterie',7 where n ~ 'kinderstatisterie'
      ), candidates as (
        select q.role,q.ord,e.id,e.name
        from requested q join ensembles e on e.parent_ensemble_id=root_id and e.family_role=q.role
        where not e.is_resolution_placeholder and not e.is_family_root
      )
      select c.id,c.name,'family'::text from candidates c
      where not exists(
        select 1 from requested q
        where (select count(*) from candidates same_role where same_role.role=q.role)<>1
      )
      order by c.ord,c.name;
    get diagnostics match_count=row_count;
    if match_count>0 then return; end if;
    if ensemble_component_count(p_name)>0 then
      return query select null::uuid,p_name,'ambiguous'::text;
      return;
    end if;
  end if;
  return query select m.id,m.name,'fuzzy'::text from find_matching_ensemble(p_name,0.85,1) m where m.similarity>=0.85;
end;
$$;

create or replace function public.find_matching_ensemble(
  p_name text,p_similarity_threshold numeric default 0.5,p_result_limit int default 3
)
returns table(id uuid,name text,similarity numeric) language sql stable as $$
  select e.id,e.name,greatest(
    similarity(e.name,p_name),
    case when normalize_entity_name(e.name)=normalize_entity_name(p_name) then 1 else 0 end,
    coalesce((select max(case when a.alias_normalized=normalize_entity_name(p_name) then 1 else similarity(a.alias,p_name) end) from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id),0)
  )::numeric
  from ensembles e
  where not e.is_resolution_placeholder and not e.is_family_root and (
    greatest(similarity(e.name,p_name),coalesce((select max(similarity(a.alias,p_name)) from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id),0))>=p_similarity_threshold
    or normalize_entity_name(e.name)=normalize_entity_name(p_name)
    or exists(select 1 from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id and a.alias_normalized=normalize_entity_name(p_name))
  ) order by 3 desc,length(e.name) desc limit p_result_limit;
$$;

-- Zusätzliche Sicherung für Schreibpfade, die den Resolver versehentlich
-- umgehen: eine Dachinstitution wird niemals als Event-Mitwirkende gespeichert.
create or replace function public.skip_family_root_event_participant()
returns trigger language plpgsql as $$
begin
  if new.ensemble_id is not null and exists (
    select 1 from public.ensembles e where e.id = new.ensemble_id and e.is_family_root
  ) then
    return null;
  end if;
  return new;
end;
$$;
drop trigger if exists skip_family_root_event_participant_trigger on public.event_participants;
create trigger skip_family_root_event_participant_trigger
before insert or update of ensemble_id on public.event_participants
for each row execute function public.skip_family_root_event_participant();

-- Die globale Suche findet Veranstaltungen weiterhin über ihren Veranstalter,
-- zeigt die Institution selbst aber nicht fälschlich als Ensembletreffer an.
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
        coalesce(similarity(o.name, pattern.raw),0),
        coalesce((select max(similarity(va.alias, pattern.raw)) from entity_aliases va where va.entity_type='venue' and va.entity_id=v.id),0),
        coalesce((select max(similarity(oa.alias, pattern.raw)) from entity_aliases oa where oa.entity_type='organizer' and oa.entity_id=o.id),0),
        coalesce((select max(greatest(similarity(w.title, pattern.raw), coalesce(similarity(wa.alias, pattern.raw), 0))) from event_works ew join works w on w.id=ew.work_id left join entity_aliases wa on wa.entity_type='work' and wa.entity_id=w.id where ew.event_id=e.id),0),
        coalesce((select max(greatest(similarity(p.full_name, pattern.raw), coalesce(similarity(pa.alias, pattern.raw),0))) from event_works ew join works w on w.id=ew.work_id join persons p on p.id=w.composer_id left join entity_aliases pa on pa.entity_type='person' and pa.entity_id=p.id where ew.event_id=e.id),0),
        coalesce((select max(greatest(coalesce(similarity(pp.full_name, pattern.raw),0),coalesce(similarity(en.name, pattern.raw),0),coalesce(similarity(a.alias, pattern.raw),0))) from event_participants ep left join persons pp on pp.id=ep.person_id left join ensembles en on en.id=ep.ensemble_id left join entity_aliases a on (a.entity_type='person' and a.entity_id=pp.id) or (a.entity_type='ensemble' and a.entity_id=en.id) where ep.event_id=e.id),0)
      )::real,
      null::text, e.start_datetime, e.price_min, e.is_free
    from events e
    join venues v on v.id=e.venue_id
    left join organizers o on o.id=e.organizer_id
    cross join pattern
    where e.status != 'draft' and (
      e.title ilike pattern.p or e.subtitle ilike pattern.p
      or v.name ilike pattern.p or o.name ilike pattern.p
      or exists(select 1 from entity_aliases va where va.entity_type='venue' and va.entity_id=v.id and va.alias ilike pattern.p)
      or exists(select 1 from entity_aliases oa where oa.entity_type='organizer' and oa.entity_id=o.id and oa.alias ilike pattern.p)
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
    from ensembles e cross join pattern
    where not e.is_resolution_placeholder and not e.is_family_root
      and (e.name ilike pattern.p or exists(select 1 from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id and a.alias ilike pattern.p))
    order by 6 desc limit result_limit
  ) union all (
    select 'venue',v.id,v.slug,v.name,v.address_city,greatest(similarity(v.name,pattern.raw),coalesce((select max(similarity(a.alias,pattern.raw)) from entity_aliases a where a.entity_type='venue' and a.entity_id=v.id),0))::real,v.photo_url,null::timestamptz,null::numeric,null::boolean
    from venues v cross join pattern where v.name ilike pattern.p or exists(select 1 from entity_aliases a where a.entity_type='venue' and a.entity_id=v.id and a.alias ilike pattern.p) order by 6 desc limit result_limit
  ) union all (
    select 'work',w.id,null::text,w.title,p.full_name,greatest(similarity(w.title,pattern.raw),coalesce((select max(similarity(a.alias,pattern.raw)) from entity_aliases a where a.entity_type='work' and a.entity_id=w.id),0))::real,null::text,null::timestamptz,null::numeric,null::boolean
    from works w left join persons p on p.id=w.composer_id cross join pattern where w.title ilike pattern.p or exists(select 1 from entity_aliases a where a.entity_type='work' and a.entity_id=w.id and a.alias ilike pattern.p) order by 6 desc limit result_limit
  ) order by 6 desc;
$$;

grant execute on function public.resolve_ensemble_entities(text) to anon,authenticated,service_role;
grant execute on function public.find_matching_ensemble(text,numeric,int) to anon,authenticated,service_role;
grant execute on function public.search_all(text, int) to anon,authenticated;
