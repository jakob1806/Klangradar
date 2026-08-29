-- Veranstalter-Portal: wiederkehrende Veranstaltungsserien. Die gemeinsamen
-- Inhalte liegen einmal an der Serie; einzelne Termine behalten bei Bedarf
-- ihre eigenen Details.
create table event_series (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references organizers(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 180),
  description_de text,
  image_url text,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index event_series_organizer_idx on event_series(organizer_id);

alter table events add column series_id uuid references event_series(id) on delete set null;
create index events_series_idx on events(series_id) where series_id is not null;

alter table event_series enable row level security;

create policy "Veranstalter sieht eigene Serien" on event_series
  for select using (has_approved_organizer_claim(organizer_id));

create policy "Veranstalter legt eigene Serien an" on event_series
  for insert with check (
    created_by = auth.uid()
    and has_approved_organizer_claim(organizer_id)
  );

create policy "Veranstalter bearbeitet eigene Serien" on event_series
  for update using (has_approved_organizer_claim(organizer_id))
  with check (has_approved_organizer_claim(organizer_id));

create policy "Redaktion verwaltet Serien" on event_series
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());
