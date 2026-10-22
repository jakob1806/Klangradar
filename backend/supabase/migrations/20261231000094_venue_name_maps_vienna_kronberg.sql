-- Erstellt mit Claude Code.
--
-- Quellen-Audit 2026-10-18: zwei Quellen verlieren einzelne Termine, weil
-- Saalnamen keiner Spielstätte zugeordnet werden ("no venue match").
-- Die Spielstätten existieren bereits; hier nur die Zuordnung der
-- Saalnamen der Website auf die kanonischen Venue-Namen.

-- Wiener Konzerthaus: Website liefert nur den Saal ("∙ Schubert-Saal"),
-- die Venues heißen "Wiener Konzerthaus – <Saal>".
update sources
set config = config || '{"venueNameMap": {
  "Großer Saal": "Wiener Konzerthaus – Großer Saal",
  "Mozart-Saal": "Wiener Konzerthaus – Mozart-Saal",
  "Schubert-Saal": "Wiener Konzerthaus – Schubert-Saal",
  "Berio-Saal": "Wiener Konzerthaus – Berio-Saal"
}}'::jsonb
where id = '768a9508-8ec3-410a-85a3-74f87e46144a';

-- Kronberg Academy: "Carl Bechstein Saal, Casals Forum" / "Großer Saal,
-- Casals Forum" -> "Casals Forum" (Saal vor dem Komma entfernen).
update sources
set config = config || '{"venueStripPattern": "^.*,\\s*"}'::jsonb
where id = '1450cc78-2982-4dfe-9ae7-38de75da8d00';
