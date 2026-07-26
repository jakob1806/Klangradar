-- Wiederkehrender Lauf für resolve-entity-candidates — ursprünglich bewusst
-- ohne Cron (siehe Kommentar in resolve-entity-candidates/index.ts: "jeder
-- Lauf kostet Tavily-/LLM-Credits"). Nach dem Umstieg von Tavily (Kontingent
-- ausgeschöpft) auf das kostenlose DuckDuckGo in _shared/entityEnrichment.ts
-- entfällt der Kostengrund gegen einen Cron — nur noch LLM-Aufrufe, die auch
-- die übrigen Enrichment-Jobs bereits auf Cron laufen lassen. Batch-Größe
-- klein gehalten (limit=8), da jeder Kandidat eine echte Websuche + mehrere
-- Seitenabrufe braucht (gleiche Vorsicht wie bei den Profil-Enrichments).
create or replace function run_entity_candidate_resolution()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/resolve-entity-candidates',
    body := '{"limit": 8}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_entity_candidate_resolution: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'entity-candidate-resolution',
  '*/15 * * * *',
  $$ select run_entity_candidate_resolution(); $$
);
