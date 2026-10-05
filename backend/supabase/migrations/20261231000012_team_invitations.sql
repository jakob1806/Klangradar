-- Veranstalterportal: Team-Mitglieder per E-Mail einladen.
-- Ein Owner trägt eine E-Mail-Adresse und eine Rolle ein, die Adresse erhält
-- eine Einladung mit Link auf eine eigene Landingpage (/einladung/<token>) und
-- kann dort annehmen oder ablehnen. Annehmen legt (wie ein genehmigter
-- Claim) eine approved-Zeile in entity_claims an — die bestehende
-- Rechte-Logik (has_organizer_capability, RLS) bleibt unverändert.
create table team_invitations (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('organizer', 'venue', 'person', 'ensemble')),
  entity_id uuid not null,
  email text not null,
  role text not null check (role in ('owner', 'editor', 'marketing', 'finance')),
  token text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'revoked')),
  invited_by uuid references profiles(id) on delete set null,
  accepted_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  responded_at timestamptz
);

create index team_invitations_entity_idx on team_invitations(entity_type, entity_id, status);
create unique index team_invitations_one_pending_idx
  on team_invitations(entity_type, entity_id, lower(email)) where status = 'pending';

alter table team_invitations enable row level security;

create policy "Redaktion verwaltet Einladungen" on team_invitations
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Owner sieht die Einladungen der eigenen Entität; Schreibzugriffe laufen
-- ausschließlich über die security-definer-Funktionen unten.
create policy "Owner sieht Einladungen der eigenen Entität" on team_invitations
  for select using (is_owner_of_entity(entity_type, entity_id));

-- Benachrichtigungen an den Einladenden bei Annahme/Ablehnung.
alter table organizer_notifications drop constraint organizer_notifications_type_check;
alter table organizer_notifications add constraint organizer_notifications_type_check check (type in (
  'claim_approved', 'claim_rejected',
  'promotion_approved', 'promotion_rejected', 'promotion_payment_failed',
  'team_invite_received', 'team_role_changed',
  'team_invite_accepted', 'team_invite_declined'
));

create function team_entity_name(p_entity_type text, p_entity_id uuid)
returns text
language plpgsql
security definer
set search_path = public
stable
as $$
declare v_name text;
begin
  if p_entity_type = 'organizer' then select name into v_name from organizers where id = p_entity_id;
  elsif p_entity_type = 'venue' then select name into v_name from venues where id = p_entity_id;
  elsif p_entity_type = 'person' then select full_name into v_name from persons where id = p_entity_id;
  elsif p_entity_type = 'ensemble' then select name into v_name from ensembles where id = p_entity_id;
  end if;
  return v_name;
end;
$$;

-- Owner lädt per E-Mail ein. Erneutes Einladen derselben Adresse erneuert
-- Token und Ablauf, statt eine zweite offene Einladung anzulegen.
create function create_team_invitation(p_entity_type text, p_entity_id uuid, p_email text, p_role text)
returns table (id uuid, token text, entity_name text, inviter_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(p_email));
  v_id uuid;
  v_token text;
  v_existing_user uuid;
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet.'; end if;
  if not (is_owner_of_entity(p_entity_type, p_entity_id) or is_admin_or_editor()) then
    raise exception 'Nur Owner dürfen Mitglieder einladen.';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Bitte eine gültige E-Mail-Adresse angeben.'; end if;
  if p_role not in ('owner', 'editor', 'marketing', 'finance') then raise exception 'Ungültige Rolle.'; end if;

  select u.id into v_existing_user from auth.users u where lower(u.email) = v_email limit 1;
  if v_existing_user is not null and exists (
    select 1 from entity_claims c
    where c.entity_type = p_entity_type and c.entity_id = p_entity_id
      and c.user_id = v_existing_user and c.status = 'approved'
  ) then
    raise exception 'Diese Person ist bereits Mitglied des Teams.';
  end if;

  update team_invitations ti
  set role = p_role, token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      expires_at = now() + interval '14 days', invited_by = auth.uid(), created_at = now()
  where ti.entity_type = p_entity_type and ti.entity_id = p_entity_id
    and lower(ti.email) = v_email and ti.status = 'pending'
  returning ti.id, ti.token into v_id, v_token;

  if v_id is null then
    insert into team_invitations (entity_type, entity_id, email, role, invited_by)
    values (p_entity_type, p_entity_id, v_email, p_role, auth.uid())
    returning team_invitations.id, team_invitations.token into v_id, v_token;
  end if;

  -- Bereits registrierte Person bekommt zusätzlich einen Hinweis im Postfach.
  if v_existing_user is not null and p_entity_type = 'organizer' then
    insert into organizer_notifications (user_id, organizer_id, type, title, body, link_href)
    values (v_existing_user, p_entity_id, 'team_invite_received',
            'Einladung zum Team „' || coalesce(team_entity_name(p_entity_type, p_entity_id), 'Team') || '“',
            'Du wurdest eingeladen. Öffne die Einladung, um sie anzunehmen oder abzulehnen.',
            '/einladung/' || v_token);
  end if;

  return query
    select v_id, v_token, team_entity_name(p_entity_type, p_entity_id),
           (select coalesce(p.display_name, 'Ein Teammitglied') from profiles p where p.id = auth.uid());
end;
$$;

-- Öffentlich lesbar über das Token (Landingpage vor dem Login): nur das,
-- was die Einladungsseite anzeigen muss, E-Mail nur maskiert.
create function get_team_invitation(p_token text)
returns table (
  entity_type text, entity_id uuid, entity_name text, role text, status text,
  expired boolean, inviter_name text, email_hint text
)
language sql
security definer
set search_path = public
stable
as $$
  select ti.entity_type, ti.entity_id, team_entity_name(ti.entity_type, ti.entity_id), ti.role, ti.status,
         (ti.status = 'pending' and ti.expires_at < now()),
         (select p.display_name from profiles p where p.id = ti.invited_by),
         regexp_replace(ti.email, '^(.).*(@.*)$', '\1***\2')
  from team_invitations ti where ti.token = p_token;
$$;
grant execute on function get_team_invitation(text) to anon, authenticated;

create function accept_team_invitation(p_token text)
returns table (entity_type text, entity_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  inv team_invitations%rowtype;
  v_user_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then raise exception 'Bitte zuerst anmelden.'; end if;
  select * into inv from team_invitations where token = p_token for update;
  if not found then raise exception 'Einladung nicht gefunden.'; end if;
  if inv.status <> 'pending' then raise exception 'Diese Einladung wurde bereits beantwortet oder zurückgezogen.'; end if;
  if inv.expires_at < now() then raise exception 'Diese Einladung ist abgelaufen.'; end if;
  if lower(inv.email) <> v_user_email then
    raise exception 'Diese Einladung gilt für eine andere E-Mail-Adresse (%). Bitte mit dieser Adresse anmelden.',
      regexp_replace(inv.email, '^(.).*(@.*)$', '\1***\2');
  end if;

  insert into entity_claims (entity_type, entity_id, user_id, status, role, reviewed_by, reviewed_at, verification_email)
  values (inv.entity_type, inv.entity_id, auth.uid(), 'approved', inv.role, inv.invited_by, now(), inv.email)
  on conflict (entity_type, entity_id, user_id) do update
    set status = 'approved', reviewed_at = now(),
        role = case when entity_claims.status = 'approved' and entity_claims.role = 'owner' then 'owner' else excluded.role end;

  update team_invitations set status = 'accepted', accepted_by = auth.uid(), responded_at = now() where id = inv.id;

  if inv.invited_by is not null and inv.entity_type = 'organizer' then
    insert into organizer_notifications (user_id, organizer_id, type, title, body, link_href)
    values (inv.invited_by, inv.entity_id, 'team_invite_accepted',
            inv.email || ' ist dem Team beigetreten', 'Rolle: ' || inv.role,
            '/veranstalter/team/organizer/' || inv.entity_id);
  end if;
  return query select inv.entity_type, inv.entity_id;
end;
$$;

-- Ablehnen geht mit dem Token allein (auch ohne Anmeldung).
create function decline_team_invitation(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare inv team_invitations%rowtype;
begin
  select * into inv from team_invitations where token = p_token for update;
  if not found then raise exception 'Einladung nicht gefunden.'; end if;
  if inv.status <> 'pending' then raise exception 'Diese Einladung wurde bereits beantwortet oder zurückgezogen.'; end if;
  update team_invitations set status = 'declined', responded_at = now() where id = inv.id;
  if inv.invited_by is not null and inv.entity_type = 'organizer' then
    insert into organizer_notifications (user_id, organizer_id, type, title, body, link_href)
    values (inv.invited_by, inv.entity_id, 'team_invite_declined',
            inv.email || ' hat die Einladung abgelehnt', null,
            '/veranstalter/team/organizer/' || inv.entity_id);
  end if;
end;
$$;
grant execute on function decline_team_invitation(text) to anon, authenticated;

create function revoke_team_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare inv team_invitations%rowtype;
begin
  select * into inv from team_invitations where id = p_invitation_id;
  if not found then return; end if;
  if not (is_owner_of_entity(inv.entity_type, inv.entity_id) or is_admin_or_editor()) then
    raise exception 'Nur Owner dürfen Einladungen zurückziehen.';
  end if;
  update team_invitations set status = 'revoked', responded_at = now() where id = p_invitation_id and status = 'pending';
end;
$$;

revoke all on function create_team_invitation(text, uuid, text, text) from public, anon;
revoke all on function accept_team_invitation(text) from public, anon;
revoke all on function revoke_team_invitation(uuid) from public, anon;
grant execute on function create_team_invitation(text, uuid, text, text) to authenticated;
grant execute on function accept_team_invitation(text) to authenticated;
grant execute on function revoke_team_invitation(uuid) to authenticated;
