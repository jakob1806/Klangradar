-- Werke können wie Personen, Ensembles und Venues als Nutzerinteresse
-- gespeichert werden. Die zusammengesetzte PK verhindert doppelte Auswahl.
create table if not exists public.user_favorite_works (
  user_id uuid not null references public.profiles(id) on delete cascade,
  work_id uuid not null references public.works(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, work_id)
);

alter table public.user_favorite_works enable row level security;

drop policy if exists "Nutzer verwaltet eigene Interessen (Werke)"
  on public.user_favorite_works;
create policy "Nutzer verwaltet eigene Interessen (Werke)"
  on public.user_favorite_works
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Die Auswahl ist nicht nur kosmetisch: Veranstaltungen mit einem
-- favorisierten Werk werden im personalisierten Feed bevorzugt.
insert into public.home_feed_ranking_weights (key, weight, description)
values ('work_interest', 5, 'Bonus wenn ein favorisiertes Werk im Veranstaltungsprogramm steht')
on conflict (key) do nothing;

drop function if exists public.recommended_events(int);

create function public.recommended_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[],
  rank_score numeric, rank_reason text[]
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  w_genre numeric;
  w_work numeric;
  w_venue numeric;
  w_person numeric;
  w_ensemble numeric;
  w_popularity numeric;
  w_time_decay_days numeric;
begin
  select weight into w_genre from public.home_feed_ranking_weights where key = 'genre_interest';
  select weight into w_work from public.home_feed_ranking_weights where key = 'work_interest';
  select weight into w_venue from public.home_feed_ranking_weights where key = 'venue_interest';
  select weight into w_person from public.home_feed_ranking_weights where key = 'person_interest';
  select weight into w_ensemble from public.home_feed_ranking_weights where key = 'ensemble_interest';
  select weight into w_popularity from public.home_feed_ranking_weights where key = 'popularity_scale';
  select weight into w_time_decay_days from public.home_feed_ranking_weights where key = 'time_decay_divisor_days';

  return query
    with scored as (
      select
        e.id, e.slug, e.title, e.subtitle, e.is_free,
        e.remaining_tickets_status, e.start_datetime,
        v.id as venue_id,
        jsonb_build_object('name', v.name) as venues,
        coalesce(
          (
            select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
            from public.event_genres eg
            join public.genres g on g.id = eg.genre_id
            where eg.event_id = e.id
          ),
          '[]'::jsonb
        ) as event_genres,
        e.image_urls,
        (v_uid is not null and exists (
          select 1 from public.event_genres eg
          join public.profile_interest_genres pig on pig.genre_id = eg.genre_id
          where eg.event_id = e.id and pig.user_id = v_uid
        )) as has_genre_match,
        (v_uid is not null and exists (
          select 1 from public.event_works ew
          join public.user_favorite_works ufw on ufw.work_id = ew.work_id
          where ew.event_id = e.id and ufw.user_id = v_uid
        )) as has_work_match,
        (v_uid is not null and (
          exists (
            select 1 from public.user_favorite_venues ufv
            where ufv.venue_id = e.venue_id and ufv.user_id = v_uid
          )
          or exists (
            select 1 from public.event_views ev
            join public.events e2 on e2.id = ev.event_id
            where e2.venue_id = e.venue_id and ev.user_id = v_uid
          )
        )) as has_venue_match,
        (v_uid is not null and exists (
          select 1 from public.event_participants ep
          join public.user_favorite_persons ufp on ufp.person_id = ep.person_id
          where ep.event_id = e.id and ufp.user_id = v_uid
        )) as has_person_match,
        (v_uid is not null and exists (
          select 1 from public.event_participants ep
          join public.user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
          where ep.event_id = e.id and ufe.user_id = v_uid
        )) as has_ensemble_match,
        (select ln(1 + count(*)::float) from public.favorites f where f.event_id = e.id) as popularity_raw
      from public.events e
      join public.venues v on v.id = e.venue_id
      where e.status = 'scheduled' and e.start_datetime >= now()
    )
    select
      s.id, s.slug, s.title, s.subtitle, s.is_free,
      s.remaining_tickets_status, s.start_datetime,
      s.venue_id, s.venues, s.event_genres, s.image_urls,
      round((
        (case when has_genre_match then w_genre else 0 end)
        + (case when has_work_match then w_work else 0 end)
        + (case when has_venue_match then w_venue else 0 end)
        + (case when has_person_match then w_person else 0 end)
        + (case when has_ensemble_match then w_ensemble else 0 end)
        + coalesce(popularity_raw, 0) * w_popularity
        - (extract(epoch from (s.start_datetime - now())) / 86400.0 / w_time_decay_days)
      )::numeric, 3) as rank_score,
      array_remove(array[
        case when has_genre_match then 'genre_interesse' end,
        case when has_work_match then 'werk_interesse' end,
        case when has_venue_match then 'venue_interesse' end,
        case when has_person_match then 'mitwirkende_interesse' end,
        case when has_ensemble_match then 'ensemble_interesse' end,
        case when coalesce(popularity_raw, 0) > 0 then 'popularitaet' end
      ], null) as rank_reason
    from scored s
    order by rank_score desc, s.start_datetime
    limit p_result_limit;
end;
$$;

grant execute on function public.recommended_events(int) to anon, authenticated;
