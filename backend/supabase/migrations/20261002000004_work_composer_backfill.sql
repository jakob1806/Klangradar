-- Backfill für Werke ohne Komponisten — Nutzeranfrage: "kommt häufig vor,
-- dass kein Komponist da steht... bitte einbauen, dass falls kein Komponist
-- gefunden werden kann, das Stück recherchiert wird und dann der Komponist
-- ergänzt wird". Bisher blieb composer_id dauerhaft leer, wenn der
-- Ursprungstext (Titel/Beschreibung/Veranstaltungsseite) keinen
-- Komponistennamen erwähnte — enrich-work-profile verarbeitet ohnehin nur
-- Werke, die composer_id BEREITS haben (siehe dortiger Kommentar), es gab
-- also keinen Nachpflege-Pfad. composer_checked_at analog zu
-- profile_checked_at (20260908000006) als Auswahl-Gate, damit ein Werk ohne
-- auffindbaren Wikipedia-Artikel nicht bei jedem Lauf erneut ausgewählt
-- wird.
alter table works add column composer_checked_at timestamptz;

comment on column works.composer_checked_at is
  'Zeitpunkt des letzten enrich-work-composer-Laufs für dieses Werk (unabhängig vom Ergebnis) — verhindert endlose Wiederholung bei Werken ohne auffindbaren Komponisten.';
