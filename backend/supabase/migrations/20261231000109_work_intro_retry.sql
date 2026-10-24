-- Erstellt von Claude Code (24.10.2026): Werke ohne Einführung, die durch
-- einen fehlgeschlagenen KI-Aufruf als geprüft markiert wurden, erneut
-- freigeben.
update works set introduction_checked_at = null
where introduction_de is null and introduction_checked_at is not null;
