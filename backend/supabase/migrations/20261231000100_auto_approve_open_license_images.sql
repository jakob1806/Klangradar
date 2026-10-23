-- Erstellt von Claude Code (Nutzerfeedback 23.10.2026: Bilderkennung stockt).
--
-- Befund: Die Bildsuche läuft alle 3–5 Minuten und findet Bilder, aber jeder
-- Fund aus einer Fremdquelle wartete auf redaktionelle Lizenzprüfung
-- (last_image_search_note "wartet auf Lizenzprüfung"). Hunderte Kandidaten
-- lagen in der Queue, 80 % der Personen blieben ohne Foto.
--
-- Neu: Bilder mit freier Lizenz aus Quellen, die eindeutig zur Entität
-- gehören, werden automatisch freigegeben und übernommen:
--   - Wikipedia (Porträt des exakten Artikels) und Wikidata (Bild-Eigenschaft
--     des exakten Eintrags): Personen, Ensembles, Orte
--   - Wikimedia Commons (Volltextsuche): nur Orte (Gebäudenamen kollidieren
--     selten; bei Personen/Ensembles bleibt Commons in der Prüfung)
-- Nur technisch einwandfreie Bilder (quality_status = 'valid'), nur wenn die
-- Entität noch kein Foto hat, pro Entität das beste Bild. Bilder von
-- Veranstalter-/Ticketseiten bleiben in der Prüfung (Lizenz unklar).

create or replace function public.auto_approve_open_license_images(p_limit int default 500)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
  v_count int := 0;
  v_url text;
begin
  for v_row in
    select distinct on (i.origin_type, i.origin_id)
      i.id, i.origin_type, i.origin_id, i.source_url, i.storage_path
    from images i
    where (i.needs_review or i.review_status = 'pending')
      and i.review_status <> 'rejected'
      and i.license_status <> 'rejected'
      and coalesce(i.quality_status, 'valid') = 'valid'
      and i.origin_type in ('person', 'ensemble', 'venue')
      and (
        i.source_name in ('Wikipedia', 'Wikidata', 'www.wikidata.org')
        or (i.origin_type = 'venue' and i.source_name in ('Wikimedia Commons', 'commons.wikimedia.org', 'upload.wikimedia.org'))
      )
      and case i.origin_type
            when 'person' then exists (select 1 from persons p where p.id = i.origin_id and p.photo_url is null)
            when 'ensemble' then exists (select 1 from ensembles e where e.id = i.origin_id and e.photo_url is null)
            when 'venue' then exists (select 1 from venues v where v.id = i.origin_id and v.photo_url is null)
          end
    order by i.origin_type, i.origin_id, (i.source_name = 'Wikipedia') desc, i.imported_at desc
    limit greatest(p_limit, 1)
  loop
    v_url := case when v_row.storage_path is not null
      then 'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/ingested-images/' || v_row.storage_path
      else v_row.source_url end;

    update images set
      needs_review = false,
      review_status = 'approved',
      license_status = 'confirmed_free',
      is_primary = true,
      reviewed_at = now(),
      license_notes = coalesce(license_notes, 'Automatisch freigegeben: freie Lizenz (Wikimedia), eindeutig der Entität zugeordnet.')
    where id = v_row.id;
    update images set is_primary = false
    where origin_type = v_row.origin_type and origin_id = v_row.origin_id and id <> v_row.id;

    if v_row.origin_type = 'person' then
      update persons set photo_url = v_url where id = v_row.origin_id and photo_url is null;
    elsif v_row.origin_type = 'ensemble' then
      update ensembles set photo_url = v_url where id = v_row.origin_id and photo_url is null;
    else
      update venues set photo_url = v_url where id = v_row.origin_id and photo_url is null;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.auto_approve_open_license_images(int) from public, anon, authenticated;
grant execute on function public.auto_approve_open_license_images(int) to service_role;

-- Bestand sofort abarbeiten, danach alle 10 Minuten neue Funde.
do $$
declare v int;
begin
  v := public.auto_approve_open_license_images(5000);
  raise notice 'Automatisch freigegebene Bilder: %', v;
end $$;

select cron.schedule('auto-approve-open-license-images', '*/10 * * * *', $$ select public.auto_approve_open_license_images(200); $$);
