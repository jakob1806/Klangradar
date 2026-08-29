-- Veranstalter-Portal Phase 5: Push/Promote.
-- Eine Promotion ist bewusst ein redaktionell freizugebender Auftrag, keine
-- Zahlung und auch kein automatischer Versand. So lassen sich die sichtbaren
-- Platzierungen (Standard/Featured/Local/Homepage) schon sicher verwalten,
-- ohne der späteren Zahlungs- oder Targeting-Infrastruktur vorzugreifen.
create table event_promotions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  requested_by uuid not null references profiles(id) on delete cascade,
  placement text not null check (placement in ('standard', 'featured', 'local_spotlight', 'homepage_feature', 'push')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requester_note text check (char_length(requester_note) <= 1000),
  reviewer_note text check (char_length(reviewer_note) <= 1000),
  reviewed_by uuid references profiles(id),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  starts_at timestamptz,
  ends_at timestamptz,
  constraint event_promotions_time_window check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index event_promotions_event_idx on event_promotions(event_id);
create index event_promotions_pending_idx on event_promotions(requested_at) where status = 'pending';

alter table event_promotions enable row level security;

-- Teammates einer beanspruchten Institution dürfen dieselben Promotionen
-- sehen. Die Berechtigung wird in einer SECURITY DEFINER-Funktion geprüft,
-- damit die RLS-Policies der beiden Tabellen nicht voneinander abhängen.
create function has_approved_organizer_event(p_event_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from events e
    join entity_claims c
      on c.entity_type = 'organizer'
      and c.entity_id = e.organizer_id
      and c.user_id = auth.uid()
      and c.status = 'approved'
    where e.id = p_event_id
  );
$$;

create policy "Redaktion verwaltet Event-Promotions" on event_promotions
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

create policy "Veranstalter sieht Promotionen eigener Events" on event_promotions
  for select using (has_approved_organizer_event(event_id));

-- Ausschließlich ein Antrag im Status pending kann von einem Veranstalter
-- erzeugt werden. Freigabe, Zeitfenster und redaktionelle Notiz liegen damit
-- vollständig bei der Redaktion.
create policy "Veranstalter beantragt Promotion eigener Events" on event_promotions
  for insert
  with check (
    requested_by = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and starts_at is null
    and ends_at is null
    and has_approved_organizer_event(event_id)
    and exists (select 1 from events e where e.id = event_id and e.status = 'scheduled' and e.start_datetime > now())
  );
