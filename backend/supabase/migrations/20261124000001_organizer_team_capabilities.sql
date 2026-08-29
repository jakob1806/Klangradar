-- Granularere Rollen im Veranstalter-Team. Bestehende Owner und Editoren
-- bleiben unverändert gültig; "editor" wird im Produkt als Redaktion gezeigt.
alter table entity_claims drop constraint entity_claims_role_check;
alter table entity_claims add constraint entity_claims_role_check
  check (role in ('owner', 'editor', 'marketing', 'finance'));

-- Owner verwaltet alles. Redaktion pflegt Events, Marketing bucht
-- Promotionen, Finanzen sieht ausschließlich die abgerechneten Kampagnen.
create function has_organizer_capability(p_organizer_id uuid, p_capability text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from entity_claims
    where entity_type = 'organizer'
      and entity_id = p_organizer_id
      and user_id = auth.uid()
      and status = 'approved'
      and (
        role = 'owner'
        or (p_capability = 'events' and role = 'editor')
        or (p_capability = 'promotions' and role = 'marketing')
        or (p_capability = 'finances' and role = 'finance')
      )
  );
$$;

create function has_event_capability(p_event_id uuid, p_capability text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select has_organizer_capability(organizer_id, p_capability)
  from events where id = p_event_id;
$$;

drop policy "Veranstalter legt eigene Events an" on events;
drop policy "Veranstalter bearbeitet eigene Events" on events;
create policy "Team legt eigene Events an" on events for insert
  with check (organizer_id is not null and has_organizer_capability(organizer_id, 'events') and status = 'draft');
create policy "Team bearbeitet eigene Events" on events for update
  using (organizer_id is not null and has_organizer_capability(organizer_id, 'events'))
  with check (organizer_id is not null and has_organizer_capability(organizer_id, 'events'));

drop policy "Veranstalter sieht Promotionen eigener Events" on event_promotions;
drop policy "Veranstalter beantragt Promotion eigener Events" on event_promotions;
create policy "Team sieht Promotionen nach Rolle" on event_promotions for select
  using (has_event_capability(event_id, 'promotions') or has_event_capability(event_id, 'finances'));
create policy "Marketing beantragt Promotion eigener Events" on event_promotions for insert
  with check (
    requested_by = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and starts_at is null
    and ends_at is null
    and has_event_capability(event_id, 'promotions')
    and exists (select 1 from events e where e.id = event_id and e.status = 'scheduled' and e.start_datetime > now())
  );

drop policy "Veranstalter sieht eigene Serien" on event_series;
drop policy "Veranstalter legt eigene Serien an" on event_series;
drop policy "Veranstalter bearbeitet eigene Serien" on event_series;
create policy "Team sieht eigene Serien" on event_series for select
  using (has_approved_organizer_claim(organizer_id));
create policy "Redaktion legt eigene Serien an" on event_series for insert
  with check (created_by = auth.uid() and has_organizer_capability(organizer_id, 'events'));
create policy "Redaktion bearbeitet eigene Serien" on event_series for update
  using (has_organizer_capability(organizer_id, 'events'))
  with check (has_organizer_capability(organizer_id, 'events'));
