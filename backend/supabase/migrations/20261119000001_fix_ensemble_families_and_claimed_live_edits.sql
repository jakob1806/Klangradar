-- Manuell entfernte Familienzuordnungen dürfen nicht durch die alte
-- Namensheuristik beim Speichern sofort wieder hergestellt werden.
create or replace function public.assign_ensemble_family()
returns trigger language plpgsql security definer set search_path=public as $$
declare n text := normalize_ensemble_resolution_name(new.name); root_id uuid;
begin
  if tg_op = 'UPDATE' and new.parent_ensemble_id is null and old.parent_ensemble_id is not null and not new.is_family_root then
    new.family_role := null;
    return new;
  end if;
  if new.is_family_root or n in ('staatstheater am gaertnerplatz','staatstheater am gartnerplatz','bayerische staatsoper','bayerischer rundfunk') then
    new.is_family_root := true; new.family_role := 'institution'; new.parent_ensemble_id := null; return new;
  end if;
  if n ~ 'kammerorchester des symphonieorchesters des bayerischen rundfunks' then
    select id into root_id from ensembles where normalize_ensemble_resolution_name(name)='symphonieorchester des bayerischen rundfunks' limit 1;
  else root_id := detect_ensemble_family_root(new.name,new.id); end if;
  if root_id is not null and new.parent_ensemble_id is null then new.parent_ensemble_id := root_id; end if;
  if root_id is not null and (new.family_role is null or new.family_role='other') then new.family_role := ensemble_role_from_name(new.name); end if;
  return new;
end;
$$;

-- Eigenständige Knabenchöre sind keine Unterensembles voneinander. Beim
-- Tölzer Knabenchor bleibt nur die explizite Solistenformation zugeordnet.
update ensembles set parent_ensemble_id = null, family_role = null
where name ilike '%tölzer knabenchor%'
  and name not ilike 'solisten des tölzer knabenchor%';

update ensembles child set parent_ensemble_id = root.id, family_role = 'other'
from ensembles root
where child.name ilike 'solisten des tölzer knabenchor%'
  and root.name ilike 'tölzer knabenchor'
  and root.name not ilike 'solisten des tölzer knabenchor%';

-- Genehmigte Claims sind nun echte Verwaltungsrechte: Änderungen gehen
-- unmittelbar live. Redaktion behält weiterhin die volle Bearbeitungsrolle.
create policy "Claimed users update persons" on persons for update
  using (has_approved_claim('person', id)) with check (has_approved_claim('person', id));
create policy "Claimed users update ensembles" on ensembles for update
  using (has_approved_claim('ensemble', id)) with check (has_approved_claim('ensemble', id));
create policy "Claimed users update venues" on venues for update
  using (has_approved_claim('venue', id)) with check (has_approved_claim('venue', id));

alter table venues add column if not exists avatar_crop_x numeric(5,4);
alter table venues add column if not exists avatar_crop_y numeric(5,4);
alter table venues add column if not exists avatar_crop_width numeric(5,4);
alter table venues add column if not exists avatar_crop_height numeric(5,4);

create policy "Claimed users manage their gallery images" on images for all
  using (origin_type in ('person','ensemble','venue') and has_approved_claim(origin_type, origin_id))
  with check (origin_type in ('person','ensemble','venue') and has_approved_claim(origin_type, origin_id));
