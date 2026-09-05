-- Nutzeranfrage: "in den Städten Hamburg, Berlin, Wien und Frankfurt haben
-- alle Konzerte noch kein Programm" — Vergleich mit München zeigt: das ist
-- kein struktureller Bug in enrich-event-references selbst (die Funktion
-- liefert für alle vier Städte bereits echte event_works/event_participants,
-- sobald sie ein Event tatsächlich verarbeitet — z.B. Deutsche Oper Berlin
-- "Konzert zum Eröffnungsfest": 15 Werke/21 Mitwirkende, Berliner
-- Philharmoniker "Lunchkonzert": 3 Werke/4 Mitwirkende), sondern ein reiner
-- Durchsatz-Engpass: der Cron verarbeitet nur 5 Events alle 10 Minuten
-- (~30/Std.), die vier neuen Städte brachten aber zusammen ~880 zusätzliche
-- offene Events (program_extraction_status='pending') auf einen Schlag mit,
-- ohne dass der Cron-Takt seit der reinen München-Zeit (~900 Events,
-- inzwischen zu 95%+ abgearbeitet) angepasst wurde. Live per PostgREST
-- gegen die Produktionsdaten verifiziert (04.09.2026): Hamburg 182/209,
-- Wien 502/523, Berlin 170/191, Frankfurt 23/30 Events noch 'pending'.
--
-- Batch-Größe (limit=5) bewusst UNVERÄNDERT gelassen — die war ursprünglich
-- wegen eines WORKER_RESOURCE_LIMIT-Speicherproblems bei limit=10 auf 5
-- reduziert worden (siehe 20260907000003_event_reference_enrichment_cron.sql),
-- an dieser Ursache hat sich nichts geändert. Stattdessen nur der Takt
-- verdreifacht (alle 3 statt alle 10 Minuten, ~100/Std. statt ~30/Std.) —
-- gleiches, bereits bewährtes Muster wie bei
-- 20260910000005_increase_image_enrichment_frequency.sql. Überlappende
-- Läufe sind ungefährlich: claim_event_program_enrichment() sperrt
-- geclaimte Zeilen mit "for update skip locked", ein noch laufender Batch
-- blockiert den nächsten Tick nicht und es kann nie derselbe Event doppelt
-- bearbeitet werden.
select cron.schedule(
  'event-reference-enrichment',
  '*/3 * * * *',
  $$ select run_event_reference_enrichment(); $$
);
