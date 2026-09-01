-- Genehmigte Personen-/Ensemble-Claims dürfen die Veranstaltungen pflegen,
-- in denen das beanspruchte Profil als Mitwirkende:r verknüpft ist. Der
-- ursprüngliche Veranstalter bleibt dabei unverändert; diese Policy gibt nur
-- Zugriff auf den bestehenden Event-Datensatz.
create or replace function has_claimed_profile_event_edit_access(p_event_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from event_participants ep
    join entity_claims c
      on c.user_id = auth.uid()
      and c.status = 'approved'
      and c.role in ('owner', 'editor')
      and (
        (c.entity_type = 'person' and c.entity_id = ep.person_id)
        or (c.entity_type = 'ensemble' and c.entity_id = ep.ensemble_id)
      )
    where ep.event_id = p_event_id
  );
$$;

create policy "Beanspruchte Künstler sehen verknüpfte Events" on events
  for select using (has_claimed_profile_event_edit_access(id));

create policy "Beanspruchte Künstler bearbeiten verknüpfte Events" on events
  for update
  using (has_claimed_profile_event_edit_access(id))
  with check (has_claimed_profile_event_edit_access(id));

create policy "Beanspruchte Künstler pflegen Event-Genres" on event_genres
  for all
  using (has_claimed_profile_event_edit_access(event_id))
  with check (has_claimed_profile_event_edit_access(event_id));

notify pgrst, 'reload schema';
