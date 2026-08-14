-- Nach Aufbau der Ensemblefamilien lassen sich beschädigte oder leicht
-- abweichende Geschwister derselben Rolle sicherer erkennen als global.
-- Beispiele im Live-Bestand: „... am G“ und „... am Grtnerplatz“ neben der
-- vollständigen Gärtnerplatz-Schreibweise. Unterschiedliche Rollen werden
-- niemals zusammengeführt; mehrere echte Orchester eines Hauses nur dann,
-- wenn ihre Namen sehr ähnlich sind.

create or replace function public.consolidate_ensemble_family_variants()
returns int language plpgsql security definer set search_path=public as $$
declare item record; merged int:=0;
begin
  for item in
    with pairs as (
      select a.id as a_id,b.id as b_id,a.name as a_name,b.name as b_name,
        case when
          (normalize_ensemble_resolution_name(a.name) like '%'||normalize_ensemble_resolution_name(parent.name)||'%')::int * 10
          + (a.is_verified)::int
          + (a.description_de is not null)::int
          + (a.photo_url is not null)::int
          + least(length(a.name),100)::numeric/1000
          >=
          (normalize_ensemble_resolution_name(b.name) like '%'||normalize_ensemble_resolution_name(parent.name)||'%')::int * 10
          + (b.is_verified)::int
          + (b.description_de is not null)::int
          + (b.photo_url is not null)::int
          + least(length(b.name),100)::numeric/1000
          then a.id else b.id end as keep_id,
        case when
          (normalize_ensemble_resolution_name(a.name) like '%'||normalize_ensemble_resolution_name(parent.name)||'%')::int * 10
          + (a.is_verified)::int
          + (a.description_de is not null)::int
          + (a.photo_url is not null)::int
          + least(length(a.name),100)::numeric/1000
          >=
          (normalize_ensemble_resolution_name(b.name) like '%'||normalize_ensemble_resolution_name(parent.name)||'%')::int * 10
          + (b.is_verified)::int
          + (b.description_de is not null)::int
          + (b.photo_url is not null)::int
          + least(length(b.name),100)::numeric/1000
          then b.id else a.id end as remove_id
      from ensembles a
      join ensembles b on a.id<b.id
        and a.parent_ensemble_id=b.parent_ensemble_id
        and a.family_role=b.family_role
      join ensembles parent on parent.id=a.parent_ensemble_id
      where not a.is_resolution_placeholder and not b.is_resolution_placeholder
        and not a.is_family_root and not b.is_family_root
        and a.family_role is not null
        and (
          similarity(normalize_ensemble_resolution_name(a.name),normalize_ensemble_resolution_name(b.name))>=0.72
          or normalize_ensemble_resolution_name(a.name) like normalize_ensemble_resolution_name(b.name)||'%'
          or normalize_ensemble_resolution_name(b.name) like normalize_ensemble_resolution_name(a.name)||'%'
        )
    ) select distinct keep_id,remove_id from pairs
  loop
    if exists(select 1 from ensembles where id=item.keep_id)
       and exists(select 1 from ensembles where id=item.remove_id) then
      insert into entity_aliases(entity_type,entity_id,alias)
      select 'ensemble',item.keep_id,name from ensembles where id=item.remove_id
      on conflict do nothing;
      if not exists(select 1 from ensembles where id=item.remove_id) then merged:=merged+1; end if;
    end if;
  end loop;
  return merged;
end;
$$;

select public.consolidate_ensemble_family_variants();
select public.detect_ensemble_duplicate_candidates();
