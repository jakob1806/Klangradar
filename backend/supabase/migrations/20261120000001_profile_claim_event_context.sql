-- Ein genehmigtes Profil (Person, Ensemble oder Venue) darf eigene Events
-- verwalten. events.organizer_id zeigt technisch weiterhin auf organizers;
-- deshalb bekommt jedes beanspruchbare Profil einen internen, eindeutig
-- zugeordneten Veranstalter-Kontext. Dieser ist kein zusätzlicher Eintrag in
-- den Endnutzer-Apps, sondern nur der Berechtigungs- und Besitzkontext.
create table if not exists profile_event_organizer_contexts (
  entity_type text not null check (entity_type in ('person', 'ensemble', 'venue')),
  entity_id uuid not null,
  organizer_id uuid not null unique references organizers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (entity_type, entity_id)
);

alter table profile_event_organizer_contexts enable row level security;

create function ensure_profile_event_organizer_context(p_entity_type text, p_entity_id uuid)
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
begin
  if p_entity_type not in ('person', 'ensemble', 'venue') then
    raise exception 'Ungültiger Profiltyp';
  end if;
  if not exists (
    select 1 from entity_claims
    where entity_type = p_entity_type and entity_id = p_entity_id
      and user_id = auth.uid() and status = 'approved'
  ) then
    raise exception 'Kein genehmigter Claim für dieses Profil';
  end if;

  select organizer_id into existing_id
  from profile_event_organizer_contexts
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
    values (context_name, context_slug, context_website, auth.uid())
    returning id into new_organizer_id;
    insert into profile_event_organizer_contexts (entity_type, entity_id, organizer_id)
    values (p_entity_type, p_entity_id, new_organizer_id);
    existing_id := new_organizer_id;
  end if;

  -- Mehrere berechtigte Teammitglieder desselben Profils nutzen bewusst
  -- denselben Kontext, erhalten aber jeweils ihren eigenen Zugriffs-Claim.
  insert into entity_claims (entity_type, entity_id, user_id, status, role, justification, reviewed_by, reviewed_at)
  values ('organizer', existing_id, auth.uid(), 'approved', 'editor', 'Automatisch aus genehmigtem Profil-Claim', auth.uid(), now())
  on conflict (entity_type, entity_id, user_id) do update
    set status = 'approved';

  return existing_id;
end;
$$;

grant execute on function ensure_profile_event_organizer_context(text, uuid) to authenticated;
