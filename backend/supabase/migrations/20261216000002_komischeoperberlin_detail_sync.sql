-- Erste venue-spezifische Hydration-Pipeline der Multi-City-Erweiterung
-- (Nutzeranfrage: "mache venue-spezifische Hydration-Parser wie bei
-- München"), analog zu staatsoper_detail_synced_at/brso_detail_synced_at
-- (siehe 20261013000001/20261015000012). x-internal-secret im Cron-Header
-- nötig, siehe 20261029000002_internal_function_secret_for_cron.sql.
alter table events
  add column if not exists komischeoperberlin_detail_synced_at timestamptz,
  add column if not exists komischeoperberlin_detail_sync_error text;

create index if not exists events_komischeoperberlin_detail_pending_idx
  on events (start_datetime)
  where website_url ilike '%komische-oper-berlin.de/%'
    and komischeoperberlin_detail_synced_at is null;

update events
set komischeoperberlin_detail_synced_at = null,
    komischeoperberlin_detail_sync_error = null
where website_url ilike '%komische-oper-berlin.de/%'
  and start_datetime >= now()
  and status in ('scheduled', 'sold_out');

create or replace function run_komischeoperberlin_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-komischeoperberlin-events',
    body := '{"limit":10}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon, 'Authorization','Bearer ' || v_anon
    )
  );
exception when others then
  raise warning 'run_komischeoperberlin_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('komischeoperberlin-detail-sync', '*/10 * * * *', $$ select run_komischeoperberlin_detail_sync(); $$);

create or replace function queue_near_term_komischeoperberlin_resync()
returns void language sql as $$
  update events
  set komischeoperberlin_detail_synced_at = null,
      komischeoperberlin_detail_sync_error = null
  where website_url ilike '%komische-oper-berlin.de/%'
    and status in ('scheduled','sold_out')
    and start_datetime >= now()
    and start_datetime < now() + interval '30 days';
$$;

select cron.schedule('komischeoperberlin-near-term-resync', '25 2 * * *', $$ select queue_near_term_komischeoperberlin_resync(); $$);
