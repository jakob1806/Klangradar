-- Erstellt von Claude Code (Nutzerfeedback 30.10.2026): "Automatisch
-- befüllen" bei redaktionellen Sammlungen funktionierte nicht. Die
-- Regel-Suche zählte kommende Termine für *alle* Namenstreffer (bei
-- "Or…" Hunderte Personen) mit je einem Scan über alle kommenden Events,
-- bevor auf 20 begrenzt wurde → Statement-Timeout, die Admin-Oberfläche
-- zeigte still keine Treffer. Jetzt: erst je Typ auf 12 Treffer begrenzen
-- (Namensanfang zuerst), dann gezielt über event_participants zählen.

create or replace function public.admin_collection_rule_search(p_query text)
returns table (entity_type text, entity_id uuid, label text, detail text, upcoming int)
language sql stable security definer set search_path = public as $$
  with q as (select nullif(btrim(p_query), '') as q),
  persons_hit as (
    select 'person'::text as entity_type, p.id, p.full_name as label,
      coalesce(p.instrument, array_to_string(p.roles, ', ')) as detail
    from persons p, q
    where q.q is not null and p.full_name ilike '%' || q.q || '%'
    order by (p.full_name ilike q.q || '%') desc, length(p.full_name)
    limit 12
  ),
  ensembles_hit as (
    select 'ensemble'::text, en.id, en.name, en.type::text
    from ensembles en, q
    where q.q is not null and en.name ilike '%' || q.q || '%' and not coalesce(en.is_resolution_placeholder, false)
    order by (en.name ilike q.q || '%') desc, length(en.name)
    limit 12
  ),
  venues_hit as (
    select 'venue'::text, v.id, v.name, v.address_city
    from venues v, q
    where q.q is not null and v.name ilike '%' || q.q || '%'
    order by (v.name ilike q.q || '%') desc, length(v.name)
    limit 12
  ),
  hits as (
    select * from persons_hit union all select * from ensembles_hit union all select * from venues_hit
  )
  select h.entity_type, h.id, h.label, h.detail,
    case h.entity_type
      when 'venue' then (select count(*)::int from events e
        where e.venue_id = h.id and e.start_datetime >= now() and e.status in ('scheduled', 'sold_out'))
      when 'person' then (select count(distinct e.id)::int from event_participants ep join events e on e.id = ep.event_id
        where ep.person_id = h.id and e.start_datetime >= now() and e.status in ('scheduled', 'sold_out'))
      else (select count(distinct e.id)::int from event_participants ep join events e on e.id = ep.event_id
        where ep.ensemble_id = h.id and e.start_datetime >= now() and e.status in ('scheduled', 'sold_out'))
    end
  from hits h
  where is_admin_or_editor()
  order by 5 desc, h.label
  limit 20;
$$;
revoke all on function public.admin_collection_rule_search(text) from public, anon;
grant execute on function public.admin_collection_rule_search(text) to authenticated;

-- Gleiches Muster für die Regel-Übersicht und den Abgleich: gezielt über
-- event_participants statt EXISTS je Event.
create or replace function public.collection_rule_events(p_collection_id uuid)
returns table (event_id uuid)
language sql stable security definer set search_path = public as $$
  select e.id from editorial_collection_rules r
  join events e on r.entity_type = 'venue' and e.venue_id = r.entity_id
  where r.collection_id = p_collection_id and e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')
  union
  select e.id from editorial_collection_rules r
  join event_participants ep on (r.entity_type = 'person' and ep.person_id = r.entity_id)
                             or (r.entity_type = 'ensemble' and ep.ensemble_id = r.entity_id)
  join events e on e.id = ep.event_id
  where r.collection_id = p_collection_id and e.start_datetime >= now() and e.status in ('scheduled', 'sold_out');
$$;
revoke all on function public.collection_rule_events(uuid) from public, anon;

create index if not exists idx_event_participants_person on public.event_participants(person_id) where person_id is not null;
create index if not exists idx_event_participants_ensemble on public.event_participants(ensemble_id) where ensemble_id is not null;
