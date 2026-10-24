-- Erstellt von Claude Code (25.10.2026): Werkeinführungen jetzt ohne KI aus
-- Wikipedia (work-introduction). Alle Werke ohne Einführung erneut prüfen.
update works set introduction_checked_at = null where introduction_de is null;
