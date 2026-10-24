-- Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 4–7):
-- persönliches Geschmacksprofil aus dem Verhalten, erklärbare Empfehlungen,
-- gelernte Lieblingszeiten/-orte, bewusster Entdecker-Anteil und offene
-- Bewertungen nach dem Konzert.
--
-- Signale und Gewichte (pro Nutzer):
--   gemerkt (interested) 1 · "ich gehe hin" (attending) 2 · besucht 3
--   Bewertung (Sterne − 3) × 1,5 (schlechte Bewertungen ziehen ab)
--   Folgen (Person/Ensemble/Ort) 2,5
-- Ein Konzert verteilt sein Gewicht auf seine Komponist:innen, Mitwirkenden,
-- den Ort sowie Wochentag und Uhrzeit-Band.

create or replace function public.taste_signals(p_user uuid)
returns table(event_id uuid, weight numeric)
language sql stable security definer set search_path = public as $$
  with s as (
    select f.event_id, case when f.status = 'attending' then 2 else 1 end::numeric as w
      from favorites f where f.user_id = p_user
    union all
    select a.event_id, 3 from event_attendance a where a.user_id = p_user
    union all
    select r.event_id, (r.stars - 3) * 1.5 from event_ratings r where r.user_id = p_user
  )
  select s.event_id, sum(s.w) from s group by s.event_id
$$;

create or replace function public.my_taste_profile()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  if v_user is null then return '{}'::jsonb; end if;
  with sig as (select * from taste_signals(v_user)),
  composers as (
    select p.id, p.full_name as name, sum(sig.weight) as w
      from sig join event_works ew on ew.event_id = sig.event_id
      join works wk on wk.id = ew.work_id join persons p on p.id = wk.composer_id
     group by p.id, p.full_name
    union all
    select p.id, p.full_name, 2.5 from user_favorite_persons ufp join persons p on p.id = ufp.person_id
     where ufp.user_id = v_user and exists (select 1 from works where composer_id = p.id)
  ),
  artists as (
    select coalesce(ep.person_id, ep.ensemble_id) as id, coalesce(pp.full_name, en.name) as name,
           case when ep.ensemble_id is not null then 'ensemble' else 'person' end as kind, sum(sig.weight) as w
      from sig join event_participants ep on ep.event_id = sig.event_id
      left join persons pp on pp.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
     group by 1, 2, 3
    union all
    select p.id, p.full_name, 'person', 2.5 from user_favorite_persons u join persons p on p.id = u.person_id where u.user_id = v_user
    union all
    select e.id, e.name, 'ensemble', 2.5 from user_favorite_ensembles u join ensembles e on e.id = u.ensemble_id where u.user_id = v_user
  ),
  places as (
    select v.id, v.name, sum(sig.weight) as w from sig join events e on e.id = sig.event_id join venues v on v.id = e.venue_id group by v.id, v.name
    union all
    select v.id, v.name, 2.5 from user_favorite_venues u join venues v on v.id = u.venue_id where u.user_id = v_user
  ),
  times as (
    select extract(isodow from e.start_datetime at time zone 'Europe/Berlin')::int as dow,
           case when extract(hour from e.start_datetime at time zone 'Europe/Berlin') < 15 then 'tag'
                when extract(hour from e.start_datetime at time zone 'Europe/Berlin') < 19 then 'vorabend'
                else 'abend' end as band,
           sum(sig.weight) as w
      from sig join events e on e.id = sig.event_id group by 1, 2
  )
  select jsonb_build_object(
    'composers', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'weight', w) order by w desc)
                            from (select id, name, sum(w) w from composers group by id, name having sum(w) > 0 order by sum(w) desc limit 12) c), '[]'),
    'artists', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'kind', kind, 'weight', w) order by w desc)
                          from (select id, name, kind, sum(w) w from artists group by id, name, kind having sum(w) > 0 order by sum(w) desc limit 12) a), '[]'),
    'venues', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'weight', w) order by w desc)
                         from (select id, name, sum(w) w from places group by id, name having sum(w) > 0 order by sum(w) desc limit 6) v), '[]'),
    'weekdays', coalesce((select jsonb_object_agg(dow, w) from (select dow, sum(w) w from times group by dow) d), '{}'),
    'bands', coalesce((select jsonb_object_agg(band, w) from (select band, sum(w) w from times group by band) b), '{}'),
    'signal_count', (select count(*) from sig)
  ) into v_result;
  return v_result;
end;
$$;

-- Begründung + persönlicher Zusatzwert für eine Liste von Konzerten
-- (Home-"Für dich", Suche). Die stärkste passende Begründung gewinnt.
create or replace function public.taste_reasons(p_event_ids uuid[])
returns table(event_id uuid, reason text, boost numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  v_profile jsonb := my_taste_profile();
begin
  if coalesce((v_profile->>'signal_count')::int, 0) = 0
     and jsonb_array_length(coalesce(v_profile->'artists', '[]')) = 0 then
    return;
  end if;
  return query
  with prof_c as (select (x->>'id')::uuid id, x->>'name' name, (x->>'weight')::numeric w from jsonb_array_elements(v_profile->'composers') x),
       prof_a as (select (x->>'id')::uuid id, x->>'name' name, (x->>'weight')::numeric w from jsonb_array_elements(v_profile->'artists') x),
       prof_v as (select (x->>'id')::uuid id, x->>'name' name, (x->>'weight')::numeric w from jsonb_array_elements(v_profile->'venues') x),
       cand as (
         select e.id as eid, 'artist'::text as k, a.name, a.w * 1.2 as w
           from unnest(p_event_ids) eid0 join events e on e.id = eid0
           join event_participants ep on ep.event_id = e.id
           join prof_a a on a.id = coalesce(ep.person_id, ep.ensemble_id)
         union all
         select e.id, 'composer', c.name, c.w
           from unnest(p_event_ids) eid0 join events e on e.id = eid0
           join event_works ew on ew.event_id = e.id join works wk on wk.id = ew.work_id
           join prof_c c on c.id = wk.composer_id
         union all
         select e.id, 'venue', v.name, v.w * 0.6
           from unnest(p_event_ids) eid0 join events e on e.id = eid0 join prof_v v on v.id = e.venue_id
       ),
       timefit as (
         select e.id as eid,
                coalesce((v_profile->'weekdays'->>(extract(isodow from e.start_datetime at time zone 'Europe/Berlin')::int)::text)::numeric, 0) * 0.15
              + coalesce((v_profile->'bands'->>(case when extract(hour from e.start_datetime at time zone 'Europe/Berlin') < 15 then 'tag'
                                                     when extract(hour from e.start_datetime at time zone 'Europe/Berlin') < 19 then 'vorabend'
                                                     else 'abend' end))::numeric, 0) * 0.1 as w
           from unnest(p_event_ids) eid0 join events e on e.id = eid0
       ),
       best as (select distinct on (eid) eid, k, name, w from cand order by eid, w desc),
       total as (select eid, sum(w) w from cand group by eid)
  select t.eid,
         case b.k when 'artist' then 'Weil du ' || b.name || ' magst'
                  when 'composer' then 'Weil du gern ' || b.name || ' hörst'
                  when 'venue' then 'In deinem Lieblingsort ' || b.name
         end,
         round(coalesce(tot.w, 0) + t.w, 2)
    from timefit t
    left join best b on b.eid = t.eid
    left join total tot on tot.eid = t.eid
   where b.eid is not null or t.w > 0;
end;
$$;

-- Entdecker-Anteil: beliebte kommende Konzerte, deren Komponist:innen und
-- Mitwirkende NICHT im eigenen Profil vorkommen (gegen die Filterblase).
create or replace function public.discover_outside_taste(p_city_id uuid default null, p_limit int default 8)
returns setof uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v_profile jsonb := my_taste_profile();
begin
  return query
  with known as (
    select (x->>'id')::uuid id from jsonb_array_elements(coalesce(v_profile->'composers', '[]')) x
    union select (x->>'id')::uuid from jsonb_array_elements(coalesce(v_profile->'artists', '[]')) x
  ),
  pool as (
    select e.id,
           (select count(*) from favorites f where f.event_id = e.id) as popularity
      from events e
     where e.status in ('scheduled', 'sold_out')
       and e.start_datetime between now() + interval '2 hours' and now() + interval '30 days'
       and (p_city_id is null or e.city_id = p_city_id)
       and coalesce(array_length(e.image_urls, 1), 0) > 0
       and not exists (select 1 from favorites f where f.event_id = e.id and f.user_id = auth.uid())
       and not exists (select 1 from event_participants ep join known k on k.id in (ep.person_id, ep.ensemble_id) where ep.event_id = e.id)
       and not exists (select 1 from event_works ew join works wk on wk.id = ew.work_id join known k on k.id = wk.composer_id where ew.event_id = e.id)
  )
  select id from pool order by popularity desc, random() limit least(greatest(p_limit, 1), 20);
end;
$$;

-- Konzerte, die man gemerkt/besucht hat, die vorbei sind (2 h – 4 Tage)
-- und noch keine eigene Bewertung haben – für die Nachklang-Karte.
create or replace function public.pending_ratings()
returns setof uuid
language sql stable security definer set search_path = public as $$
  select e.id
    from events e
   where e.start_datetime between now() - interval '4 days' and now() - interval '2 hours'
     and (exists (select 1 from favorites f where f.event_id = e.id and f.user_id = auth.uid())
          or exists (select 1 from event_attendance a where a.event_id = e.id and a.user_id = auth.uid()))
     and not exists (select 1 from event_ratings r where r.event_id = e.id and r.user_id = auth.uid())
   order by e.start_datetime desc
   limit 3
$$;

revoke all on function public.taste_signals(uuid) from public, anon, authenticated;
grant execute on function public.my_taste_profile() to authenticated;
grant execute on function public.taste_reasons(uuid[]) to authenticated;
grant execute on function public.discover_outside_taste(uuid, int) to authenticated, anon;
grant execute on function public.pending_ratings() to authenticated;
