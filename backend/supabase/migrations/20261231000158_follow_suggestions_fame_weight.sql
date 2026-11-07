-- Folgen-Vorschläge: Bekanntheit stärker gewichten (Deckel 6 → 10, Faktor 1.4),
-- lokale Konzertzahl hebt Unbekannte nicht mehr über Weltstars.
create or replace function public.onboarding_follow_suggestions(p_kind text, p_city_id uuid DEFAULT NULL::uuid, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 60)
 RETURNS TABLE(id uuid, label text, photo_url text, upcoming_in_city integer, upcoming_total integer, followers integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with params as (
    select
      coalesce(
        p_city_id,
        (select pr.active_city_id from profiles pr where pr.id = auth.uid())
      ) as city_id,
      nullif(btrim(p_query), '') as q,
      least(greatest(coalesce(p_limit, 60), 1), 200) as lim
  ),
  base as (
    select p.id, p.full_name as label, p.photo_url,
           (coalesce(p.is_deceased, false) or p.death_date is not null or p.birth_date < date '1920-01-01') as deceased,
           (p.member_of_ensemble_id is not null) as ensemble_member
    from persons p
    where p_kind = 'person'
    union all
    select en.id, en.name, en.photo_url, false, false
    from ensembles en
    where p_kind = 'ensemble'
      and not coalesce(en.is_resolution_placeholder, false)
      and not coalesce(en.is_family_root, false)
    union all
    select v.id, v.name, v.photo_url, false, false
    from venues v
    where p_kind = 'venue'
  ),
  event_counts as (
    select c.entity_id,
           sum(c.n) filter (where c.city_id = (select city_id from params)) as in_city,
           sum(c.n) as total
    from entity_upcoming_counts c
    where c.kind = p_kind
    group by c.entity_id
  ),
  follower_counts as (
    select f.entity_id, f.n from entity_follower_counts f where f.kind = p_kind
  ),
  scored as (
    select b.id, b.label, b.photo_url, b.deceased,
           coalesce(ec.in_city, 0)::int as in_city,
           coalesce(ec.total, 0)::int as total,
           coalesce(fc.n, 0)::int as followers,
           coalesce(ep.score, 0) as fame,
           coalesce(ep.boost, 0) as boost,
           1.4 * least(coalesce(ep.score, 0), 10) + coalesce(ep.boost, 0)
             + case when coalesce(ep.wiki_views, 0) > 0 then 1.2 else 0.6 end * ln(1 + coalesce(ec.in_city, 0))
             + 0.35 * ln(1 + coalesce(ec.total, 0))
             + 0.8 * ln(1 + coalesce(fc.n, 0))
             + case when b.photo_url is not null then 0.6 else -1.5 end
             - case when b.ensemble_member and coalesce(ep.wiki_views, 0) = 0 then 1.5 else 0 end
             as rank_score
    from base b
    left join event_counts ec on ec.entity_id = b.id
    left join follower_counts fc on fc.entity_id = b.id
    left join entity_prominence ep on ep.kind = p_kind and ep.entity_id = b.id
    where b.label is not null
  )
  select s.id, s.label, s.photo_url, s.in_city, s.total, s.followers
  from scored s
  cross join params pa
  where case
          when pa.q is null then not s.deceased and s.total > 0 and s.boost > -10
          else s.label ilike '%' || pa.q || '%'
        end
  order by
    case when pa.q is null then 0
         when s.label ilike pa.q || '%' then 0
         when s.label ilike '% ' || pa.q || '%' then 1
         else 2 end,
    s.rank_score desc,
    s.label
  limit (select lim from params);
$function$;
grant execute on function public.onboarding_follow_suggestions(text, uuid, text, int) to anon, authenticated;
