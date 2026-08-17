-- Neue Personen sofort automatisch mit Biografie und Bild versorgen.
-- Die bestehenden Crons bleiben als Sicherheitsnetz und für den Altbestand.

create or replace function public.enqueue_new_person_enrichment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if nullif(btrim(new.biography_de), '') is null then
    perform net.http_post(
      url := v_supabase_url || '/functions/v1/enrich-entity-oncall',
      body := jsonb_build_object('entityType', 'person', 'entityId', new.id),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', v_anon_key,
        'Authorization', 'Bearer ' || v_anon_key
      )
    );
  end if;

  if nullif(btrim(new.photo_url), '') is null then
    perform net.http_post(
      url := v_supabase_url || '/functions/v1/enrich-entity-images',
      body := jsonb_build_object(
        'type', 'person',
        'limit', 1,
        'entityIds', jsonb_build_array(new.id),
        'fastFallback', true
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', v_anon_key,
        'Authorization', 'Bearer ' || v_anon_key
      )
    );
  end if;

  return new;
exception when others then
  -- Ein externer KI-/Netzwerkfehler darf den eigentlichen Personen-Import
  -- niemals zurückrollen. Die regulären Hintergrund-Crons übernehmen dann.
  raise warning 'Neue Person % konnte nicht sofort angereichert werden: % (%)', new.id, sqlerrm, sqlstate;
  return new;
end;
$$;

drop trigger if exists persons_enqueue_automatic_enrichment on public.persons;
create trigger persons_enqueue_automatic_enrichment
after insert on public.persons
for each row execute function public.enqueue_new_person_enrichment();

-- Der verbesserte Kontext-Prompt bekommt den bisher erfolglosen Altbestand
-- automatisch noch einmal. Die Queue schreibt weiterhin ausschließlich in
-- leere Biografiefelder und überschreibt keine redaktionellen Texte.
update public.persons
set ai_biography_status = 'pending',
    ai_biography_checked_at = null,
    ai_biography_error = null
where nullif(btrim(biography_de), '') is null
  and ai_biography_status in ('not_known', 'error');

-- Künftig werden nicht erkannte Personen nach einer Woche erneut probiert;
-- Modellwissen und der verknüpfte Veranstaltungskontext entwickeln sich.
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
        or (ai_biography_status = 'not_known' and ai_biography_checked_at < now() - interval '7 days')
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
