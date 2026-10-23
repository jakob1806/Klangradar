-- Erstellt von Claude Code (Nutzerfeedback 23.10.2026: "Freigeben klappt
-- technisch nicht" bei rund 1.000 Bildern in der Prüfliste).
--
-- Ursache: Die Sammelfreigabe in /media rief pro Bild eine Kette von 6–10
-- einzelnen Datenbankaufrufen auf, alle parallel, plus ein Seiten-Neuaufbau
-- pro Bild. Ab einigen hundert Bildern lief die Server-Aktion ins Zeitlimit
-- und brach ab.
--
-- Neu: review_images() erledigt alles in einem Aufruf und einer Transaktion
-- (Lizenz/Prüfstatus setzen, Foto in die Entität übernehmen, Titelbild und
-- Reihenfolge). Nur für Redaktion/Admin.

create or replace function public.review_images(p_ids uuid[], p_status text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_img record;
  v_url text;
  v_count int := 0;
begin
  if not is_admin_or_editor() then raise exception 'not allowed'; end if;
  if p_status not in ('confirmed_free', 'confirmed_licensed', 'rejected') then raise exception 'invalid status'; end if;

  for v_img in select id, origin_type, origin_id, source_url, storage_path from images where id = any(p_ids) loop
    update images set
      license_status = p_status,
      needs_review = false,
      review_status = case when p_status = 'rejected' then 'rejected' else 'approved' end,
      reviewed_at = now(),
      reviewed_by = auth.uid()
    where id = v_img.id;
    v_count := v_count + 1;

    continue when p_status = 'rejected';

    v_url := case when v_img.storage_path is not null
      then 'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/ingested-images/' || v_img.storage_path
      else v_img.source_url end;

    if v_img.origin_type = 'event' then
      update events set image_urls = coalesce(image_urls, '{}') || v_url
      where id = v_img.origin_id and not (v_url = any(coalesce(image_urls, '{}')));
    elsif v_img.origin_type = 'person' then
      update persons set photo_url = v_url where id = v_img.origin_id and photo_url is null;
    elsif v_img.origin_type = 'ensemble' then
      update ensembles set photo_url = v_url where id = v_img.origin_id and photo_url is null;
    elsif v_img.origin_type = 'venue' then
      update venues set photo_url = v_url where id = v_img.origin_id and photo_url is null;
    elsif v_img.origin_type = 'festival' then
      update festivals set photo_url = v_url where id = v_img.origin_id and photo_url is null;
    end if;

    -- Titelbild: dieses Bild an Position 0, die übrigen dahinter.
    update images set is_primary = (id = v_img.id),
      sort_order = case when id = v_img.id then 0 else sort_order + 1 end
    where origin_type = v_img.origin_type and origin_id = v_img.origin_id;
  end loop;

  insert into system_logs (entity_type, entity_id, action, actor)
  select 'image', id, 'license_' || p_status, coalesce((select email from auth.users where id = auth.uid()), auth.uid()::text)
  from unnest(p_ids) as id;

  return v_count;
end;
$$;
revoke all on function public.review_images(uuid[], text) from public, anon;
grant execute on function public.review_images(uuid[], text) to authenticated;
