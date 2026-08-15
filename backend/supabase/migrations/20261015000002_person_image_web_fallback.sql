-- Der breite Web-Fallback ist netzwerkintensiver als Wikipedia/Wikidata.
-- Kleine, häufige Batches vermeiden WORKER_RESOURCE_LIMIT und arbeiten die
-- faire image_search_checked_at-Queue dennoch kontinuierlich ab.
create or replace function public.run_person_image_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-entity-images',
    body := '{"type":"person","limit":4,"fastFallback":true}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon_key,'Authorization','Bearer ' || v_anon_key)
  );
exception when others then
  raise warning 'run_person_image_enrichment fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;
