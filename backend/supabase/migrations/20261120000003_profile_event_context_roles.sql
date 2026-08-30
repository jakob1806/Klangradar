-- Der technische Veranstalter-Kontext übernimmt die Teamrolle des
-- genehmigten Profil-Claims. Insbesondere darf ein Owner eines Ensembles
-- nicht durch die technische Zuordnung zu einem reinen Editor werden.
create or replace function ensure_profile_event_organizer_context(p_entity_type text, p_entity_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_id uuid;
  context_name text;
  context_website text;
  context_slug text;
  new_organizer_id uuid;
  source_role text;
begin
  if p_entity_type not in ('person', 'ensemble', 'venue') then
    raise exception 'Ungültiger Profiltyp';
  end if;
  select role into source_role from entity_claims
  where entity_type = p_entity_type and entity_id = p_entity_id
    and user_id = auth.uid() and status = 'approved';
  if source_role is null then
    raise exception 'Kein genehmigter Claim für dieses Profil';
  end if;

  select organizer_id into existing_id from profile_event_organizer_contexts
  where entity_type = p_entity_type and entity_id = p_entity_id;
  if existing_id is null then
    if p_entity_type = 'person' then
      select full_name, website_url into context_name, context_website from persons where id = p_entity_id;
    elsif p_entity_type = 'ensemble' then
      select name, website_url into context_name, context_website from ensembles where id = p_entity_id;
    else
      select name, website_url into context_name, context_website from venues where id = p_entity_id;
    end if;
    if context_name is null then raise exception 'Profil nicht gefunden'; end if;
    context_slug := 'profil-' || p_entity_type || '-' || replace(p_entity_id::text, '-', '');
    insert into organizers (name, slug, website_url, created_by)
    values (context_name, context_slug, context_website, auth.uid()) returning id into new_organizer_id;
    insert into profile_event_organizer_contexts (entity_type, entity_id, organizer_id)
    values (p_entity_type, p_entity_id, new_organizer_id);
    existing_id := new_organizer_id;
  end if;

  insert into entity_claims (entity_type, entity_id, user_id, status, role, justification, reviewed_by, reviewed_at)
  values ('organizer', existing_id, auth.uid(), 'approved', source_role, 'Automatisch aus genehmigtem Profil-Claim', auth.uid(), now())
  on conflict (entity_type, entity_id, user_id) do update
    set status = 'approved', role = excluded.role;
  return existing_id;
end;
$$;

notify pgrst, 'reload schema';
