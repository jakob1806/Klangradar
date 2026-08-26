-- Multi-City-Erweiterung, Abschnitt 3 "Nutzerprofil".
alter table profiles
  add column active_city_id uuid references regions(id),
  add column favorite_city_ids uuid[] not null default '{}',
  add column city_selection_completed_at timestamptz;

-- Einmaliger Backfill: bestehende Nutzer bekommen München als anfängliche
-- aktive Stadt. Bewusst NUR city_selection_completed_at is null als
-- Bedingung (nicht z.B. "alle Profile"), damit ein späterer, erneuter
-- Lauf dieser Art (z.B. ein Hotfix, der versehentlich nochmal backfillt)
-- Nutzer, die längst selbst eine Stadt gewählt haben, nicht überschreibt —
-- "Eine später vom Client gewählte Stadt darf nicht durch einen erneuten
-- Backfill überschrieben werden" gilt nicht nur für künftige Migrationen,
-- sondern auch für dieses Skript selbst, falls es je erneut ausgeführt
-- würde.
update profiles
set active_city_id = (select id from regions where type = 'city' and slug = 'munich')
where active_city_id is null and city_selection_completed_at is null;

comment on column profiles.active_city_id is 'Aktuell aktive Konzertregion des Nutzers — steuert Events/Empfehlungen/Suche/Karte/Kalender. Initial München per Backfill; ein späterer expliziter Client-seitiger Wechsel setzt city_selection_completed_at und darf danach nicht mehr automatisch überschrieben werden.';
comment on column profiles.favorite_city_ids is 'Optionale Liste weiterer Städte, die der Nutzer schnell wechseln möchte (z.B. Pendler/Reisende). Rein additiv, ändert nichts an active_city_id.';
comment on column profiles.city_selection_completed_at is 'Zeitstempel der ersten EXPLIZITEN Stadtwahl durch den Nutzer (nicht der automatische Backfill). Ein Migrations-Backfill darf active_city_id nur setzen, wenn dieses Feld noch null ist.';
