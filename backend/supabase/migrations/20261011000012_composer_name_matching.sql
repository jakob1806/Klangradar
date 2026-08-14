-- Komponisten werden in Programmen oft nur mit Nachnamen oder mit leicht
-- abweichenden Vornamen geführt. pg_trgm über den kompletten Namen verfehlt
-- diese Fälle. Ein Nachnamen-Match wird hier NUR hoch bewertet, wenn dieser
-- Nachname unter allen bekannten Komponisten eindeutig ist. Mehrdeutige
-- Namen (z.B. Strauss) bleiben damit in der redaktionellen Prüfung.
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
  composer_people as (
    select distinct p.id, p.full_name,
      trim(regexp_replace(lower(p.full_name), '[^a-z0-9]+', ' ', 'g')) as n
    from persons p
    where 'komponist' = any(p.roles)
       or exists (select 1 from works w where w.composer_id = p.id)
  ),
  surname_counts as (
    select regexp_replace(n, '^.* ', '') as surname, count(*) as amount
    from composer_people group by regexp_replace(n, '^.* ', '')
  ),
  scored as (
    select p.id, p.full_name, greatest(
      similarity(p.full_name, p_name),
      case when p.n = i.n then 1.0 else 0 end,
      coalesce((select max(case when trim(regexp_replace(lower(a.alias), '[^a-z0-9]+', ' ', 'g')) = i.n then 0.99 else similarity(a.alias, p_name) end)
        from entity_aliases a where a.entity_type = 'person' and a.entity_id = p.id), 0),
      case
        when sc.amount = 1 and regexp_replace(i.n, '^.* ', '') = regexp_replace(p.n, '^.* ', '')
          and position(' ' in i.n) = 0 then 0.96
        when sc.amount = 1 and regexp_replace(i.n, '^.* ', '') = regexp_replace(p.n, '^.* ', '')
          and split_part(i.n, ' ', 1) = split_part(p.n, ' ', 1) then 0.95
        when sc.amount = 1 and regexp_replace(i.n, '^.* ', '') = regexp_replace(p.n, '^.* ', '')
          and similarity(i.n, p.n) >= 0.25 then 0.90
        else 0
      end
    )::numeric as score
    from composer_people p cross join input i
    left join surname_counts sc on sc.surname = regexp_replace(p.n, '^.* ', '')
  ),
  all_person_scores as (
    select p.id, p.full_name, greatest(
      similarity(p.full_name, p_name),
      case when trim(regexp_replace(lower(p.full_name), '[^a-z0-9]+', ' ', 'g')) = i.n then 1.0 else 0 end,
      coalesce((select max(case when trim(regexp_replace(lower(a.alias), '[^a-z0-9]+', ' ', 'g')) = i.n then 0.99 else similarity(a.alias, p_name) end)
        from entity_aliases a where a.entity_type = 'person' and a.entity_id = p.id), 0)
    )::numeric as score
    from persons p cross join input i
  ),
  combined as (
    select * from scored
    union all
    select aps.* from all_person_scores aps where not exists (select 1 from scored s where s.id = aps.id)
  )
  select c.id, c.full_name, c.score
  from combined c
  where c.score >= p_similarity_threshold
  order by c.score desc, c.full_name
  limit p_result_limit;
$$;

-- Bereits entstandene Varianten werden nicht automatisch zusammengeführt,
-- sondern sicher in die vorhandene Personen-Duplikatprüfung gestellt.
with composer_people as (
  select distinct p.id, p.full_name,
    trim(regexp_replace(lower(p.full_name), '[^a-z0-9]+', ' ', 'g')) as n
  from persons p
  where 'komponist' = any(p.roles) or exists (select 1 from works w where w.composer_id = p.id)
), pairs as (
  select a.id as a_id, b.id as b_id
  from composer_people a join composer_people b on a.id < b.id
  where regexp_replace(a.n, '^.* ', '') = regexp_replace(b.n, '^.* ', '')
    and (
      position(' ' in a.n) = 0 or position(' ' in b.n) = 0
      or (split_part(a.n, ' ', 1) = split_part(b.n, ' ', 1) and similarity(a.n, b.n) >= 0.35)
    )
)
insert into person_duplicate_candidates (person_a_id, person_b_id, status)
select a_id, b_id, 'pending' from pairs
on conflict do nothing;
