-- Auf Nutzerwunsch: das Bildlücken-Dashboard soll den TATSÄCHLICHEN Grund
-- zeigen (keine Quelle vorhanden / Quelle blockiert / Bild nicht eindeutig
-- genug / Lizenzprüfung erforderlich) statt einer nachträglich geratenen
-- Kategorie. Der einzige Ort, der diesen Grund wirklich kennt, ist der
-- Anreicherungslauf selbst, im Moment der Entscheidung — daher eine
-- persistierte Spalte statt einer Live-Neuberechnung beim Seitenaufruf
-- (die für "Quelle blockiert" ohnehin einen erneuten, teuren HTTP-Request
-- pro Zeile bräuchte).
alter table venues add column last_image_search_note text;
alter table persons add column last_image_search_note text;
alter table ensembles add column last_image_search_note text;
alter table festivals add column last_image_search_note text;
alter table events add column last_image_search_note text;
