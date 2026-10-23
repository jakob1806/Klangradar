-- Erstellt von Claude Code (Nutzerfeedback 23.10.2026): Programm-Erkennung
-- bei den Münchner Philharmonikern, Stücke doppelt/falsch erkannt.
--
-- 1. merge_works(): führt ein doppelt angelegtes Werk in das behaltene über
--    (Programme, Favoriten, Attribute, Bild-Wiederverwendung, Aliasse,
--    Provenienz). Aufgerufen von der Edge Function dedupe-works, die die
--    Identität per workIdentity.ts bestimmt (dieselbe Logik wie im Import).
-- 2. mphil.de-Termine einmal neu einlesen: hydrate-mphil-events liest jetzt
--    das offizielle Programm statt der KI-Extraktion.
-- 3. Täglicher Cron für dedupe-works.

create or replace function public.merge_works(p_keep uuid, p_drop uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_drop works%rowtype;
begin
  if p_keep = p_drop then return; end if;
  select * into v_drop from works where id = p_drop;
  if v_drop.id is null or not exists (select 1 from works where id = p_keep) then return; end if;

  -- Programme: bei Konflikt (gleiches Event, gleiche Position) Duplikat-Zeile löschen.
  delete from event_works d using event_works k
    where d.work_id = p_drop and k.work_id = p_keep and k.event_id = d.event_id;
  update event_works set work_id = p_keep where work_id = p_drop;

  insert into user_favorite_works (user_id, work_id, created_at)
    select user_id, p_keep, created_at from user_favorite_works where work_id = p_drop
    on conflict do nothing;
  delete from user_favorite_works where work_id = p_drop;

  insert into work_attributes (work_id, attribute_id, weight, source)
    select p_keep, attribute_id, weight, source from work_attributes where work_id = p_drop
    on conflict do nothing;
  delete from work_attributes where work_id = p_drop;

  delete from event_image_reuse d using event_image_reuse k
    where d.work_id = p_drop and k.work_id = p_keep and k.event_id = d.event_id;
  update event_image_reuse set work_id = p_keep where work_id = p_drop;

  update program_items set work_id = p_keep where work_id = p_drop;
  update field_provenance set entity_id = p_keep where entity_type = 'work' and entity_id = p_drop;

  -- Bisherigen Titel als Alias behalten, Aliasse übernehmen.
  insert into entity_aliases (entity_type, entity_id, alias)
    values ('work', p_keep, v_drop.title) on conflict do nothing;
  insert into entity_aliases (entity_type, entity_id, alias)
    select 'work', p_keep, alias from entity_aliases where entity_type = 'work' and entity_id = p_drop
    on conflict do nothing;
  delete from entity_aliases where entity_type = 'work' and entity_id = p_drop;

  -- Fehlende Stammdaten vom Duplikat übernehmen, nie überschreiben.
  update works k set
    composer_id = coalesce(k.composer_id, v_drop.composer_id),
    catalog_number = coalesce(k.catalog_number, v_drop.catalog_number),
    key_signature = coalesce(k.key_signature, v_drop.key_signature),
    composition_year = coalesce(k.composition_year, v_drop.composition_year),
    description_de = coalesce(k.description_de, v_drop.description_de)
  where k.id = p_keep;

  delete from works where id = p_drop;
end;
$$;
revoke all on function public.merge_works(uuid, uuid) from public, anon, authenticated;
grant execute on function public.merge_works(uuid, uuid) to service_role;

-- 2. Kommende mphil.de-Termine neu einlesen (jetzt mit Programm).
update events set mphil_detail_synced_at = null
where website_url ilike '%mphil.de/%' and start_datetime >= now();

-- 3. Täglich 04:40 Werk-Duplikate zusammenführen.
create or replace function run_dedupe_works()
returns void
language plpgsql
as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/dedupe-works',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(), 'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000
  );
exception when others then
  raise warning 'run_dedupe_works: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('dedupe-works', '40 4 * * *', $$ select run_dedupe_works(); $$);
