-- Erstellt von Claude Code (14.11.2026): Bayerische Staatsoper – Besetzungs-
-- änderungen nur noch bei Umbesetzung (jemand ersetzt jemanden), nicht wenn
-- jemand nur wegfällt. Bestehende reine Wegfall-Meldungen werden entfernt.

create or replace function public.detect_cast_changes()
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    with current_cast as (
      select e.id as event_id,
             array_agg(distinct coalesce(p.full_name, en.name) order by coalesce(p.full_name, en.name))
               filter (where coalesce(p.full_name, en.name) is not null) as names
      from events e
      join event_participants ep on ep.event_id = e.id
      left join persons p on p.id = ep.person_id
      left join ensembles en on en.id = ep.ensemble_id
      where e.start_datetime between now() and now() + interval '90 days'
        and e.status in ('scheduled', 'sold_out')
      group by e.id
    )
    select c.event_id, c.names, s.names as old_names,
      exists (select 1 from events e where e.id = c.event_id
              and (e.staatsoper_detail_synced_at is not null or e.website_url ilike '%staatsoper.de%')) as is_staatsoper
    from current_cast c left join event_cast_snapshots s on s.event_id = c.event_id
    where s.names is distinct from c.names
  loop
    -- Erstes Auftauchen = Ausgangsstand, kein Push. Ebenso keine Meldung,
    -- wenn vorher noch niemand eingetragen war.
    -- Staatsoper: nur Umbesetzungen melden (jemand kommt neu dazu), nicht wenn
    -- jemand nur wegfällt – deren Besetzungslisten schrumpfen oft nachträglich.
    if r.old_names is not null and cardinality(r.old_names) > 0 and cardinality(r.names) > 0
       and (not r.is_staatsoper or exists (select unnest(r.names) except select unnest(r.old_names))) then
      insert into event_changes(event_id, field_name, old_value, new_value)
      values (r.event_id, 'cast',
        nullif(array_to_string(array(select unnest(r.old_names) except select unnest(r.names)), ', '), ''),
        nullif(array_to_string(array(select unnest(r.names) except select unnest(r.old_names)), ', '), ''));
      v_count := v_count + 1;
    end if;
    insert into event_cast_snapshots(event_id, names, updated_at) values (r.event_id, r.names, now())
    on conflict (event_id) do update set names = excluded.names, updated_at = now();
  end loop;
  return v_count;
end;
$$;

delete from event_changes c
using events e
where c.event_id = e.id
  and c.field_name = 'cast'
  and (c.new_value is null or btrim(c.new_value) = '')
  and (e.staatsoper_detail_synced_at is not null or e.website_url ilike '%staatsoper.de%');
