-- Erstellt von Claude Code (Nutzerwunsch 27.10.2026): Bei Konzerten mit bis
-- zu vier Mitwirkenden zeigt die App alle unter "Wer spielt?" mit
-- Kurzbiografie. Dafür:
-- 1. Personen/Ensembles, die bei kommenden Konzerten auftreten und noch
--    keine Biografie haben, kommen in der KI-Biografie-Queue zuerst dran.
-- 2. Wer bisher als "not_known" markiert war, wird jetzt einmal neu
--    versucht – die Worker nutzen ab diesem PR Wikipedia als Rückfall.
-- 3. Für kommende Mitwirkende gilt ein kürzerer Neuversuch (1 statt 7 Tage).

create or replace function public.claim_person_ai_biographies(p_limit integer default 16)
returns setof public.persons
language sql
security definer
set search_path = public
as $$
  with upcoming as (
    select distinct ep.person_id as id
    from public.event_participants ep
    join public.events e on e.id = ep.event_id
    where ep.person_id is not null and e.start_datetime > now() and e.status = 'scheduled'
  ),
  picked as (
    select p.id
    from public.persons p
    left join upcoming u on u.id = p.id
    where nullif(btrim(p.biography_de), '') is null
      and (
        p.ai_biography_status = 'pending'
        or (p.ai_biography_status = 'processing' and p.ai_biography_checked_at < now() - interval '15 minutes')
        or (p.ai_biography_status = 'error' and p.ai_biography_checked_at < now() - interval '1 hour')
        or (p.ai_biography_status = 'not_known' and p.ai_biography_checked_at
              < now() - case when u.id is not null then interval '1 day' else interval '7 days' end)
      )
    order by (u.id is not null) desc, p.ai_biography_checked_at asc nulls first, p.full_name asc
    for update of p skip locked
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

create or replace function public.claim_ensemble_ai_biographies(p_limit integer default 8)
returns setof public.ensembles
language sql
security definer
set search_path = public
as $$
  with upcoming as (
    select distinct ep.ensemble_id as id
    from public.event_participants ep
    join public.events e on e.id = ep.event_id
    where ep.ensemble_id is not null and e.start_datetime > now() and e.status = 'scheduled'
  ),
  picked as (
    select en.id
    from public.ensembles en
    left join upcoming u on u.id = en.id
    where nullif(btrim(en.description_de), '') is null and (
      en.ai_biography_status = 'pending'
      or (en.ai_biography_status = 'processing' and en.ai_biography_checked_at < now() - interval '15 minutes')
      or (en.ai_biography_status = 'error' and en.ai_biography_checked_at < now() - interval '1 hour')
      or (en.ai_biography_status = 'not_known' and en.ai_biography_checked_at
            < now() - case when u.id is not null then interval '1 day' else interval '7 days' end)
    )
    order by (u.id is not null) desc, en.ai_biography_checked_at asc nulls first, en.name asc
    for update of en skip locked
    limit greatest(1, least(p_limit, 40))
  )
  update public.ensembles entity set ai_biography_status = 'processing', ai_biography_checked_at = now(), ai_biography_error = null
  from picked where entity.id = picked.id returning entity.*;
$$;

revoke all on function public.claim_ensemble_ai_biographies(integer) from public, anon, authenticated;
grant execute on function public.claim_ensemble_ai_biographies(integer) to service_role;

-- Einmaliger Neuversuch für alle kommenden Mitwirkenden ohne Biografie.
update public.persons p set ai_biography_status = 'pending', ai_biography_checked_at = null
where nullif(btrim(p.biography_de), '') is null and p.ai_biography_status = 'not_known'
  and exists (select 1 from public.event_participants ep join public.events e on e.id = ep.event_id
              where ep.person_id = p.id and e.start_datetime > now());

update public.ensembles en set ai_biography_status = 'pending', ai_biography_checked_at = null
where nullif(btrim(en.description_de), '') is null and en.ai_biography_status = 'not_known'
  and exists (select 1 from public.event_participants ep join public.events e on e.id = ep.event_id
              where ep.ensemble_id = en.id and e.start_datetime > now());
