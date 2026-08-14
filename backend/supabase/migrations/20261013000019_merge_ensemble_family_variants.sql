-- Stark ähnliche Geschwister mit identischer Familienrolle sind beschädigte
-- Schreibvarianten, keine verschiedenen Klangkörper. Diese Migration führt
-- sie einschließlich aller fachlichen Verweise wirklich zusammen.

create or replace function public.merge_ensemble_family_variants()
returns int language plpgsql security definer set search_path=public as $$
declare item record; merged int:=0; keep_name text; remove_name text;
begin
  for item in
    with pairs as (
      select a.id as a_id,b.id as b_id,
        similarity(ensemble_family_fingerprint(a.name),ensemble_family_fingerprint(parent.name))*100
          +(a.is_verified)::int*2+(a.description_de is not null)::int+(a.photo_url is not null)::int+length(a.name)::numeric/1000 as a_score,
        similarity(ensemble_family_fingerprint(b.name),ensemble_family_fingerprint(parent.name))*100
          +(b.is_verified)::int*2+(b.description_de is not null)::int+(b.photo_url is not null)::int+length(b.name)::numeric/1000 as b_score
      from ensembles a join ensembles b on a.id<b.id
        and a.parent_ensemble_id=b.parent_ensemble_id and a.family_role=b.family_role
      join ensembles parent on parent.id=a.parent_ensemble_id
      where not a.is_resolution_placeholder and not b.is_resolution_placeholder
        and not a.is_family_root and not b.is_family_root and a.family_role is not null
        and (
          similarity(normalize_ensemble_resolution_name(a.name),normalize_ensemble_resolution_name(b.name))>=0.72
          or normalize_ensemble_resolution_name(a.name) like normalize_ensemble_resolution_name(b.name)||'%'
          or normalize_ensemble_resolution_name(b.name) like normalize_ensemble_resolution_name(a.name)||'%'
        )
    )
    select case when a_score>=b_score then a_id else b_id end as keep_id,
           case when a_score>=b_score then b_id else a_id end as remove_id
    from pairs order by greatest(a_score,b_score) desc
  loop
    select name into keep_name from ensembles where id=item.keep_id;
    select name into remove_name from ensembles where id=item.remove_id;
    if keep_name is null or remove_name is null then continue; end if;

    update ensembles keep set
      description_de=coalesce(keep.description_de,remove.description_de),
      photo_url=coalesce(keep.photo_url,remove.photo_url),
      website_url=coalesce(keep.website_url,remove.website_url),
      founded_year=coalesce(keep.founded_year,remove.founded_year),
      member_count=coalesce(keep.member_count,remove.member_count),
      is_verified=keep.is_verified or remove.is_verified
    from ensembles remove where keep.id=item.keep_id and remove.id=item.remove_id;

    delete from event_participants old_link where old_link.ensemble_id=item.remove_id
      and exists(select 1 from event_participants kept where kept.event_id=old_link.event_id and kept.ensemble_id=item.keep_id);
    update event_participants set ensemble_id=item.keep_id where ensemble_id=item.remove_id;
    delete from user_favorite_ensembles old_favorite where old_favorite.ensemble_id=item.remove_id
      and exists(select 1 from user_favorite_ensembles kept where kept.user_id=old_favorite.user_id and kept.ensemble_id=item.keep_id);
    update user_favorite_ensembles set ensemble_id=item.keep_id where ensemble_id=item.remove_id;
    update sources set ensemble_id=item.keep_id where ensemble_id=item.remove_id;
    update entity_candidates set created_ensemble_id=item.keep_id where created_ensemble_id=item.remove_id;
    update ensembles set parent_ensemble_id=item.keep_id where parent_ensemble_id=item.remove_id;
    update persons set member_of_ensemble_id=item.keep_id where member_of_ensemble_id=item.remove_id;
    update images set origin_id=item.keep_id where origin_type='ensemble' and origin_id=item.remove_id;

    delete from ensemble_resolution_rule_targets old_target where old_target.ensemble_id=item.remove_id
      and exists(select 1 from ensemble_resolution_rule_targets kept where kept.rule_id=old_target.rule_id and kept.ensemble_id=item.keep_id);
    update ensemble_resolution_rule_targets set ensemble_id=item.keep_id where ensemble_id=item.remove_id;
    delete from ensemble_duplicate_candidates where ensemble_a_id=item.remove_id or ensemble_b_id=item.remove_id;

    delete from entity_aliases old_alias where old_alias.entity_type='ensemble' and old_alias.entity_id=item.remove_id
      and (old_alias.alias_normalized=normalize_entity_name(keep_name)
        or exists(select 1 from entity_aliases kept where kept.entity_type='ensemble' and kept.entity_id=item.keep_id and kept.alias_normalized=old_alias.alias_normalized));
    update entity_aliases set entity_id=item.keep_id where entity_type='ensemble' and entity_id=item.remove_id;
    insert into entity_aliases(entity_type,entity_id,alias) values('ensemble',item.keep_id,remove_name) on conflict do nothing;
    delete from ensembles where id=item.remove_id;
    merged:=merged+1;
  end loop;
  return merged;
end;
$$;

select public.merge_ensemble_family_variants();
select public.detect_ensemble_duplicate_candidates();
