-- Erstellt von Claude Code (24.10.2026): ingest-source hat ausgeblendete
-- Dubletten beim nächsten Import wieder veröffentlicht (eigener Entwurf →
-- scheduled, ohne review_status zu beachten). Behoben in ingest-source/
-- write.ts; hier einmal neu bereinigen.
select hide_cross_source_duplicates();
