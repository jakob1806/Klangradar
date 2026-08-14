-- Ensemblefamilien unterscheiden echte Untergruppen eines Hauses von
-- Schreibvarianten und von Sammelangaben, die mehrere Gruppen meinen.

alter table public.ensembles add column if not exists family_role text;
alter table public.ensembles add column if not exists is_family_root boolean not null default false;
alter table public.ensembles add column if not exists is_resolution_placeholder boolean not null default false;
alter table public.ensembles drop constraint if exists ensembles_family_role_check;
alter table public.ensembles add constraint ensembles_family_role_check check (family_role is null or family_role in (
  'institution','orchestra','choir','childrens_choir','extra_choir','ballet','opera_studio','statisterie','child_statisterie','other'
));
create index if not exists ensembles_family_role_idx on public.ensembles(parent_ensemble_id, family_role);

create or replace function public.normalize_ensemble_resolution_name(p_value text)
returns text language sql immutable parallel safe as $$
  select trim(regexp_replace(
    translate(
      replace(replace(replace(replace(lower(coalesce(p_value,'')), 'ä','ae'), 'ö','oe'), 'ü','ue'), 'ß','ss'),
      'áàâéèêíìîóòôúùûçñ', 'aaaeeeiiiooouuucn'
    ),
    '[^a-z0-9]+', ' ', 'g'
  ));
$$;

-- Die drei Häuser als nicht auftretende Wurzel der Ensemblefamilie. Bereits
-- vorhandene Datensätze werden wiederverwendet.
insert into public.ensembles(slug,name,type,is_verified,is_family_root,family_role)
select 'staatstheater-am-gaertnerplatz-ensemblefamilie','Staatstheater am Gärtnerplatz','sonstiges',true,true,'institution'
where not exists(select 1 from ensembles where normalize_ensemble_resolution_name(name) in ('staatstheater am gaertnerplatz','staatstheater am gartnerplatz'));
insert into public.ensembles(slug,name,type,is_verified,is_family_root,family_role)
select 'bayerische-staatsoper-ensemblefamilie','Bayerische Staatsoper','sonstiges',true,true,'institution'
where not exists(select 1 from ensembles where normalize_ensemble_resolution_name(name)='bayerische staatsoper');
insert into public.ensembles(slug,name,type,is_verified,is_family_root,family_role)
select 'bayerischer-rundfunk-ensemblefamilie','Bayerischer Rundfunk','sonstiges',true,true,'institution'
where not exists(select 1 from ensembles where normalize_ensemble_resolution_name(name)='bayerischer rundfunk');

update ensembles set is_family_root=true,family_role='institution'
where normalize_ensemble_resolution_name(name) in ('staatstheater am gaertnerplatz','staatstheater am gartnerplatz','bayerische staatsoper','bayerischer rundfunk');

create or replace function public.ensemble_role_from_name(p_name text)
returns text language plpgsql immutable as $$
declare n text := normalize_ensemble_resolution_name(p_name);
begin
  if n ~ 'kinderchor' then return 'childrens_choir'; end if;
  if n ~ 'extrachor|zusatzchor' then return 'extra_choir'; end if;
  if n ~ 'chor' then return 'choir'; end if;
  if n ~ 'orchester|musikerinnen und musiker' then return 'orchestra'; end if;
  if n ~ 'ballett' then return 'ballet'; end if;
  if n ~ 'opernstudio' then return 'opera_studio'; end if;
  if n ~ 'kinderstatisterie' then return 'child_statisterie'; end if;
  if n ~ 'statisterie' then return 'statisterie'; end if;
  return 'other';
end;
$$;

-- Reduziert einen Namen auf die Merkmale des Hauses. Rollenbegriffe und
-- grammatische Varianten werden entfernt/vereinheitlicht, damit z.B.
-- „Bayerischer Staatsopernchor“ automatisch zur „Bayerischen Staatsoper“
-- und Gärtnerplatz-Schreibweisen zum selben Haus finden.
create or replace function public.ensemble_family_fingerprint(p_name text)
returns text language sql immutable parallel safe as $$
  select trim(regexp_replace(
    regexp_replace(
      regexp_replace(replace(replace(replace(replace(replace(replace(
        normalize_ensemble_resolution_name(p_name),
        'bayerischen','bayerische'),'bayerischer','bayerische'),'bayerisches','bayerische'),
        'staatstheaters','staatstheater'),'staatsopern','staatsoper'),'rundfunkorchester','rundfunk'),
        '(^| )br( |$)', ' bayerische rundfunk ', 'g'),
      '(^| )(kammerorchester|orchester|orchesters|chor|chores|kinderchor|extrachor|zusatzchor|ballett|opernstudio|statisterie|kinderstatisterie|ensemble|musikerinnen|musiker|mitglieder)( |$)',
      ' ', 'g'
    ), '\s+', ' ', 'g'
  ));
$$;

-- Nutzt alle expliziten Familienwurzeln sowie bestehende „Gehört zu“-Bäume
-- als Lernbasis. Neue Häuser benötigen dadurch keine neue fest codierte
-- IF-Abfrage: Sobald eine Dachorganisation oder Elternbeziehung existiert,
-- werden weitere offizielle Schreibweisen automatisch derselben Familie
-- zugeordnet. Die Mindestschwelle verhindert Zuordnungen nur aufgrund von
-- Wörtern wie „Chor“ oder „Orchester“.
create or replace function public.detect_ensemble_family_root(p_name text,p_exclude_id uuid default null)
returns uuid language sql stable as $$
  with input as (
    select ensemble_family_fingerprint(p_name) as fingerprint
  ), roots as (
    select e.id,e.name,ensemble_family_fingerprint(e.name) as fingerprint
    from ensembles e
    where e.id is distinct from p_exclude_id
      and (e.is_family_root
       or exists(select 1 from ensembles child where child.parent_ensemble_id=e.id))
  ), scored as (
    select r.id,
      case
        when length(i.fingerprint)>=6 and (i.fingerprint like '%'||r.fingerprint||'%' or r.fingerprint like '%'||i.fingerprint||'%') then 1.0+least(length(r.fingerprint),100)::numeric/1000
        when exists(
          select 1 from regexp_split_to_table(i.fingerprint,' ') token
          where length(token)>=7 and token=any(regexp_split_to_array(r.fingerprint,' '))
        ) then greatest(similarity(i.fingerprint,r.fingerprint),word_similarity(i.fingerprint,r.fingerprint))+0.22
        else greatest(similarity(i.fingerprint,r.fingerprint),word_similarity(i.fingerprint,r.fingerprint))
      end as score
    from roots r cross join input i
    where i.fingerprint<>'' and r.fingerprint<>''
  )
  select id from scored where score>=0.58 order by score desc,id limit 1;
$$;

create or replace function public.assign_ensemble_family()
returns trigger language plpgsql security definer set search_path=public as $$
declare n text := normalize_ensemble_resolution_name(new.name); root_id uuid;
begin
  if new.is_family_root or n in ('staatstheater am gaertnerplatz','staatstheater am gartnerplatz','bayerische staatsoper','bayerischer rundfunk') then
    new.is_family_root := true; new.family_role := 'institution'; new.parent_ensemble_id := null; return new;
  end if;
  if n ~ 'kammerorchester des symphonieorchesters des bayerischen rundfunks' then
    select id into root_id from ensembles where normalize_ensemble_resolution_name(name)='symphonieorchester des bayerischen rundfunks' limit 1;
  else
    root_id := detect_ensemble_family_root(new.name,new.id);
  end if;
  if root_id is not null and new.parent_ensemble_id is null then new.parent_ensemble_id := root_id; end if;
  if root_id is not null and (new.family_role is null or new.family_role='other') then new.family_role := ensemble_role_from_name(new.name); end if;
  return new;
end;
$$;

create or replace function public.ensemble_component_count(p_name text)
returns int language plpgsql immutable as $$
declare n text:=normalize_ensemble_resolution_name(p_name); amount int:=0; without_specific text;
begin
  if n ~ 'orchester|musikerinnen und musiker' then amount:=amount+1; end if;
  if n ~ 'kinderchor' then amount:=amount+1; end if;
  if n ~ 'extrachor|zusatzchor' then amount:=amount+1; end if;
  without_specific:=regexp_replace(n,'kinderchor|extrachor|zusatzchor|kinderstatisterie','','g');
  if without_specific ~ 'chor' then amount:=amount+1; end if;
  if n ~ 'ballett' then amount:=amount+1; end if;
  if n ~ 'opernstudio' then amount:=amount+1; end if;
  if n ~ 'kinderstatisterie' then amount:=amount+1; end if;
  if without_specific ~ 'statisterie' then amount:=amount+1; end if;
  return amount;
end;
$$;

drop trigger if exists assign_ensemble_family_trigger on public.ensembles;
create trigger assign_ensemble_family_trigger before insert or update of name,parent_ensemble_id on public.ensembles
for each row execute function public.assign_ensemble_family();

-- Bestehende Zeilen einmal automatisch einordnen.
update public.ensembles set name=name where not is_family_root;

create or replace function public.ensemble_identity_key(p_name text)
returns text language sql immutable parallel safe as $$
  select replace(replace(replace(normalize_ensemble_resolution_name(p_name),'ae','a'),'oe','o'),'ue','u');
$$;

-- Nur wirklich identische Namensvarianten innerhalb derselben Familie
-- automatisch konsolidieren (z.B. Münchner/Munchner Rundfunkorchester oder
-- doppelt angelegter Kinderchor). Unterschiedliche family_role-Werte werden
-- ausdrücklich niemals zusammengeführt.
create or replace function public.consolidate_exact_ensemble_duplicates()
returns int language plpgsql security definer set search_path=public as $$
declare item record; merged int:=0;
begin
  for item in
    with ranked as (
      select e.id,e.name,e.parent_ensemble_id,e.family_role,
        first_value(e.id) over(partition by e.parent_ensemble_id,e.family_role,ensemble_identity_key(e.name) order by e.is_verified desc,(e.type::text<>'sonstiges') desc,(e.description_de is not null) desc,(select count(*) from event_participants ep where ep.ensemble_id=e.id) desc,e.created_at,e.id) as keep_id,
        row_number() over(partition by e.parent_ensemble_id,e.family_role,ensemble_identity_key(e.name) order by e.is_verified desc,(e.type::text<>'sonstiges') desc,(e.description_de is not null) desc,(select count(*) from event_participants ep where ep.ensemble_id=e.id) desc,e.created_at,e.id) as rn
      from ensembles e where not e.is_family_root and not e.is_resolution_placeholder and e.parent_ensemble_id is not null
    ) select * from ranked where rn>1
  loop
    delete from event_participants old_link where old_link.ensemble_id=item.id and exists(select 1 from event_participants keep_link where keep_link.event_id=old_link.event_id and keep_link.ensemble_id=item.keep_id);
    update event_participants set ensemble_id=item.keep_id where ensemble_id=item.id;
    delete from user_favorite_ensembles old_favorite where old_favorite.ensemble_id=item.id and exists(select 1 from user_favorite_ensembles keep_favorite where keep_favorite.user_id=old_favorite.user_id and keep_favorite.ensemble_id=item.keep_id);
    update user_favorite_ensembles set ensemble_id=item.keep_id where ensemble_id=item.id;
    update sources set ensemble_id=item.keep_id where ensemble_id=item.id;
    update entity_candidates set created_ensemble_id=item.keep_id where created_ensemble_id=item.id;
    update ensembles set parent_ensemble_id=item.keep_id where parent_ensemble_id=item.id;
    update persons set member_of_ensemble_id=item.keep_id where member_of_ensemble_id=item.id;
    update images set origin_id=item.keep_id where origin_type='ensemble' and origin_id=item.id;
    delete from ensemble_duplicate_candidates where ensemble_a_id=item.id or ensemble_b_id=item.id;
    if normalize_entity_name(item.name)<>(select normalize_entity_name(name) from ensembles where id=item.keep_id) then
      insert into entity_aliases(entity_type,entity_id,alias) values('ensemble',item.keep_id,item.name) on conflict do nothing;
    end if;
    delete from ensembles where id=item.id;
    merged:=merged+1;
  end loop;
  return merged;
end;
$$;

select public.consolidate_exact_ensemble_duplicates();

create table if not exists public.ensemble_resolution_rules(
  id uuid primary key default gen_random_uuid(),
  family_root_id uuid references ensembles(id) on delete cascade,
  input_name text not null,
  input_normalized text generated always as (normalize_ensemble_resolution_name(input_name)) stored,
  action text not null default 'expand' check(action in ('expand','ignore')),
  note text,
  created_at timestamptz not null default now(),
  unique(input_normalized)
);
alter table public.ensemble_resolution_rules add column if not exists family_root_id uuid references ensembles(id) on delete cascade;
create table if not exists public.ensemble_resolution_rule_targets(
  rule_id uuid not null references ensemble_resolution_rules(id) on delete cascade,
  ensemble_id uuid not null references ensembles(id) on delete cascade,
  display_order int not null default 0,
  primary key(rule_id,ensemble_id)
);
alter table public.ensemble_resolution_rules enable row level security;
alter table public.ensemble_resolution_rule_targets enable row level security;
create policy "Ensemble-Auflösungsregeln sind lesbar" on public.ensemble_resolution_rules for select using(true);
create policy "Redaktion verwaltet Ensemble-Auflösungsregeln" on public.ensemble_resolution_rules for all using(is_admin_or_editor()) with check(is_admin_or_editor());
create policy "Ensemble-Auflösungsziele sind lesbar" on public.ensemble_resolution_rule_targets for select using(true);
create policy "Redaktion verwaltet Ensemble-Auflösungsziele" on public.ensemble_resolution_rule_targets for all using(is_admin_or_editor()) with check(is_admin_or_editor());

-- Bekannte Sammel-/Umschreibungen aus den offiziellen Besetzungslisten.
insert into ensemble_resolution_rules(input_name,action,note) values
 ('Chor und Kinderchor des Staatstheaters am Gärtnerplatz','expand','Chor und Kinderchor getrennt verknüpfen'),
 ('Kinderchor und Statisterie des Staatstheaters am Gärtnerplatz','expand','Kinderchor und Statisterie getrennt verknüpfen'),
 ('Chor und Kinderchor und Statisterie des Staatstheaters am Gärtnerplatz','expand','Drei Untergruppen getrennt verknüpfen'),
 ('Chor und Statisterie des Staatstheaters am Gärtnerplatz','expand','Chor und Statisterie getrennt verknüpfen'),
 ('Musikerinnen und Musiker des Staatstheaters am Gärtnerplatz','expand','Umschreibung des Hausorchesters'),
 ('Musikerinnen und Musiker des Orchesters des Staatstheaters am Gärtnerplatz','expand','Umschreibung des Hausorchesters'),
 ('Solistinnen und Solisten des Staatstheaters am Gärtnerplatz','ignore','Wechselnde Besetzung, kein stabiles Ensemble'),
 ('Solistinnen und Solisten des Staatstheaters am Gartnerplatz','ignore','Wechselnde Besetzung, kein stabiles Ensemble')
on conflict(input_normalized) do update set action=excluded.action,note=excluded.note;

-- Alle bereits vorhandenen und künftigen erkennbaren Sammelzeilen werden
-- datengetrieben zu Regeln, statt einzeln in Quellcode gepflegt zu werden.
insert into ensemble_resolution_rules(input_name,action,note)
select e.name,
  case when normalize_ensemble_resolution_name(e.name) ~ 'solistinnen und solisten|solisten und solistinnen' then 'ignore' else 'expand' end,
  'Automatisch aus Ensemblefamilie und Komponenten erkannt'
from ensembles e
where e.parent_ensemble_id is not null and (
  ensemble_component_count(e.name)>1
  or normalize_ensemble_resolution_name(e.name) ~ 'musikerinnen und musiker|mitglieder?n? des opernstudios|solistinnen und solisten|solisten und solistinnen'
)
on conflict(input_normalized) do update set action=excluded.action,note=excluded.note;

-- Die Familie wird zusätzlich direkt an der Regel gespeichert. Das macht
-- Regeln im Admin-Portal bearbeitbar, auch wenn für eine künftig neu erfasste
-- Sammelbezeichnung noch kein technischer Platzhalter-Datensatz existiert.
update ensemble_resolution_rules r set family_root_id=placeholder.parent_ensemble_id
from ensembles placeholder
where normalize_ensemble_resolution_name(placeholder.name)=r.input_normalized
  and placeholder.parent_ensemble_id is not null
  and r.family_root_id is distinct from placeholder.parent_ensemble_id;

-- Zielrollen der expand-Regeln automatisch aus dem Text ableiten. Dadurch
-- funktionieren sie auch, wenn die kanonische Untergruppe später umbenannt wird.
insert into ensemble_resolution_rule_targets(rule_id,ensemble_id,display_order)
select r.id,e.id,
  case e.family_role when 'orchestra' then 0 when 'choir' then 1 when 'childrens_choir' then 2 when 'extra_choir' then 3 when 'ballet' then 4 when 'opera_studio' then 5 when 'statisterie' then 6 when 'child_statisterie' then 7 else 9 end
from ensemble_resolution_rules r
join ensembles placeholder on normalize_ensemble_resolution_name(placeholder.name)=r.input_normalized and placeholder.parent_ensemble_id is not null
join ensembles e on e.parent_ensemble_id=placeholder.parent_ensemble_id and e.id<>placeholder.id
where r.action='expand'
and not exists(select 1 from ensemble_resolution_rules placeholder_rule where placeholder_rule.input_normalized=normalize_ensemble_resolution_name(e.name))
and (
  (r.input_normalized ~ 'musikerinnen und musiker' and e.family_role='orchestra')
  or (regexp_replace(r.input_normalized,'kinderchor|extrachor|zusatzchor','','g') ~ 'chor' and e.family_role='choir')
  or (r.input_normalized ~ 'kinderchor' and e.family_role='childrens_choir')
  or (r.input_normalized ~ 'extrachor|zusatzchor' and e.family_role='extra_choir')
  or (r.input_normalized ~ 'ballett' and e.family_role='ballet')
  or (r.input_normalized ~ 'opernstudio' and e.family_role='opera_studio')
  or (r.input_normalized ~ 'kinderstatisterie' and e.family_role='child_statisterie')
  or (regexp_replace(r.input_normalized,'kinderstatisterie','','g') ~ 'statisterie' and e.family_role='statisterie')
) on conflict do nothing;

-- Alte Sammelzeilen bleiben zu Revisionszwecken in den Stammdaten sichtbar,
-- erscheinen aber nicht mehr in öffentlichen Verzeichnissen oder Matchern.
update ensembles e set is_resolution_placeholder=true
where exists(select 1 from ensemble_resolution_rules r where r.input_normalized=normalize_ensemble_resolution_name(e.name));

drop policy if exists "Öffentlich lesbar" on public.ensembles;
create policy "Öffentlich lesbar" on public.ensembles for select
using(not is_resolution_placeholder or is_admin_or_editor());

-- Bestehende Veranstaltungs- und Favoritenverknüpfungen von vollständigen
-- Sammelregeln auf alle stabilen Ziel-Unterensembles auffächern.
with complete_rules as (
  select r.id,r.input_normalized
  from ensemble_resolution_rules r
  where r.action='expand' and exists(select 1 from ensemble_resolution_rule_targets t where t.rule_id=r.id)
), placeholder_links as (
  select e.id as placeholder_id,cr.id as rule_id
  from complete_rules cr join ensembles e on normalize_ensemble_resolution_name(e.name)=cr.input_normalized
  where e.is_resolution_placeholder
)
insert into event_participants(event_id,ensemble_id,role,role_label,display_order)
select distinct ep.event_id,t.ensemble_id,ep.role,ep.role_label,ep.display_order+t.display_order
from placeholder_links pl join event_participants ep on ep.ensemble_id=pl.placeholder_id
join ensemble_resolution_rule_targets t on t.rule_id=pl.rule_id
where not exists(select 1 from event_participants already where already.event_id=ep.event_id and already.ensemble_id=t.ensemble_id)
on conflict do nothing;

with placeholder_links as (
  select e.id as placeholder_id
  from ensemble_resolution_rules r join ensembles e on normalize_ensemble_resolution_name(e.name)=r.input_normalized
  where r.action='expand' and e.is_resolution_placeholder and exists(select 1 from ensemble_resolution_rule_targets t where t.rule_id=r.id)
)
delete from event_participants ep using placeholder_links pl where ep.ensemble_id=pl.placeholder_id;

with placeholder_targets as (
  select e.id as placeholder_id,t.ensemble_id
  from ensemble_resolution_rules r join ensembles e on normalize_ensemble_resolution_name(e.name)=r.input_normalized
  join ensemble_resolution_rule_targets t on t.rule_id=r.id
  where r.action='expand' and e.is_resolution_placeholder
)
insert into user_favorite_ensembles(user_id,ensemble_id)
select distinct f.user_id,pt.ensemble_id from user_favorite_ensembles f join placeholder_targets pt on pt.placeholder_id=f.ensemble_id
on conflict do nothing;

delete from user_favorite_ensembles f using ensembles e
where f.ensemble_id=e.id and e.is_resolution_placeholder;

-- Reine Sammelbezeichnungen wie „Solistinnen und Solisten des Hauses“ sind
-- kein stabiles Ensemble und werden ohne Ersatz aus strukturierten
-- Verknüpfungen entfernt; die konkreten Einzelpersonen bleiben erhalten.
delete from event_participants ep using ensembles e,ensemble_resolution_rules r
where ep.ensemble_id=e.id and e.is_resolution_placeholder
  and r.action='ignore' and r.input_normalized=normalize_ensemble_resolution_name(e.name);

create or replace function public.resolve_ensemble_entities(p_name text)
returns table(id uuid,name text,resolution text)
language plpgsql stable security invoker as $$
declare n text:=normalize_ensemble_resolution_name(p_name); r ensemble_resolution_rules%rowtype; match_count int; root_id uuid;
begin
  select * into r from ensemble_resolution_rules where input_normalized=n limit 1;
  if found then
    if r.action='ignore' then return query select null::uuid,p_name,'ignore'::text; return; end if;
    return query select e.id,e.name,'rule'::text from ensemble_resolution_rule_targets t join ensembles e on e.id=t.ensemble_id where t.rule_id=r.id order by t.display_order,e.name;
    return;
  end if;

  -- Ein exakter Hauptname oder Alias hat Vorrang vor der Familienlogik. Das
  -- ist beim BR wichtig, weil dort mehrere verschiedene Orchester zur selben
  -- Familie gehören und „Münchner Rundfunkorchester“ nur eines davon meint.
  return query
    select e.id,e.name,'canonical'::text from ensembles e where normalize_ensemble_resolution_name(e.name)=n and not e.is_resolution_placeholder
    union all
    select e.id,e.name,'alias' from entity_aliases a join ensembles e on e.id=a.entity_id where a.entity_type='ensemble' and normalize_ensemble_resolution_name(a.alias)=n and not e.is_resolution_placeholder
    limit 1;
  get diagnostics match_count=row_count;
  if match_count>0 then return; end if;

  -- Noch nie gesehene Kombinationen automatisch anhand von Haus und
  -- Untergruppenbegriffen auffächern; dadurch braucht nicht jede neue
  -- Reihenfolge von „Chor/Kinderchor/Statisterie“ eine manuelle Regel.
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
        where not e.is_resolution_placeholder
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
grant execute on function public.resolve_ensemble_entities(text) to anon,authenticated,service_role;

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
  where not e.is_resolution_placeholder and (
    greatest(similarity(e.name,p_name),coalesce((select max(similarity(a.alias,p_name)) from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id),0))>=p_similarity_threshold
    or normalize_entity_name(e.name)=normalize_entity_name(p_name)
    or exists(select 1 from entity_aliases a where a.entity_type='ensemble' and a.entity_id=e.id and a.alias_normalized=normalize_entity_name(p_name))
  ) order by 3 desc,length(e.name) desc limit p_result_limit;
$$;

-- Eltern, Kinder und Geschwister derselben Familie sind nie Duplikate.
create or replace function public.detect_ensemble_duplicate_candidates(p_name_similarity_threshold numeric default 0.5)
returns int language plpgsql as $$
declare v_inserted int:=0;
begin
  update ensemble_duplicate_candidates c set status='dismissed',reviewed_at=now()
  from ensembles a,ensembles b where a.id=c.ensemble_a_id and b.id=c.ensemble_b_id and c.status='pending'
    and (a.is_resolution_placeholder or b.is_resolution_placeholder or a.parent_ensemble_id=b.id or b.parent_ensemble_id=a.id or (a.parent_ensemble_id is not null and a.parent_ensemble_id=b.parent_ensemble_id and coalesce(a.family_role,'')<>coalesce(b.family_role,'')));
  insert into ensemble_duplicate_candidates(ensemble_a_id,ensemble_b_id,similarity_score)
  select a.id,b.id,round(similarity(a.name,b.name)::numeric,3) from ensembles a join ensembles b on a.id<b.id
  where similarity(a.name,b.name)>=p_name_similarity_threshold
    and not a.is_resolution_placeholder and not b.is_resolution_placeholder
    and not (a.parent_ensemble_id=b.id or b.parent_ensemble_id=a.id)
    and not (a.parent_ensemble_id is not null and a.parent_ensemble_id=b.parent_ensemble_id and coalesce(a.family_role,'')<>coalesce(b.family_role,''))
    and not exists(select 1 from ensemble_duplicate_candidates c where least(c.ensemble_a_id,c.ensemble_b_id)=least(a.id,b.id) and greatest(c.ensemble_a_id,c.ensemble_b_id)=greatest(a.id,b.id))
  on conflict do nothing;
  get diagnostics v_inserted=row_count; return v_inserted;
end;
$$;

select public.detect_ensemble_duplicate_candidates();
