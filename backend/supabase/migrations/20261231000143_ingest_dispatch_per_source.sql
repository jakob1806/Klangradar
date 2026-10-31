-- Erstellt von Claude Code (31.10.2026): Jede Importquelle läuft in einem
-- eigenen Edge-Function-Aufruf.
--
-- Befund nach dem Deploy von #419: run-all-sources rief runIngestion() für
-- bis zu 5 Quellen gleichzeitig IN SEINER EIGENEN Instanz auf und startete
-- 90 s lang neue Quellen. Eine Quelle, die bei Sekunde 85 begann, hatte zwar
-- ihr eigenes 100-s-Budget, die Instanz wird aber nach ~150 s beendet – der
-- Lauf blieb auf "running" und wurde nach 30 Minuten als gescheitert
-- markiert (~60 % aller Läufe). Jetzt verschickt run-all-sources pro
-- fälliger Quelle über pg_net einen eigenen Aufruf von ingest-source.
--
-- Schlüssel ist der öffentliche anon-Key (wie in den übrigen Cron-Aufrufen),
-- geschützt wird ingest-source über x-internal-secret.
create or replace function public.dispatch_ingest_source(p_source_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/ingest-source',
    body := jsonb_build_object('source_id', p_source_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', internal_function_secret(),
      'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000);
end; $$;
revoke all on function public.dispatch_ingest_source(uuid) from public, anon, authenticated;
