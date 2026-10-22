-- Erstellt von Claude Code. Onboarding: die relevantesten Personen,
-- Ensembles und Spielstätten zuerst statt alphabetisch.
-- Punkte: kommende Konzerte x3 + Follower x2 + 5 für ein Foto.
create or replace function public.onboarding_profile_ranking(p_kind text)
returns table (id uuid, score bigint)
language sql
stable
security definer
set search_path = public
as $$
  with upcoming as (
    select id, venue_id from events where start_datetime >= now() and status <> 'draft'
  )
  select p.id,
    3 * (select count(distinct ep.event_id) from event_participants ep join upcoming u on u.id = ep.event_id where ep.person_id = p.id)
    + 2 * (select count(*) from user_favorite_persons f where f.person_id = p.id)
    + case when p.photo_url is not null then 5 else 0 end
  from persons p where p_kind = 'person'
  union all
  select e.id,
    3 * (select count(distinct ep.event_id) from event_participants ep join upcoming u on u.id = ep.event_id where ep.ensemble_id = e.id)
    + 2 * (select count(*) from user_favorite_ensembles f where f.ensemble_id = e.id)
    + case when e.photo_url is not null then 5 else 0 end
  from ensembles e where p_kind = 'ensemble'
  union all
  select v.id,
    3 * (select count(*) from upcoming u where u.venue_id = v.id)
    + 2 * (select count(*) from user_favorite_venues f where f.venue_id = v.id)
    + case when v.photo_url is not null then 5 else 0 end
  from venues v where p_kind = 'venue';
$$;
grant execute on function public.onboarding_profile_ranking(text) to anon, authenticated;
