-- Zwei bei der Verifikation der Vormigrationen entdeckte Restfälle:
--
-- 1) Der Re-Lauf von enrich-event-references für "Konzert des Nymphenburger
--    Kammerorchesters" verknüpfte zusätzlich Bachs Orgel-"Fantasie" (BWV
--    1121) — ein Werk, das echt zu zwei ANDEREN Orgelkonzert-Events gehört
--    (die website_url des Nymphenburger-Events ist eine allgemeine
--    Ensemble-Homepage, vermutlich mit weiteren Konzerthinweisen auf
--    derselben Seite, die die Extraktion mit hereingezogen hat — laut
--    description_de kommt in diesem Konzert kein Bach vor). Nur die falsche
--    Verknüpfung entfernen, das Werk selbst bleibt für die beiden
--    tatsächlich betroffenen Orgelkonzerte bestehen.
delete from event_works
where event_id = '630596a6-0392-4992-b303-ccde8394bd1c'
  and work_id = 'a000776c-5f90-4a2b-9572-1df9b2dab8b6';

-- 2) "Orgelkonzert mit Angela Metzger": eine alte, komponistenlose
--    "Echo-Fantasie (d4)"-Zeile (Katalog fälschlich "SwWV 261" im Titel-
--    Klammerzusatz statt als eigenes Feld) blieb neben der neuen, korrekt
--    mit Sweelinck verknüpften "Echo-Fantasie" bestehen, weil sich die
--    Titel nach Normalisierung unterscheiden ("Echo-Fantasie" vs.
--    "Echo-Fantasie (d4)") und daher als zwei verschiedene Werke galten —
--    dieselbe Aufführung erschien dadurch doppelt im Programm. Die alte,
--    unvollständige Zeile entfernen.
delete from event_works
where event_id = 'cd1020c9-8d5f-4cd9-903b-321f793e84a4'
  and work_id = 'abc8da86-4d53-486d-a312-c2f162932039';

delete from works
where id = 'abc8da86-4d53-486d-a312-c2f162932039'
  and id not in (select work_id from event_works);
