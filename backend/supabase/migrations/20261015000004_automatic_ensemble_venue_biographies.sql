-- Automatische KI-Biografien für Ensembles und Venues, inklusive sichtbarem
-- Queue-Status und Sofortstart bei neu angelegten Stammdaten.

alter table public.ensembles
  add column if not exists ai_biography_status text not null default 'pending',
  add column if not exists ai_biography_checked_at timestamptz,
  add column if not exists ai_biography_error text;
alter table public.venues
  add column if not exists ai_biography_status text not null default 'pending',
  add column if not exists ai_biography_checked_at timestamptz,
  add column if not exists ai_biography_error text;

alter table public.ensembles drop constraint if exists ensembles_ai_biography_status_check;
alter table public.ensembles add constraint ensembles_ai_biography_status_check
  check (ai_biography_status in ('pending', 'processing', 'generated', 'not_known', 'error'));
alter table public.venues drop constraint if exists venues_ai_biography_status_check;
alter table public.venues add constraint venues_ai_biography_status_check
  check (ai_biography_status in ('pending', 'processing', 'generated', 'not_known', 'error'));

update public.ensembles set ai_biography_status = 'generated', ai_biography_checked_at = now()
where nullif(btrim(description_de), '') is not null;
update public.venues set ai_biography_status = 'generated', ai_biography_checked_at = now()
where nullif(btrim(description_de), '') is not null;

create index if not exists ensembles_ai_biography_queue_idx
  on public.ensembles (ai_biography_status, ai_biography_checked_at) where description_de is null;
create index if not exists venues_ai_biography_queue_idx
  on public.venues (ai_biography_status, ai_biography_checked_at) where description_de is null;

create or replace function public.claim_ensemble_ai_biographies(p_limit integer default 8)
returns setof public.ensembles language sql security definer set search_path = public as $$
  with picked as (
    select id from public.ensembles
    where nullif(btrim(description_de), '') is null and (
      ai_biography_status = 'pending'
      or (ai_biography_status = 'processing' and ai_biography_checked_at < now() - interval '15 minutes')
      or (ai_biography_status = 'error' and ai_biography_checked_at < now() - interval '1 hour')
      or (ai_biography_status = 'not_known' and ai_biography_checked_at < now() - interval '7 days')
    )
    order by ai_biography_checked_at asc nulls first, name asc for update skip locked
    limit greatest(1, least(p_limit, 20))
  )
  update public.ensembles entity set ai_biography_status = 'processing', ai_biography_checked_at = now(), ai_biography_error = null
  from picked where entity.id = picked.id returning entity.*;
$$;

create or replace function public.claim_venue_ai_biographies(p_limit integer default 8)
returns setof public.venues language sql security definer set search_path = public as $$
  with picked as (
    select id from public.venues
    where nullif(btrim(description_de), '') is null and (
      ai_biography_status = 'pending'
      or (ai_biography_status = 'processing' and ai_biography_checked_at < now() - interval '15 minutes')
      or (ai_biography_status = 'error' and ai_biography_checked_at < now() - interval '1 hour')
      or (ai_biography_status = 'not_known' and ai_biography_checked_at < now() - interval '7 days')
    )
    order by ai_biography_checked_at asc nulls first, name asc for update skip locked
    limit greatest(1, least(p_limit, 20))
  )
  update public.venues entity set ai_biography_status = 'processing', ai_biography_checked_at = now(), ai_biography_error = null
  from picked where entity.id = picked.id returning entity.*;
$$;

revoke all on function public.claim_ensemble_ai_biographies(integer) from public, anon, authenticated;
revoke all on function public.claim_venue_ai_biographies(integer) from public, anon, authenticated;
grant execute on function public.claim_ensemble_ai_biographies(integer) to service_role;
grant execute on function public.claim_venue_ai_biographies(integer) to service_role;

create or replace function public.run_ensemble_ai_biography_enrichment()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-biographies',
    body := '{"type":"ensemble","limit":8}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_key,'Authorization','Bearer ' || v_key)
  );
exception when others then raise warning 'Ensemble-Biografielauf fehlgeschlagen: %', sqlerrm;
end; $$;

create or replace function public.run_venue_ai_biography_enrichment()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-biographies',
    body := '{"type":"venue","limit":8}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_key,'Authorization','Bearer ' || v_key)
  );
exception when others then raise warning 'Venue-Biografielauf fehlgeschlagen: %', sqlerrm;
end; $$;

select cron.schedule('ensemble-ai-biography-enrichment', '1-59/3 * * * *', $$select public.run_ensemble_ai_biography_enrichment();$$);
select cron.schedule('venue-ai-biography-enrichment', '2-59/3 * * * *', $$select public.run_venue_ai_biography_enrichment();$$);

create or replace function public.enqueue_new_entity_biography()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_type text := case tg_table_name when 'ensembles' then 'ensemble' else 'venue' end;
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if nullif(btrim(new.description_de), '') is null then
    perform net.http_post(
      url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-biographies',
      body := jsonb_build_object('type', v_type, 'entityId', new.id),
      headers := jsonb_build_object('Content-Type','application/json','apikey',v_key,'Authorization','Bearer ' || v_key)
    );
  end if;
  if nullif(btrim(new.photo_url), '') is null then
    perform net.http_post(
      url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-images',
      body := jsonb_build_object('type', v_type, 'limit', 1, 'entityIds', jsonb_build_array(new.id), 'fastFallback', true),
      headers := jsonb_build_object('Content-Type','application/json','apikey',v_key,'Authorization','Bearer ' || v_key)
    );
  end if;
  return new;
exception when others then
  raise warning 'Neue Entität % konnte nicht sofort angereichert werden: %', new.id, sqlerrm;
  return new;
end; $$;

drop trigger if exists ensembles_enqueue_automatic_enrichment on public.ensembles;
create trigger ensembles_enqueue_automatic_enrichment after insert on public.ensembles
for each row execute function public.enqueue_new_entity_biography();
drop trigger if exists venues_enqueue_automatic_enrichment on public.venues;
create trigger venues_enqueue_automatic_enrichment after insert on public.venues
for each row execute function public.enqueue_new_entity_biography();
