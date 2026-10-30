-- Erstellt von Claude Code (Nutzerwunsch 30.10.2026: "Supabase ausgelastet,
-- kein Abo abschließen"). Befund vom 29./30.10.2026:
--  * Datenbank selbst nur 325 MB, Cache-Trefferquote 100 % – kein Platz-,
--    sondern ein Rechenlast-Problem.
--  * Über 50 Cron-Jobs, viele alle 2–5 Minuten, 18 davon exakt zur selben
--    Minute (*/10). In 24 h scheiterten ~30 % der Läufe, Aufrufe, die nur
--    einen HTTP-Request einreihen, dauerten bis zu 4 Minuten; am Abend des
--    29.10. waren Datenbank, REST und Auth zeitweise "UNHEALTHY".
--  * cron.job_run_details wurde nie aufgeräumt: 136 MB (42 % der Datenbank).
--
-- Maßnahmen (keine Funktion fällt weg, sie laufen nur seltener/versetzt):
--  1. Hintergrund-Anreicherungen seltener (KI-Biografien, Bilder, Kataloge,
--     Social Links, Programmhefte, Werkeinführungen).
--  2. Die */10-Jobs auf verschiedene Minuten verteilt statt alle gleichzeitig.
--  3. Protokoll der Cron-Läufe auf 2 Tage begrenzt, täglich aufgeräumt.
--  4. Index für cleanup_stale_ingestion_runs (lief alle 10 Minuten per
--     Seq-Scan über 38.000 Import-Läufe), alte Import-Läufe nach 60 Tagen weg.

set statement_timeout = '15min';

-- 1. + 2. Neue Zeitpläne. Jobs, die es nicht gibt, werden übersprungen.
do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- Hintergrund-Anreicherung: Bestand ist weitgehend abgearbeitet.
      ('person-ai-biography-enrichment',     '3-59/15 * * * *'),
      ('ensemble-ai-biography-enrichment',   '11 * * * *'),
      ('venue-ai-biography-enrichment',      '41 * * * *'),
      ('composer-work-catalog-sync',         '8-59/20 * * * *'),
      ('event-reference-enrichment',         '1-59/10 * * * *'),
      ('person-image-enrichment-priority',   '6-59/15 * * * *'),
      ('image-enrichment',                   '12-59/15 * * * *'),
      ('social-links-research',              '23 * * * *'),
      ('find-program-booklets',              '17-59/30 * * * *'),
      ('booklet-work-facts',                 '27-59/30 * * * *'),
      ('work-introductions',                 '33 * * * *'),
      ('musikverein-detail-sync',            '4-59/15 * * * *'),
      ('subscription-sync',                  '9-59/10 * * * *'),
      ('daily-ingestion',                    '2-59/5 * * * *'),
      -- */10-Jobs: bisher alle zur Minute 0, 10, 20 … — jetzt verteilt.
      ('auto-approve-open-license-images',   '5-59/30 * * * *'),
      ('biennale-detail-sync',               '1-59/10 * * * *'),
      ('br-chor-detail-sync',                '2-59/10 * * * *'),
      ('brso-detail-sync',                   '3-59/10 * * * *'),
      ('cleanup-stale-ingestion-runs',       '4-59/10 * * * *'),
      ('ensemble-profile-enrichment',        '15 * * * *'),
      ('event-price-enrichment',             '5-59/10 * * * *'),
      ('gaertnerplatz-detail-sync',          '6-59/10 * * * *'),
      ('gasteig-detail-sync',                '7-59/10 * * * *'),
      ('komischeoperberlin-detail-sync',     '8-59/10 * * * *'),
      ('mko-detail-sync',                    '9-59/10 * * * *'),
      ('mphil-detail-sync',                  '0-59/10 * * * *'),
      ('person-profile-enrichment',          '25 * * * *'),
      ('staatsoper-detail-sync',             '1-59/10 * * * *'),
      ('venue-profile-enrichment',           '35 * * * *'),
      ('volksoperwien-detail-sync',          '3-59/10 * * * *'),
      ('wienerphilharmoniker-detail-sync',   '7-59/10 * * * *'),
      ('work-profile-enrichment',            '45 * * * *')
    ) as v(jobname, schedule)
  loop
    perform cron.alter_job(job_id := j.jobid, schedule := r.schedule)
    from cron.job j where j.jobname = r.jobname;
  end loop;
end;
$$;

-- 3. Protokoll der Cron-Läufe begrenzen.
delete from cron.job_run_details where start_time < now() - interval '2 days';

select cron.unschedule(jobid) from cron.job where jobname = 'cleanup-cron-run-details';
select cron.schedule('cleanup-cron-run-details', '13 4 * * *',
  $$ delete from cron.job_run_details where start_time < now() - interval '2 days' $$);

-- 4. Import-Läufe: Index für die Aufräumfunktion, alte Läufe entfernen.
create index if not exists ingestion_runs_running_idx
  on public.ingestion_runs (started_at) where status = 'running';

delete from public.ingestion_runs where started_at < now() - interval '60 days' and status <> 'running';

select cron.unschedule(jobid) from cron.job where jobname = 'cleanup-old-ingestion-runs';
select cron.schedule('cleanup-old-ingestion-runs', '19 4 * * *',
  $$ delete from public.ingestion_runs where started_at < now() - interval '60 days' and status <> 'running' $$);
