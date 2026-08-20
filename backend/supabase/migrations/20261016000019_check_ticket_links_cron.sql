-- Täglicher Cron für check-ticket-links (siehe Edge Function). Einmal
-- täglich reicht — Ticketlinks werden nicht stundenweise ungültig, und
-- 100 Links/Lauf reichen bei aktueller Katalog-Größe locker, um den ganzen
-- Bestand innerhalb weniger Tage einmal durchzuprüfen.
create or replace function run_check_ticket_links()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/check-ticket-links',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_check_ticket_links: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule(
  'check-ticket-links',
  '0 6 * * *',
  $$ select run_check_ticket_links(); $$
);
