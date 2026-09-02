-- Nutzerfeedback: "Datenanbindung scheint nicht richtig zu funktionieren,
-- auf 'kommende Konzerte in Isarphilharmonie' findet er nichts. Nur auf
-- ausgewählter Stadt basierend." -- coach_search_events matchte p_filters
-- ->>'query' bislang nur gegen Titel/Untertitel/Genre, nie gegen den
-- Venue-Namen. Ein Venue-Name landet aber typischerweise genau in diesem
-- freien Textfeld (siehe klangradar-coach/index.ts PLAN_FUNCTION). Gleiche
-- Kandidaten-/Scoring-Logik wie zuvor, nur die query-Bedingung erweitert.
create or replace function coach_search_events(p_filters jsonb default '{}'::jsonb,p_limit int default 8)
returns jsonb language sql stable security invoker as $$
with candidates as (
  select e.id,e.slug,e.title,e.subtitle,e.start_datetime,e.duration_minutes,e.price_min,e.price_max,e.price_currency,e.is_free,
    e.remaining_tickets_status,e.ticket_url,e.website_url,
    coalesce(e.image_urls[1],v.photo_url) image_url,
    v.id venue_id,v.name venue_name,v.address_city,
    array_remove(array[
      case when e.is_free then 'Eintritt frei' end,
      case when exists(select 1 from user_favorite_venues f where f.user_id=auth.uid() and f.venue_id=e.venue_id) then 'Du folgst diesem Ort' end,
      case when exists(select 1 from event_genres eg join profile_interest_genres i using(genre_id) where eg.event_id=e.id and i.user_id=auth.uid()) then 'Passt zu deinen Interessen' end,
      case when exists(select 1 from event_participants ep join user_favorite_persons f using(person_id) where ep.event_id=e.id and f.user_id=auth.uid()) then 'Mit einer Person, der du folgst' end,
      case when exists(select 1 from event_participants ep join user_favorite_ensembles f using(ensemble_id) where ep.event_id=e.id and f.user_id=auth.uid()) then 'Mit einem Ensemble, dem du folgst' end,
      case when not exists(select 1 from favorites f join events old on old.id=f.event_id where f.user_id=auth.uid() and exists(select 1 from event_genres a join event_genres b using(genre_id) where a.event_id=e.id and b.event_id=old.id)) then 'Eine neue Richtung für dich' end
    ],null) reasons
  from events e join venues v on v.id=e.venue_id
  where e.status='scheduled'
    and e.start_datetime>=coalesce((p_filters->>'date_from')::timestamptz,now())
    and e.start_datetime<coalesce((p_filters->>'date_to')::timestamptz,now()+interval '90 days')
    and (p_filters->>'max_budget' is null or e.is_free or e.price_min is null or e.price_min<=(p_filters->>'max_budget')::numeric)
    and (p_filters->>'city' is null or v.address_city ilike '%'||(p_filters->>'city')||'%')
    and (coalesce((p_filters->>'exclude_opera')::boolean,false)=false or coalesce(e.category,'')<>'opera')
    and (p_filters->>'query' is null or e.title ilike '%'||(p_filters->>'query')||'%' or coalesce(e.subtitle,'') ilike '%'||(p_filters->>'query')||'%'
      or v.name ilike '%'||(p_filters->>'query')||'%'
      or exists(
      select 1 from event_genres eg join genres g on g.id=eg.genre_id where eg.event_id=e.id and (g.label_de ilike '%'||(p_filters->>'query')||'%' or g.slug ilike '%'||(p_filters->>'query')||'%')))
)
select coalesce(jsonb_agg(to_jsonb(x) order by x.personal_score desc,x.start_datetime),'[]'::jsonb)
from (select c.*,cardinality(reasons) personal_score from candidates c order by personal_score desc,start_datetime limit greatest(1,least(p_limit,20))) x;
$$;
grant execute on function coach_search_events(jsonb,int) to authenticated;
