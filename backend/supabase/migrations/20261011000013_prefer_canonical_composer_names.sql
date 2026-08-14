-- Wenn zu einem Komponisten bereits Kurz- und Langformen existieren, darf
-- ein exakter Treffer auf die Kurzform nicht weiterhin dieses Dublettenprofil
-- bevorzugen. Die vollständigste Namensform wird als Matching-Ziel gerankt;
-- die eigentliche Zusammenführung bleibt der redaktionellen Prüfung vorbehalten.
create or replace function find_matching_person(
  p_name text,
  p_similarity_threshold numeric default 0.5,
  p_result_limit int default 3
)
returns table (id uuid, full_name text, similarity numeric)
language sql
stable
as $$
  with input as (
    select trim(regexp_replace(lower(p_name), '[^a-z0-9]+', ' ', 'g')) as n
  ),
  composer_base as (
    select distinct p.id, p.full_name, p.is_verified,
      trim(regexp_replace(lower(p.full_name), '[^a-z0-9]+', ' ', 'g')) as n
    from persons p
    where 'komponist' = any(p.roles)
       or exists (select 1 from works w where w.composer_id = p.id)
  ),
  composer_people as (
    select cb.*,
      regexp_replace(cb.n, '^.* ', '') as surname,
      1 + length(cb.n) - length(replace(cb.n, ' ', '')) as token_count,
      row_number() over (
        partition by regexp_replace(cb.n, '^.* ', '')
        order by
          (1 + length(cb.n) - length(replace(cb.n, ' ', ''))) desc,
          length(cb.n) desc,
          cb.is_verified desc,
          cb.full_name
      ) as canonical_rank,
      max(1 + length(cb.n) - length(replace(cb.n, ' ', ''))) over (
        partition by regexp_replace(cb.n, '^.* ', '')
      ) as max_tokens
    from composer_base cb
  ),
  surname_counts as (
    select surname, count(*) as amount
    from composer_people group by surname
  ),
  scored as (
    select p.id, p.full_name, greatest(
      case
        when position(' ' in i.n) = 0 and p.max_tokens > 1 and p.token_count = 1
          then least(similarity(p.full_name, p_name), 0.94)
        else similarity(p.full_name, p_name)
      end,
      case
        when p.n = i.n and position(' ' in i.n) = 0 and p.max_tokens > 1 then 0.94
        when p.n = i.n then 1.0
        else 0
      end,
      coalesce((select max(case
        when trim(regexp_replace(lower(a.alias), '[^a-z0-9]+', ' ', 'g')) = i.n then 0.99
        else similarity(a.alias, p_name)
      end) from entity_aliases a
        where a.entity_type = 'person' and a.entity_id = p.id), 0),
      case
        when regexp_replace(i.n, '^.* ', '') = p.surname
          and position(' ' in i.n) = 0 and p.max_tokens > 1
          and p.canonical_rank = 1 then 0.995
        when regexp_replace(i.n, '^.* ', '') = p.surname
          and split_part(i.n, ' ', 1) = split_part(p.n, ' ', 1)
          and p.canonical_rank = 1 then 0.96
        when sc.amount = 1 and regexp_replace(i.n, '^.* ', '') = p.surname
          and position(' ' in i.n) = 0 then 0.96
        when sc.amount = 1 and regexp_replace(i.n, '^.* ', '') = p.surname
          and similarity(i.n, p.n) >= 0.25 then 0.90
        else 0
      end
    )::numeric as score
    from composer_people p cross join input i
    left join surname_counts sc on sc.surname = p.surname
  ),
  all_person_scores as (
    select p.id, p.full_name, greatest(
      similarity(p.full_name, p_name),
      case when trim(regexp_replace(lower(p.full_name), '[^a-z0-9]+', ' ', 'g')) = i.n then 1.0 else 0 end,
      coalesce((select max(case
        when trim(regexp_replace(lower(a.alias), '[^a-z0-9]+', ' ', 'g')) = i.n then 0.99
        else similarity(a.alias, p_name)
      end) from entity_aliases a
        where a.entity_type = 'person' and a.entity_id = p.id), 0)
    )::numeric as score
    from persons p cross join input i
  ),
  combined as (
    select id, full_name, score from scored
    union all
    select aps.* from all_person_scores aps
    where not exists (select 1 from scored s where s.id = aps.id)
  )
  select c.id, c.full_name, c.score
  from combined c
  where c.score >= p_similarity_threshold
  order by c.score desc, length(c.full_name) desc, c.full_name
  limit p_result_limit;
$$;
