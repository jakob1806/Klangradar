-- Empfehlungssystem-Anfrage (Punkt 25, "Folgen als Kernfeature"): Festivals
-- fehlten in der Reihe Personen/Ensembles/Venues, obwohl events.festival_id
-- (20260819000007) und die Home-Kachel "Festival gerade in München"
-- (festival_events(), 20261016000009) schon existieren. Gleiche Struktur
-- wie user_favorite_venues, inkl. notify_new_events (20261016000010).
create table user_favorite_festivals (
  user_id uuid references profiles(id) on delete cascade,
  festival_id uuid references festivals(id) on delete cascade,
  notify_new_events boolean not null default true,
  primary key (user_id, festival_id)
);
alter table user_favorite_festivals enable row level security;
create policy "Nutzer verwaltet eigene Festival-Follows" on user_favorite_festivals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
