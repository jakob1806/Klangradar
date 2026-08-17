-- Atomare Zusammenfuehrungen fuer die Duplikatpruefung. Die bisherigen
-- Next.js-Actions verschoben Verweise einzeln; existierte am Ziel bereits
-- dieselbe Event-/Favoriten-Verknuepfung, brach der Lauf am Unique-Index ab
-- und hinterliess einen teilweise migrierten Datensatz.

create or replace function public.merge_person_duplicate_candidate(
  p_candidate_id uuid,
  p_keep_person_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.person_duplicate_candidates%rowtype;
  remove_id uuid;
  remove_name text;
begin
  if not public.is_admin_or_editor() then raise exception 'Nicht berechtigt'; end if;

  select * into c from person_duplicate_candidates where id=p_candidate_id and status='pending' for update;
  if not found then raise exception 'Personen-Duplikat-Kandidat nicht gefunden oder bereits bearbeitet'; end if;
  if p_keep_person_id not in (c.person_a_id,c.person_b_id) then raise exception 'Ausgewaehlte Person gehoert nicht zu diesem Kandidaten'; end if;
  remove_id := case when p_keep_person_id=c.person_a_id then c.person_b_id else c.person_a_id end;
  select full_name into remove_name from persons where id=remove_id for update;
  perform 1 from persons where id=p_keep_person_id for update;

  update persons keep set
    biography_de=coalesce(keep.biography_de,old.biography_de), biography_en=coalesce(keep.biography_en,old.biography_en),
    birth_date=coalesce(keep.birth_date,old.birth_date), death_date=coalesce(keep.death_date,old.death_date),
    nationality=coalesce(keep.nationality,old.nationality), instrument=coalesce(keep.instrument,old.instrument),
    photo_url=coalesce(keep.photo_url,old.photo_url), website_url=coalesce(keep.website_url,old.website_url),
    wikipedia_url=coalesce(keep.wikipedia_url,old.wikipedia_url), roles=(select array(select distinct unnest(coalesce(keep.roles,'{}')||coalesce(old.roles,'{}')))),
    is_verified=coalesce(keep.is_verified,false) or coalesce(old.is_verified,false)
  from persons old where keep.id=p_keep_person_id and old.id=remove_id;

  delete from event_participants old where old.person_id=remove_id and exists(
    select 1 from event_participants kept where kept.event_id=old.event_id and kept.person_id=p_keep_person_id
  );
  update event_participants set person_id=p_keep_person_id where person_id=remove_id;
  delete from user_favorite_persons old where old.person_id=remove_id and exists(
    select 1 from user_favorite_persons kept where kept.user_id=old.user_id and kept.person_id=p_keep_person_id
  );
  update user_favorite_persons set person_id=p_keep_person_id where person_id=remove_id;
  update works set composer_id=p_keep_person_id where composer_id=remove_id;
  update sources set person_id=p_keep_person_id where person_id=remove_id;
  update entity_candidates set created_person_id=p_keep_person_id where created_person_id=remove_id;
  -- Der partielle Unique-Index erlaubt je Entitaet nur ein Primaerbild.
  -- Hat die behaltene Person bereits eines, bleiben die Bilder der
  -- verworfenen Version erhalten, werden beim Umhaengen aber Galerie-Bilder.
  update images set is_primary=false
    where origin_type='person' and origin_id=remove_id and is_primary
      and exists(select 1 from images where origin_type='person' and origin_id=p_keep_person_id and is_primary);
  update images set origin_id=p_keep_person_id where origin_type='person' and origin_id=remove_id;

  delete from field_provenance old where old.entity_type='person' and old.entity_id=remove_id and exists(
    select 1 from field_provenance kept where kept.entity_type='person' and kept.entity_id=p_keep_person_id and kept.field_name=old.field_name
  );
  update field_provenance set entity_id=p_keep_person_id where entity_type='person' and entity_id=remove_id;
  delete from entity_aliases old where old.entity_type='person' and old.entity_id=remove_id and (
    old.alias_normalized=public.normalize_entity_name((select full_name from persons where id=p_keep_person_id)) or exists(
      select 1 from entity_aliases kept where kept.entity_type='person' and kept.entity_id=p_keep_person_id and kept.alias_normalized=old.alias_normalized
    )
  );
  update entity_aliases set entity_id=p_keep_person_id where entity_type='person' and entity_id=remove_id;
  if public.normalize_entity_name(remove_name)<>public.normalize_entity_name((select full_name from persons where id=p_keep_person_id)) then
    insert into entity_aliases(entity_type,entity_id,alias) values('person',p_keep_person_id,remove_name) on conflict do nothing;
  end if;

  -- Andere offene Paare mit der verworfenen Version sind nach dem Merge
  -- nicht mehr sinnvoll. Der bearbeitete Kandidat wird vor dem Delete
  -- markiert; sein FK wird durch ON DELETE CASCADE entfernt.
  update person_duplicate_candidates set status='dismissed',reviewed_at=now()
    where id<>p_candidate_id and status='pending' and remove_id in (person_a_id,person_b_id);
  update person_duplicate_candidates set status='merged',reviewed_at=now() where id=p_candidate_id;
  delete from persons where id=remove_id;
  return true;
end;
$$;

create or replace function public.merge_ensemble_duplicate_candidate(
  p_candidate_id uuid,
  p_keep_ensemble_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.ensemble_duplicate_candidates%rowtype;
  remove_id uuid;
  remove_name text;
begin
  if not public.is_admin_or_editor() then raise exception 'Nicht berechtigt'; end if;
  select * into c from ensemble_duplicate_candidates where id=p_candidate_id and status='pending' for update;
  if not found then raise exception 'Ensemble-Duplikat-Kandidat nicht gefunden oder bereits bearbeitet'; end if;
  if p_keep_ensemble_id not in (c.ensemble_a_id,c.ensemble_b_id) then raise exception 'Ausgewaehltes Ensemble gehoert nicht zu diesem Kandidaten'; end if;
  remove_id := case when p_keep_ensemble_id=c.ensemble_a_id then c.ensemble_b_id else c.ensemble_a_id end;
  select name into remove_name from ensembles where id=remove_id for update;
  perform 1 from ensembles where id=p_keep_ensemble_id for update;

  update ensembles keep set description_de=coalesce(keep.description_de,old.description_de),
    description_en=coalesce(keep.description_en,old.description_en), founded_year=coalesce(keep.founded_year,old.founded_year),
    member_count=coalesce(keep.member_count,old.member_count), photo_url=coalesce(keep.photo_url,old.photo_url),
    website_url=coalesce(keep.website_url,old.website_url), home_venue_id=coalesce(keep.home_venue_id,old.home_venue_id),
    is_verified=coalesce(keep.is_verified,false) or coalesce(old.is_verified,false)
  from ensembles old where keep.id=p_keep_ensemble_id and old.id=remove_id;

  delete from event_participants old where old.ensemble_id=remove_id and exists(
    select 1 from event_participants kept where kept.event_id=old.event_id and kept.ensemble_id=p_keep_ensemble_id
  );
  update event_participants set ensemble_id=p_keep_ensemble_id where ensemble_id=remove_id;
  delete from user_favorite_ensembles old where old.ensemble_id=remove_id and exists(
    select 1 from user_favorite_ensembles kept where kept.user_id=old.user_id and kept.ensemble_id=p_keep_ensemble_id
  );
  update user_favorite_ensembles set ensemble_id=p_keep_ensemble_id where ensemble_id=remove_id;
  update sources set ensemble_id=p_keep_ensemble_id where ensemble_id=remove_id;
  update entity_candidates set created_ensemble_id=p_keep_ensemble_id where created_ensemble_id=remove_id;
  update ensembles set parent_ensemble_id=p_keep_ensemble_id where parent_ensemble_id=remove_id;
  update persons set member_of_ensemble_id=p_keep_ensemble_id where member_of_ensemble_id=remove_id;
  -- Beide Versionen koennen ein Primaerbild besitzen. Vor dem Umhaengen
  -- den Verlierer nur dann zum Galerie-Bild herabstufen, wenn das Ziel
  -- bereits ein Primaerbild hat; andernfalls wandert sein Primaerbild mit.
  update images set is_primary=false
    where origin_type='ensemble' and origin_id=remove_id and is_primary
      and exists(select 1 from images where origin_type='ensemble' and origin_id=p_keep_ensemble_id and is_primary);
  update images set origin_id=p_keep_ensemble_id where origin_type='ensemble' and origin_id=remove_id;
  delete from ensemble_resolution_rule_targets old where old.ensemble_id=remove_id and exists(
    select 1 from ensemble_resolution_rule_targets kept where kept.rule_id=old.rule_id and kept.ensemble_id=p_keep_ensemble_id
  );
  update ensemble_resolution_rule_targets set ensemble_id=p_keep_ensemble_id where ensemble_id=remove_id;
  update ensemble_resolution_rules set family_root_id=p_keep_ensemble_id where family_root_id=remove_id;

  delete from field_provenance old where old.entity_type='ensemble' and old.entity_id=remove_id and exists(
    select 1 from field_provenance kept where kept.entity_type='ensemble' and kept.entity_id=p_keep_ensemble_id and kept.field_name=old.field_name
  );
  update field_provenance set entity_id=p_keep_ensemble_id where entity_type='ensemble' and entity_id=remove_id;
  delete from entity_aliases old where old.entity_type='ensemble' and old.entity_id=remove_id and (
    old.alias_normalized=public.normalize_entity_name((select name from ensembles where id=p_keep_ensemble_id)) or exists(
      select 1 from entity_aliases kept where kept.entity_type='ensemble' and kept.entity_id=p_keep_ensemble_id and kept.alias_normalized=old.alias_normalized
    )
  );
  update entity_aliases set entity_id=p_keep_ensemble_id where entity_type='ensemble' and entity_id=remove_id;
  if public.normalize_entity_name(remove_name)<>public.normalize_entity_name((select name from ensembles where id=p_keep_ensemble_id)) then
    insert into entity_aliases(entity_type,entity_id,alias) values('ensemble',p_keep_ensemble_id,remove_name) on conflict do nothing;
  end if;

  update ensemble_duplicate_candidates set status='dismissed',reviewed_at=now()
    where id<>p_candidate_id and status='pending' and remove_id in (ensemble_a_id,ensemble_b_id);
  update ensemble_duplicate_candidates set status='merged',reviewed_at=now() where id=p_candidate_id;
  delete from ensembles where id=remove_id;
  return true;
end;
$$;

grant execute on function public.merge_person_duplicate_candidate(uuid,uuid) to authenticated;
grant execute on function public.merge_ensemble_duplicate_candidate(uuid,uuid) to authenticated;

-- Familienmitglieder werden im Familienwerkzeug gepflegt und sind keine
-- normalen Duplikate. Bestehende Treffer werden ebenfalls entfernt.
update ensemble_duplicate_candidates c set status='dismissed',reviewed_at=now()
from ensembles a,ensembles b
where c.status='pending' and a.id=c.ensemble_a_id and b.id=c.ensemble_b_id and (
  a.is_family_root or b.is_family_root or a.is_resolution_placeholder or b.is_resolution_placeholder
  or a.parent_ensemble_id=b.id or b.parent_ensemble_id=a.id
  or (a.parent_ensemble_id is not null and a.parent_ensemble_id=b.parent_ensemble_id)
);

create or replace function public.detect_ensemble_duplicate_candidates(p_name_similarity_threshold numeric default 0.5)
returns int language plpgsql as $$
declare v_inserted int:=0;
begin
  update ensemble_duplicate_candidates c set status='dismissed',reviewed_at=now()
  from ensembles a,ensembles b where a.id=c.ensemble_a_id and b.id=c.ensemble_b_id and c.status='pending'
    and (a.is_family_root or b.is_family_root or a.is_resolution_placeholder or b.is_resolution_placeholder
      or a.parent_ensemble_id=b.id or b.parent_ensemble_id=a.id
      or (a.parent_ensemble_id is not null and a.parent_ensemble_id=b.parent_ensemble_id));
  insert into ensemble_duplicate_candidates(ensemble_a_id,ensemble_b_id,similarity_score)
  select a.id,b.id,round(similarity(a.name,b.name)::numeric,3) from ensembles a join ensembles b on a.id<b.id
  where similarity(a.name,b.name)>=p_name_similarity_threshold
    and not a.is_family_root and not b.is_family_root
    and not a.is_resolution_placeholder and not b.is_resolution_placeholder
    and not (a.parent_ensemble_id=b.id or b.parent_ensemble_id=a.id)
    and not (a.parent_ensemble_id is not null and a.parent_ensemble_id=b.parent_ensemble_id)
    and not exists(select 1 from ensemble_duplicate_candidates c where least(c.ensemble_a_id,c.ensemble_b_id)=least(a.id,b.id) and greatest(c.ensemble_a_id,c.ensemble_b_id)=greatest(a.id,b.id));
  get diagnostics v_inserted=row_count; return v_inserted;
end;
$$;

-- Vollstaendiges, aber abgesichertes Entfernen eines Kontos. Historische
-- Review-Zeilen bleiben erhalten; nur ihre Bearbeiterreferenz wird geloest.
create or replace function public.admin_delete_user(p_user_id uuid)
returns boolean language plpgsql security definer set search_path=public,auth as $$
declare admin_count int;
begin
  if not public.is_admin() then raise exception 'Nur Admins duerfen Benutzer entfernen'; end if;
  if p_user_id=auth.uid() then raise exception 'Du kannst dein eigenes Konto nicht entfernen'; end if;
  if exists(select 1 from user_roles where user_id=p_user_id and role='admin') then
    select count(*) into admin_count from user_roles where role='admin';
    if admin_count<=1 then raise exception 'Der letzte Admin kann nicht entfernt werden'; end if;
  end if;
  update duplicate_candidates set reviewed_by=null where reviewed_by=p_user_id;
  update person_duplicate_candidates set reviewed_by=null where reviewed_by=p_user_id;
  update work_duplicate_candidates set reviewed_by=null where reviewed_by=p_user_id;
  update venue_duplicate_candidates set reviewed_by=null where reviewed_by=p_user_id;
  update ensemble_duplicate_candidates set reviewed_by=null where reviewed_by=p_user_id;
  update cancellation_candidates set reviewed_by=null where reviewed_by=p_user_id;
  update entity_candidates set reviewed_by=null where reviewed_by=p_user_id;
  update images set reviewed_by=null where reviewed_by=p_user_id;
  update content_reports set reviewed_by=null where reviewed_by=p_user_id;
  update editorial_ai_settings set updated_by=null where updated_by=p_user_id;
  delete from editorial_ai_threads where created_by=p_user_id;
  update event_views set user_id=null where user_id=p_user_id;
  delete from auth.users where id=p_user_id;
  if not found then raise exception 'Benutzer nicht gefunden'; end if;
  return true;
end;
$$;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- Verifizierte Position am Gebaeude Prinzregentenplatz 12.
update venues set
  address_street='Prinzregentenplatz 12', address_zip='81675', address_city='München',
  location=st_setsrid(st_makepoint(11.605591,48.138986),4326)::geography,
  updated_at=now()
where normalize_entity_name(name)=normalize_entity_name('Prinzregententheater');

-- Der im Personenverzeichnis auffaellige Datensatz ist real, hatte aber
-- keinerlei Rolle/Instrument und erschien deshalb ohne Unterzeile.
update persons set roles=array['solist'],instrument='Violine',birth_date=coalesce(birth_date,'1987-12-17'::date),
  website_url=coalesce(website_url,'https://camerata.at/de/musikerinnen/afanasy-chupin'),updated_at=now()
where normalize_entity_name(full_name)=normalize_entity_name('Afanasy Chupin');
