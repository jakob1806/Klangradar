-- "Neu angekündigt"-Modul (Discovery & Engagement, Nutzeranfrage): eigener
-- Home-Bereich für kürzlich neu ins System aufgenommene, noch bevorstehende
-- Events — bewusst ungefiltert nach Follow-Status (anders als
-- entity_news_events, das nur gefolgte Venues/Personen/Ensembles abdeckt).
-- Funktioniert auch ohne Login (reine Zeit-Sortierung, kein Personalisierungs-
-- Bedarf), blendet für eingeloggte Nutzer aber dieselben content_dismissals
-- aus wie die anderen Module (Eligibility Filtering muss überall greifen).
create or replace function newly_announced_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[]
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  return query
    select
      e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status, e.start_datetime,
      v.id,
      jsonb_build_object('name', v.name),
      coalesce(
        (
          select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
          from event_genres eg
          join genres g on g.id = eg.genre_id
          where eg.event_id = e.id
        ),
        '[]'::jsonb
      ),
      e.image_urls
    from events e
    join venues v on v.id = e.venue_id
    where e.status = 'scheduled'
      and e.start_datetime >= now()
      and e.created_at >= now() - interval '5 days'
      and (v_uid is null or e.id not in (
        select entity_id from content_dismissals where user_id = v_uid and entity_type = 'event'
      ))
      and (v_uid is null or e.venue_id not in (
        select entity_id from content_dismissals where user_id = v_uid and entity_type = 'venue'
      ))
    order by e.created_at desc, e.start_datetime
    limit p_result_limit;
end;
$$;

grant execute on function newly_announced_events(int) to anon, authenticated;
