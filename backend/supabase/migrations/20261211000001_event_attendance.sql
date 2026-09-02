-- Konzertbesuche sind ein eigenes Signal. Favoriten und Kalender bleiben
-- davon getrennt; beide dürfen lediglich einen Check-in vorschlagen.
create table if not exists public.event_attendance (
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  status text not null default 'attended' check (status in ('planned', 'attended')),
  verification_type text not null default 'manual' check (verification_type in ('manual', 'location', 'ticket')),
  attended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

create index if not exists event_attendance_user_date_idx
  on public.event_attendance(user_id, attended_at desc nulls last, created_at desc);

alter table public.event_attendance enable row level security;

drop policy if exists "Eigene Konzertbesuche" on public.event_attendance;
create policy "Eigene Konzertbesuche" on public.event_attendance for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.event_attendance to authenticated;

comment on table public.event_attendance is
  'Explizit bestätigte oder geplante Konzertbesuche; getrennt von Favoriten und Kalender-Signalen.';
comment on column public.event_attendance.verification_type is
  'manual = selbst bestätigt, location = nach Standort-Match bestätigt, ticket = späterer Ticketnachweis.';

-- Bestehende freiwillige Konzertreflexionen werden einmalig als manuell
-- bestätigte Besuche übernommen, ohne neue oder doppelte Besuche zu erfinden.
insert into public.event_attendance (user_id, event_id, status, verification_type, attended_at, created_at)
select user_id, event_id, 'attended', 'manual', attended_at, created_at
from public.coach_event_reflections
on conflict (user_id, event_id) do nothing;

notify pgrst, 'reload schema';
