-- Bereinigt korrupte Programm-Einträge, die vom Fuzzy-Match-/Doppelverarbeitungs-
-- Bug in enrich-event-references verursacht wurden (siehe Code-Fix im selben
-- PR: composerConflict-Schwellwert angehoben, Fragment-Titel-Filter,
-- key_signature-Plausibilitätsprüfung). Nutzerfeedback: "es haben mehrere
-- Konzerte fehlerhafte Programme, oder fehlende Komponisten" — live verifiziert
-- an mehreren Events (u.a. Nymphenburger Kammerorchester, Münchner
-- Philharmoniker Strauß/Ravel).
--
-- Drei Bereinigungsschritte:
--
-- 1) Generisch: (event_id, position)-Duplikate. Diese entstehen, wenn ein
--    Event zweimal durch enrich-event-references lief (z.B. nach einem
--    gezielten references_checked_at-Reset für einen Backfill) und der
--    zweite Lauf einen abgeschnittenen Titel-Fragment als vermeintlich neues
--    Werk anlegte ("Konzert f" neben "Konzert für Oboe...", "An der sch"
--    neben "An der schönen blauen Donau"). Behält je Duplikat-Gruppe die
--    Zeile mit dem LÄNGEREN Werktitel (der vollständige Titel ist so gut wie
--    immer der längere), löscht die andere Verknüpfung, merkt betroffene
--    Events für eine erneute Extraktion vor und entfernt verwaiste
--    Fragment-Werke — generisch für ALLE betroffenen Events, nicht nur die
--    zwei konkret gemeldeten.
--
-- 2) Gezielt: das Werk "Sinfonie Nr. 4 c-moll" (Beethoven, op. 60, B-Dur —
--    Tonart und Titel widersprechen sich bereits: Beethovens echte 4.
--    Sinfonie steht in B-Dur, nicht c-Moll) wurde per Fuzzy-Match fälschlich
--    mit VIER unterschiedlichen, tatsächlich anderen Werken zusammengelegt
--    (Schuberts "Tragische", ein Tschaikowsky-Werk, zwei Werke bei Rattle/
--    Yuja-Wang-Konzerten mit Busoni/Barber/Schostakowitsch) — keine der vier
--    Verknüpfungen ist korrekt. Wird komplett entfernt statt versucht,
--    einzeln zu erraten, welches der vier Werke stattdessen gemeint war.
--
-- 3) Erkennbar erfundene Opus-Nummern bei einem Orgelkonzert mit Bach-/
--    vorbarocken Chorälen nullen (solche Werke tragen nie eine Opus-Zählung).
--
-- Betroffene Events werden über references_checked_at=null erneut für die
-- automatische Extraktion vorgemerkt — der jetzt reparierte Code erzeugt beim
-- nächsten Lauf ein korrektes Programm.

do $$
declare
  v_reset_events int;
  v_deleted_links int;
  v_deleted_works int;
begin

-- Schritt 1: generische (event_id, position)-Duplikate.
create temporary table dedup_losers as
  select event_id, position, work_id
  from (
    select
      ew.event_id,
      ew.position,
      ew.work_id,
      row_number() over (
        partition by ew.event_id, ew.position
        order by length(w.title) desc, ew.work_id
      ) as rank_by_title_length
    from event_works ew
    join works w on w.id = ew.work_id
    where (ew.event_id, ew.position) in (
      select event_id, position from event_works group by event_id, position having count(*) > 1
    )
  ) ranked
  where rank_by_title_length > 1;

delete from event_works ew
using dedup_losers dl
where ew.event_id = dl.event_id and ew.position = dl.position and ew.work_id = dl.work_id;
get diagnostics v_deleted_links = row_count;

update events set references_checked_at = null
where id in (select distinct event_id from dedup_losers);
get diagnostics v_reset_events = row_count;

delete from works
where id in (select work_id from dedup_losers)
  and id not in (select work_id from event_works);
get diagnostics v_deleted_works = row_count;

raise notice 'Duplikat-Bereinigung: % Verknüpfungen gelöscht, % Events zur Neu-Extraktion vorgemerkt, % verwaiste Werke gelöscht',
  v_deleted_links, v_reset_events, v_deleted_works;

drop table dedup_losers;

end $$;

-- Schritt 2: das fälschlich zusammengelegte Beethoven-Werk gezielt entfernen.
update events set references_checked_at = null
where id in (
  select event_id from event_works
  where work_id in (select id from works where title = 'Sinfonie Nr. 4 c-moll' and catalog_number = 'op. 60')
);

delete from event_works
where work_id in (select id from works where title = 'Sinfonie Nr. 4 c-moll' and catalog_number = 'op. 60');

delete from works where title = 'Sinfonie Nr. 4 c-moll' and catalog_number = 'op. 60';

-- Schritt 3: erkennbar erfundene Opus-Nummern bei einem Orgelkonzert mit
-- Bach-/vorbarocken Chorälen ("op. 67 Nr. 45", "op. 40 Nr. 1" — solche Werke
-- tragen nie eine Opus-Zählung, das ist eine romantische Konvention) nullen
-- statt eine falsche Angabe stehen zu lassen. Composer bleibt bewusst leer
-- für den regulären enrich-work-composer-Backfill statt hier zu raten.
update works
set catalog_number = null
where catalog_number in ('op. 67 Nr. 45', 'op. 40 Nr. 1')
  and composer_id is null;

update events set references_checked_at = null
where id = 'cd1020c9-8d5f-4cd9-903b-321f793e84a4';
