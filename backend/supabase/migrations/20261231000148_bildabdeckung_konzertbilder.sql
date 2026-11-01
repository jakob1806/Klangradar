-- Erstellt von Claude Code (Nutzerwunsch 01.11.2026: "Bilder von den
-- Importquellen, also den Veranstaltungsseiten nehmen … Ersatzbild Komponist").
--
-- Befund: 58 von 59 Quellen schieben die Bildsuche seit 31.10. in den Job
-- enrich-entity-images auf. Dieser lud alle kommenden Termine (max. 1000
-- Zeilen) und filterte erst danach – spätere Termine kamen nie dran
-- (Oper Frankfurt 184/184, Theater an der Wien 87/87, Gärtnerplatz 229/240
-- ohne eigenes Bild). Das von der Quelle gelieferte Bild ging beim
-- Aufschieben verloren.
--
-- 1. events.source_image_url: Bild, das die Importquelle am Termin liefert;
--    der Job verwendet es zuerst (mit Quelle und Credit).
-- 2. Ersatzbild: Komponist:in des ersten Werks vor dem Saalfoto – für
--    kommende Termine ohne eigenes Bild einmalig nachgezogen (264 Termine).

alter table public.events add column if not exists source_image_url text;

with ev as (
  select e.id
  from events e
  left join images i on i.id = e.primary_image_id
  where e.start_datetime >= now() and e.status = 'scheduled' and e.duplicate_of is null
    and coalesce(cardinality(e.image_urls), 0) = 0
    and (e.primary_image_id is null or i.origin_type = 'venue')
),
pick as (
  select distinct on (ev.id) ev.id, img.id as image_id
  from ev
  join event_works ew on ew.event_id = ev.id
  join works w on w.id = ew.work_id
  join images img on img.origin_type = 'person' and img.origin_id = w.composer_id
    and img.storage_path is not null
    and img.license_status in ('confirmed_free', 'confirmed_licensed', 'official_press_image')
    and coalesce(img.review_status, '') <> 'rejected'
  order by ev.id, ew.position, img.is_primary desc nulls last
)
update events e set primary_image_id = pick.image_id, updated_at = now()
from pick where pick.id = e.id;

-- 3. Falsche Zuordnungen erkennen ------------------------------------------
--    Täglich: dasselbe Foto bei mehreren Personen/Ensembles, Wikimedia-Datei,
--    deren Name den Nachnamen nicht enthält. Dazu Meldungen aus der App
--    (content_reports, Grund wrong_image). Alles landet in der Prüfansicht
--    /media/pruefen, sortiert nach Zahl kommender Konzerte.

create table if not exists public.image_flags (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('person', 'ensemble', 'venue')),
  entity_id uuid not null,
  photo_url text not null,
  reason text not null,
  status text not null default 'open' check (status in ('open', 'kept', 'removed')),
  created_at timestamptz not null default now(),
  unique (entity_type, entity_id, photo_url, reason)
);
alter table public.image_flags enable row level security;
drop policy if exists "Redaktion liest Bild-Hinweise" on public.image_flags;
create policy "Redaktion liest Bild-Hinweise" on public.image_flags for select to authenticated using (is_admin_or_editor());

create or replace function public.detect_image_conflicts()
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  insert into image_flags (entity_type, entity_id, photo_url, reason)
  select x.entity_type, x.id, x.photo_url, x.reason from (
    -- Dasselbe Foto bei mehreren Personen
    select 'person' entity_type, p.id, p.photo_url,
      'Gleiches Foto auch bei: ' || (select string_agg(o.full_name, ', ') from persons o where o.photo_url = p.photo_url and o.id <> p.id) reason
    from persons p
    where p.photo_url is not null
      and exists (select 1 from persons o where o.photo_url = p.photo_url and o.id <> p.id)
    union all
    select 'ensemble', e.id, e.photo_url,
      'Gleiches Foto auch bei: ' || (select string_agg(o.name, ', ') from ensembles o where o.photo_url = e.photo_url and o.id <> e.id)
    from ensembles e
    where e.photo_url is not null
      and exists (select 1 from ensembles o where o.photo_url = e.photo_url and o.id <> e.id)
    union all
    -- Wikimedia-Dateiname ohne einen Namensteil der Person (Kodierungen wie
    -- %C3%A1 entfernt, Namensteil ≥ 4 Buchstaben, erste 6 Buchstaben genügen –
    -- "Rachmaninow" passt so zu "Rachmaninov.jpg").
    select 'person', p.id, p.photo_url, 'Dateiname passt nicht zum Namen'
    from persons p
    where p.photo_url ~* 'wikimedia\.org/.+/[^/]+\.(jpe?g|png|webp)'
      and not exists (
        select 1 from regexp_split_to_table(lower(p.full_name), '\s+') t
        where length(regexp_replace(t, '[^a-z]', '', 'g')) >= 4
          and regexp_replace(lower(p.photo_url), '%[0-9a-f]{2}', '', 'g') like '%' || left(regexp_replace(t, '[^a-z]', '', 'g'), 6) || '%')
  ) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  -- Hinweise, deren Foto inzwischen nicht mehr gesetzt ist, erledigen sich.
  update image_flags f set status = 'removed'
  where f.status = 'open' and not exists (
    select 1 from persons p where f.entity_type = 'person' and p.id = f.entity_id and p.photo_url = f.photo_url
    union all select 1 from ensembles e where f.entity_type = 'ensemble' and e.id = f.entity_id and e.photo_url = f.photo_url
    union all select 1 from venues v where f.entity_type = 'venue' and v.id = f.entity_id and v.photo_url = f.photo_url);
  return v_count;
end;
$$;
revoke all on function public.detect_image_conflicts() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'detect-image-conflicts';
select cron.schedule('detect-image-conflicts', '41 5 * * *', $$ select public.detect_image_conflicts(); $$);
select public.detect_image_conflicts();

-- 4. Prüfansicht -------------------------------------------------------------
create or replace function public.admin_image_review_queue(p_limit int default 200)
returns table (
  kind text, image_id uuid, flag_id uuid, report_id uuid, entity_type text, entity_id uuid, entity_name text,
  upcoming int, image_url text, source_page_url text, source_name text, credits text,
  license_status text, license_name text, reason text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'not allowed'; end if;
  return query
  with q as (
    -- Bildkandidaten, die auf eine Lizenzentscheidung warten
    select 'license'::text kind, i.id image_id, null::uuid flag_id, null::uuid report_id, i.origin_type entity_type, i.origin_id entity_id,
      coalesce(case when i.thumbnail_path is not null or i.storage_path is not null
        then 'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/ingested-images/' || coalesce(i.storage_path, i.thumbnail_path) end, i.source_url) image_url,
      i.source_page_url, i.source_name, coalesce(i.credits, i.photographer) credits, i.license_status, i.license_name,
      coalesce(nullif(array_to_string(i.warnings, ' · '), ''), i.match_reason, 'Lizenz prüfen') reason, i.imported_at created_at
    from images i
    where i.needs_review and i.license_status not in ('rejected') and coalesce(i.review_status, '') not in ('rejected', 'approved')
      and i.origin_type in ('person', 'ensemble', 'venue', 'event')
    union all
    select 'flag', null, f.id, null, f.entity_type, f.entity_id, f.photo_url, null, null, null, null, null, f.reason, f.created_at
    from image_flags f where f.status = 'open'
    union all
    select 'report', null, null, r.id, r.entity_type, r.entity_id,
      case r.entity_type when 'person' then (select photo_url from persons where id = r.entity_id)
        when 'ensemble' then (select photo_url from ensembles where id = r.entity_id)
        when 'venue' then (select photo_url from venues where id = r.entity_id)
        else (select image_urls[1] from events where id = r.entity_id) end,
      null, null, null, null, null, 'In der App gemeldet' || coalesce(': ' || r.message, ''), r.created_at
    from content_reports r where r.reason = 'wrong_image' and r.status = 'pending'
  )
  select q.kind, q.image_id, q.flag_id, q.report_id, q.entity_type, q.entity_id,
    coalesce((select full_name from persons where id = q.entity_id), (select name from ensembles where id = q.entity_id),
             (select name from venues where id = q.entity_id), (select title from events where id = q.entity_id), '–'),
    case q.entity_type
      when 'person' then (select count(distinct ep.event_id)::int from event_participants ep join events e on e.id = ep.event_id where ep.person_id = q.entity_id and e.start_datetime >= now() and e.status = 'scheduled')
      when 'ensemble' then (select count(distinct ep.event_id)::int from event_participants ep join events e on e.id = ep.event_id where ep.ensemble_id = q.entity_id and e.start_datetime >= now() and e.status = 'scheduled')
      when 'venue' then (select count(*)::int from events e where e.venue_id = q.entity_id and e.start_datetime >= now() and e.status = 'scheduled')
      else 1 end,
    q.image_url, q.source_page_url, q.source_name, q.credits, q.license_status, q.license_name, q.reason, q.created_at
  from q
  where q.image_url is not null
  order by 8 desc nulls last, q.created_at desc
  limit p_limit;
end;
$$;
revoke all on function public.admin_image_review_queue(int) from public, anon;
grant execute on function public.admin_image_review_queue(int) to authenticated;

-- Entscheidung "Bild ist falsch": Foto bei der Entität entfernen, Bildzeilen
-- mit dieser Adresse ablehnen, Hinweise/Meldungen schließen. Die Bildsuche
-- übernimmt abgelehnte Adressen nicht erneut.
create or replace function public.admin_remove_entity_photo(p_entity_type text, p_entity_id uuid, p_photo_url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'not allowed'; end if;
  if p_entity_type = 'person' then update persons set photo_url = null, image_search_checked_at = now() where id = p_entity_id and photo_url = p_photo_url;
  elsif p_entity_type = 'ensemble' then update ensembles set photo_url = null, image_search_checked_at = now() where id = p_entity_id and photo_url = p_photo_url;
  elsif p_entity_type = 'venue' then update venues set photo_url = null, image_search_checked_at = now() where id = p_entity_id and photo_url = p_photo_url;
  elsif p_entity_type = 'event' then update events set image_urls = array_remove(image_urls, p_photo_url) where id = p_entity_id;
  end if;
  update images set license_status = 'rejected', review_status = 'rejected', needs_review = false, is_primary = false,
    reviewed_at = now(), reviewed_by = auth.uid()
  where origin_type = p_entity_type and origin_id = p_entity_id
    and (source_url = p_photo_url or original_image_url = p_photo_url or p_photo_url like '%' || storage_path);
  update events set primary_image_id = null
  where primary_image_id in (select id from images where origin_type = p_entity_type and origin_id = p_entity_id and license_status = 'rejected');
  update image_flags set status = 'removed' where entity_type = p_entity_type and entity_id = p_entity_id and status = 'open';
  update content_reports set status = 'resolved', reviewed_by = auth.uid(), reviewed_at = now()
  where entity_type = p_entity_type and entity_id = p_entity_id and reason = 'wrong_image' and status = 'pending';
end;
$$;
revoke all on function public.admin_remove_entity_photo(text, uuid, text) from public, anon;
grant execute on function public.admin_remove_entity_photo(text, uuid, text) to authenticated;

-- Entscheidung "Bild ist richtig": Hinweis/Meldung schließen.
create or replace function public.admin_keep_entity_photo(p_flag_id uuid, p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'not allowed'; end if;
  update image_flags set status = 'kept' where id = p_flag_id;
  update content_reports set status = 'dismissed', reviewed_by = auth.uid(), reviewed_at = now() where id = p_report_id;
end;
$$;
revoke all on function public.admin_keep_entity_photo(uuid, uuid) from public, anon;
grant execute on function public.admin_keep_entity_photo(uuid, uuid) to authenticated;

-- 5. Neue Porträtquellen (harvest-artist-photos): stündlich eine Quelle
--    (BRSO, Münchner Rundfunkorchester, DSO Berlin, Intermusica,
--    HarrisonParrott, KD Schmid, Askonas Holt), je Lauf bis zu 15 Personen.
create or replace function public.run_harvest_artist_photos()
returns void language plpgsql as $$
declare
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/harvest-artist-photos',
    body := '{"limit": 15}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key, 'Authorization', 'Bearer ' || v_anon_key),
    timeout_milliseconds := 120000
  );
exception when others then
  raise warning 'run_harvest_artist_photos fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'harvest-artist-photos';
select cron.schedule('harvest-artist-photos', '52 * * * *', $$ select public.run_harvest_artist_photos(); $$);
