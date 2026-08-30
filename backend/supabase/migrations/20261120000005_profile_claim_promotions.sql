-- Ein genehmigter Claim für eine Venue, Person oder ein Ensemble berechtigt
-- auch zur Promotion ihrer zugeordneten, veröffentlichten Termine. Events
-- bleiben dabei redaktionell angelegt; der Claim gibt ausschließlich das
-- Recht, eine Promotion anzufragen und den Fortschritt zu sehen.
create or replace function has_event_promotion_access(p_event_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
      select 1
      from events e
      left join event_participants ep on ep.event_id = e.id
      join entity_claims c
        on c.user_id = auth.uid()
        and c.status = 'approved'
        and (
          (c.entity_type = 'venue' and c.entity_id = e.venue_id)
          or (c.entity_type = 'person' and c.entity_id = ep.person_id)
          or (c.entity_type = 'ensemble' and c.entity_id = ep.ensemble_id)
        )
      where e.id = p_event_id
    );
$$;

-- Die Team-Rollen werden erst in einer späteren Migration eingeführt.
-- Deshalb dürfen sie hier weder vorausgesetzt noch zwingend gelöscht werden.
drop policy if exists "Team sieht Promotionen nach Rolle" on event_promotions;
drop policy if exists "Marketing beantragt Promotion eigener Events" on event_promotions;

create policy "Vertretung sieht Promotionen eigener Profile" on event_promotions
  for select using (has_event_promotion_access(event_id));

create policy "Vertretung beantragt Promotion eigener Profile" on event_promotions
  for insert with check (
    requested_by = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and starts_at is null
    and ends_at is null
    and has_event_promotion_access(event_id)
    and exists (select 1 from events e where e.id = event_id and e.status = 'scheduled' and e.start_datetime > now())
  );

notify pgrst, 'reload schema';
