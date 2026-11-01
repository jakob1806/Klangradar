-- Erstellt von Claude Code (Nutzerwunsch 01.11.2026: "Abo-Bereich erweitern,
-- mehr Abos suchen").
-- 1. Eigener Platz je Abo ("Parkett links, Reihe 12, Platz 7"), erscheint bei
--    jedem Konzert des Abos.
-- 2. Neue Abo-Erkennung in sync-event-subscriptions für Münchner Symphoniker,
--    hr-Sinfonieorchester und Konzerthaus Berlin: deren kommende Termine
--    einmal neu zuordnen lassen.

alter table public.user_concert_subscriptions
  add column if not exists seat text check (seat is null or char_length(seat) <= 80);

update public.events
   set subscriptions_synced_at = null
 where start_datetime >= now()
   and (website_url ilike '%muenchner-symphoniker.de/%node/%'
     or website_url ilike '%hr-sinfonieorchester.de/konzerte%'
     or website_url ilike '%konzerthaus.de/de/programm%');
