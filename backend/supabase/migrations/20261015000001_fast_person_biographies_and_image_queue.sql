-- Schnelle KI-Biografien und faire Personenbild-Warteschlange.

alter table public.persons
  add column if not exists ai_biography_status text not null default 'pending',
  add column if not exists ai_biography_checked_at timestamptz,
  add column if not exists ai_biography_error text;

alter table public.persons drop constraint if exists persons_ai_biography_status_check;
alter table public.persons add constraint persons_ai_biography_status_check
  check (ai_biography_status in ('pending', 'processing', 'generated', 'not_known', 'error'));

update public.persons
set ai_biography_status = 'generated',
    ai_biography_checked_at = coalesce(ai_biography_checked_at, now())
where nullif(btrim(biography_de), '') is not null;

create index if not exists persons_ai_biography_queue_idx
  on public.persons (ai_biography_status, ai_biography_checked_at)
  where biography_de is null;

create or replace function public.claim_person_ai_biographies(p_limit integer default 16)
returns setof public.persons
language sql
security definer
set search_path = public
as $$
  with picked as (
    select id
    from public.persons
    where nullif(btrim(biography_de), '') is null
      and (
        ai_biography_status = 'pending'
        or (ai_biography_status = 'processing' and ai_biography_checked_at < now() - interval '15 minutes')
        or (ai_biography_status = 'error' and ai_biography_checked_at < now() - interval '1 hour')
      )
    order by ai_biography_checked_at asc nulls first, full_name asc
    for update skip locked
    limit greatest(1, least(p_limit, 40))
  )
  update public.persons p
  set ai_biography_status = 'processing',
      ai_biography_checked_at = now(),
      ai_biography_error = null
  from picked
  where p.id = picked.id
  returning p.*;
$$;

revoke all on function public.claim_person_ai_biographies(integer) from public, anon, authenticated;
grant execute on function public.claim_person_ai_biographies(integer) to service_role;

create or replace function public.reset_person_ai_biography_queue()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.biography_de is not null and new.biography_de is null then
    new.ai_biography_status := 'pending';
    new.ai_biography_checked_at := null;
    new.ai_biography_error := null;
  end if;
  return new;
end;
$$;

drop trigger if exists persons_reset_ai_biography_queue on public.persons;
create trigger persons_reset_ai_biography_queue
before update of biography_de on public.persons
for each row execute function public.reset_person_ai_biography_queue();

-- Ein echter Zeitstempel statt Sortierung nach Diagnose-Text sorgt dafür,
-- dass erfolglose Bildsuchen nicht immer wieder dieselben ersten Personen
-- auswählen und der Rest der Tabelle verhungert.
alter table public.persons add column if not exists image_search_checked_at timestamptz;
alter table public.ensembles add column if not exists image_search_checked_at timestamptz;
alter table public.venues add column if not exists image_search_checked_at timestamptz;
alter table public.festivals add column if not exists image_search_checked_at timestamptz;

create index if not exists persons_missing_image_queue_idx
  on public.persons (image_search_checked_at)
  where photo_url is null;

create or replace function public.run_person_ai_biography_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-person-biographies',
    body := '{"limit":16}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon_key,'Authorization','Bearer ' || v_anon_key)
  );
exception when others then
  raise warning 'run_person_ai_biography_enrichment fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

create or replace function public.run_person_image_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-entity-images',
    body := '{"type":"person","limit":12,"fastFallback":true}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon_key,'Authorization','Bearer ' || v_anon_key)
  );
exception when others then
  raise warning 'run_person_image_enrichment fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'person-ai-biography-enrichment',
  '*/2 * * * *',
  $$ select public.run_person_ai_biography_enrichment(); $$
);

select cron.schedule(
  'person-image-enrichment-priority',
  '*/3 * * * *',
  $$ select public.run_person_image_enrichment(); $$
);
