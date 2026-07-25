-- Home-Feed Phase A (siehe docs/08-home-feed-recommendation-algorithm.md,
-- Abschnitt 10): log-skalierte Popularität in recommended_events() + eine
-- neue discovery_events()-Function für das "Entdecken"-Modul, gebaut auf
-- der bereits vorhandenen events.embedding-Spalte (siehe
-- 20260819000009_embeddings.sql) — bisher nirgends in der App genutzt.

-- Log-Skalierung: 0.5*count() lässt bei wachsendem Katalog ein einzelnes
-- virales Event alle anderen Signale dominieren (siehe Doc, Abschnitt 4.1)
-- — 0.5*ln(1+count()) wächst viel langsamer, ohne Popularität als Signal
-- ganz zu verlieren. Bei aktuell kleinen Favoriten-Zahlen fast identisch
-- zur alten Formel, wird aber wichtig sobald die App wächst.
create or replace function recommended_events(p_result_limit int default 10)
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
    where e.status = 'scheduled' and e.start_datetime >= now()
    order by
      (
        -- Genre-Interesse
        (case when v_uid is not null and exists (
          select 1 from event_genres eg
          join profile_interest_genres pig on pig.genre_id = eg.genre_id
          where eg.event_id = e.id and pig.user_id = v_uid
        ) then 5 else 0 end)
        +
        -- Venue-Interesse ODER Venue schon besucht
        (case when v_uid is not null and (
          exists (
            select 1 from user_favorite_venues ufv
            where ufv.venue_id = e.venue_id and ufv.user_id = v_uid
          )
          or exists (
            select 1 from event_views ev
            join events e2 on e2.id = ev.event_id
            where e2.venue_id = e.venue_id and ev.user_id = v_uid
          )
        ) then 3 else 0 end)
        +
        -- Komponist/Mitwirkende-Interesse (Personen)
        (case when v_uid is not null and exists (
          select 1 from event_participants ep
          join user_favorite_persons ufp on ufp.person_id = ep.person_id
          where ep.event_id = e.id and ufp.user_id = v_uid
        ) then 4 else 0 end)
        +
        -- Ensemble-Interesse
        (case when v_uid is not null and exists (
          select 1 from event_participants ep
          join user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
          where ep.event_id = e.id and ufe.user_id = v_uid
        ) then 4 else 0 end)
        +
        -- Popularität (log-skaliert, siehe Kommentar oben)
        (select ln(1 + count(*)::float) * 0.5 from favorites f where f.event_id = e.id)
        -
        -- zeitliche Nähe: Events weiter in der Zukunft leicht abgewertet
        (extract(epoch from (e.start_datetime - now())) / 86400.0 / 30.0)
      ) desc,
      e.start_datetime
    limit p_result_limit;
end;
$$;

-- "Entdecken"-Modul (docs/08-..., Abschnitt 4.3): Kandidaten über
-- semantische Ähnlichkeit (Cosinus-Distanz der Embeddings) zu den
-- zuletzt favorisierten/angesehenen Events der Person, NICHT über
-- Genre/Venue-Regeln wie recommended_events() — soll bewusst auch
-- Ensembles/Venues zeigen, die die Person noch nicht kennt.
--
-- Ohne eingeloggte Person oder ohne jede Favoriten-/Ansichts-Historie gibt
-- es keinen sinnvollen Ausgangspunkt — liefert dann bewusst eine leere
-- Liste statt beliebiger Events (der Home-Feed überspringt ein Modul mit
-- zu wenigen Kandidaten ohnehin, siehe docs/08, Abschnitt 3).
--
-- "Zu naheliegend"-Filter (Abschnitt 4.3): Kandidaten, deren Venue UND
-- Komponist/Mitwirkende:r schon beide bekannt sind (favorisiert),
-- ausgeschlossen — sonst wäre es nur eine zweite Kopie von
-- recommended_events() statt echter Entdeckung. Der in der Doku
-- zusätzlich vorgesehene Ensemble-Teil dieses Filters braucht
-- profile_interest_ensembles (docs/08, Abschnitt 9, Phase B) und ist hier
-- bewusst noch nicht Teil der Bedingung.
create or replace function discovery_events(p_result_limit int default 10)
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
  v_has_seeds boolean;
begin
  if v_uid is null then
    return;
  end if;

  select exists (
    select 1 from events e
    where e.embedding is not null
      and e.id in (
        select event_id from favorites where user_id = v_uid
        union
        select event_id from event_views where user_id = v_uid
      )
  ) into v_has_seeds;

  if not v_has_seeds then
    return;
  end if;

  return query
    with seed_ids as (
      (
        select event_id, created_at as ts from favorites where user_id = v_uid
        union
        select event_id, viewed_at as ts from event_views where user_id = v_uid
      )
      order by ts desc
      limit 5
    ),
    seed_embeddings as (
      select e.embedding from events e
      join seed_ids s on s.event_id = e.id
      where e.embedding is not null
    ),
    already_seen as (
      select event_id from favorites where user_id = v_uid
      union
      select event_id from event_views where user_id = v_uid
    )
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
      and e.embedding is not null
      and e.id not in (select event_id from already_seen)
      and not (
        exists (
          select 1 from user_favorite_venues ufv
          where ufv.venue_id = e.venue_id and ufv.user_id = v_uid
        )
        and exists (
          select 1 from event_participants ep
          join user_favorite_persons ufp on ufp.person_id = ep.person_id
          where ep.event_id = e.id and ufp.user_id = v_uid
        )
      )
    order by (select min(e.embedding <=> se.embedding) from seed_embeddings se) asc
    limit p_result_limit;
end;
$$;

grant execute on function discovery_events(int) to anon, authenticated;
