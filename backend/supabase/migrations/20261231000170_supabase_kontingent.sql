-- Supabase-Kontingent (11.11.2026): Log-Ingestion 7,4/1 GB, Egress 6,1/5 GB
-- im Free-Plan. Häufige Hintergrund-Jobs (alle 3–10 Min.) erzeugen bei jedem
-- Lauf Edge-Function- und Datenbank-Logs. Takte deutlich gesenkt und
-- versetzt; Inhalte bleiben aktuell genug (Konzertdaten ändern sich selten).
do $$
declare
  r record;
  plan constant jsonb := '{
    "biennale-detail-sync": "3 * * * *",
    "br-chor-detail-sync": "8 * * * *",
    "brso-detail-sync": "13 * * * *",
    "gaertnerplatz-detail-sync": "18 * * * *",
    "gasteig-detail-sync": "23 * * * *",
    "komischeoperberlin-detail-sync": "28 * * * *",
    "mko-detail-sync": "33 * * * *",
    "mphil-detail-sync": "38 * * * *",
    "staatsoper-detail-sync": "43 * * * *",
    "volksoperwien-detail-sync": "48 * * * *",
    "wienerphilharmoniker-detail-sync": "53 * * * *",
    "musikverein-detail-sync": "58 * * * *",
    "social-links-research": "11 */2 * * *",
    "subscription-sync": "26,56 * * * *",
    "ensemble-ai-biography-enrichment": "6,36 * * * *",
    "venue-ai-biography-enrichment": "21,51 * * * *",
    "booklet-work-facts": "16,46 * * * *",
    "work-duration-enrichment": "31 * * * *",
    "refresh-search-index": "9,39 * * * *",
    "work-introductions": "44 * * * *",
    "auto-approve-open-license-images": "14,44 * * * *",
    "find-program-booklets": "29 */2 * * *",
    "entity-popularity-refresh": "27 */3 * * *"
  }';
begin
  for r in select jobid, jobname from cron.job where plan ? jobname loop
    perform cron.alter_job(r.jobid, schedule := plan->>r.jobname);
  end loop;
end $$;

-- Protokoll der Cron-Läufe kürzer halten (zählt ebenfalls zu den Logs/DB).
delete from cron.job_run_details where end_time < now() - interval '2 days';
