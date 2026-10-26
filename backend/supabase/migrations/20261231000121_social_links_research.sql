-- Erstellt von Claude Code (26.10.2026): Recherche-Cron für offizielle
-- Social-Media-Konten über Wikidata (Personen, Ensembles, Spielstätten).
alter table public.venues add column if not exists social_links jsonb default '{}';
alter table public.venues add column if not exists website_url text;
alter table public.persons add column if not exists wikidata_id text, add column if not exists social_links_checked_at timestamptz;
alter table public.ensembles add column if not exists wikidata_id text, add column if not exists social_links_checked_at timestamptz;
alter table public.venues add column if not exists wikidata_id text, add column if not exists social_links_checked_at timestamptz;

create or replace function run_social_links_research()
returns void language plpgsql as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/research-social-links',
    body := '{"limit":40}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon,
      'x-internal-secret', internal_function_secret()),
    timeout_milliseconds := 150000
  );
exception when others then
  raise warning 'run_social_links_research: % (%)', sqlerrm, sqlstate;
end;
$$;
select cron.unschedule(jobid) from cron.job where jobname = 'social-links-research';
select cron.schedule('social-links-research', '*/5 * * * *', $$ select run_social_links_research(); $$);
