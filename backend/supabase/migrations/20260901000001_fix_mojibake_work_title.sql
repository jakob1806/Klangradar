-- Ein einzelner work-Eintrag hatte einen kaputt kodierten Titel ("Konzert
-- f├╝r Oboe..." statt "Konzert für Oboe...") — Box-Drawing-Zeichen (U+2500
-- Bereich), die nie legitim in einem deutschen Werktitel vorkommen. Die
-- Quellseite selbst liefert korrektes UTF-8 (per curl verifiziert), die
-- Kaputtheit entstand also erst bei der LLM-gestützten Werk-/Komponisten-
-- Extraktion in enrich-event-references — vermutlich ein einmaliger
-- Rendering-Glitch des jeweiligen KI-Providers, denn eine Datenbank-weite
-- Suche nach demselben Zeichenmuster fand sonst keinen einzigen weiteren
-- Treffer (works/events/persons/ensembles/venues).
--
-- Ein zweiter, späterer Lauf legte denselben Titel korrekt kodiert UND mit
-- richtig zugeordnetem Komponisten erneut an (works.title ist nicht unique,
-- der ilike-Abgleich in enrich-event-references griff wegen der
-- unterschiedlichen Bytes nicht) — sichtbar als doppelter Programmpunkt auf
-- der Event-Detailseite. Der kaputte Eintrag wird hier entfernt, der
-- korrekte (mit composer_id) bleibt.
delete from event_works where work_id = '74bed9ef-8148-4439-ae29-1d34ef0f735e';
delete from works where id = '74bed9ef-8148-4439-ae29-1d34ef0f735e';
