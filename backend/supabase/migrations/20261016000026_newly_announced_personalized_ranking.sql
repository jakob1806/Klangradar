-- Empfehlungssystem-Anfrage (Punkt 26, "Neu angekündigt" —
-- "interessenbasiert", "Follow-basiert"): newly_announced_events() war
-- bewusst ungefiltert (siehe Kommentar in 20261016000013 — Discovery-
-- Charakter, nicht dieselbe enge Zielgruppe wie entity_news_events()).
-- Diese Anfrage will trotzdem eine Personalisierung, aber ein harter Filter
-- würde das Modul zu entity_news_events() duplizieren (das schon exakt
-- "neue Events an gefolgten Venues/Personen/Ensembles" abdeckt) und den
-- Discovery-Zweck zunichtemachen. Kompromiss: interessen-/follow-
-- passende neue Events werden VORGEZOGEN (Sortierung), aber weiterhin alle
-- neuen Events gezeigt — "interessenbasiert" als Rankingsignal, nicht als
-- Ausschlusskriterium.
drop function if exists newly_announced_events(int);

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
    order by
      (v_uid is not null and (
        exists (select 1 from user_favorite_venues ufv where ufv.venue_id = e.venue_id and ufv.user_id = v_uid)
        or exists (
          select 1 from event_participants ep join user_favorite_persons ufp on ufp.person_id = ep.person_id
          where ep.event_id = e.id and ufp.user_id = v_uid
        )
        or exists (
          select 1 from event_participants ep join user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
          where ep.event_id = e.id and ufe.user_id = v_uid
        )
        or exists (
          select 1 from event_works ew join user_favorite_works ufw on ufw.work_id = ew.work_id
          where ew.event_id = e.id and ufw.user_id = v_uid
        )
        or (e.festival_id is not null and exists (
          select 1 from user_favorite_festivals uff where uff.festival_id = e.festival_id and uff.user_id = v_uid
        ))
        or exists (
          select 1 from event_genres eg join profile_interest_genres pig on pig.genre_id = eg.genre_id
          where eg.event_id = e.id and pig.user_id = v_uid
        )
      )) desc,
      e.created_at desc, e.start_datetime
    limit p_result_limit;
end;
$$;

grant execute on function newly_announced_events(int) to anon, authenticated;
