-- Zweite venue-spezifische Hydration-Pipeline der Multi-City-Erweiterung,
-- erste für Wien (Nutzeranfrage: "mache venue-spezifische Hydration-Parser
-- wie bei München"), analog zu 20261216000002_komischeoperberlin_detail_sync.sql.
alter table events
  add column if not exists volksoperwien_detail_synced_at timestamptz,
  add column if not exists volksoperwien_detail_sync_error text;

create index if not exists events_volksoperwien_detail_pending_idx
  on events (start_datetime)
  where website_url ilike '%volksoper.at/%'
    and volksoperwien_detail_synced_at is null;

update events
set volksoperwien_detail_synced_at = null,
    volksoperwien_detail_sync_error = null
where website_url ilike '%volksoper.at/%'
  and start_datetime >= now()
  and status in ('scheduled', 'sold_out');

create or replace function run_volksoperwien_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-volksoperwien-events',
    body := '{"limit":10}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon, 'Authorization','Bearer ' || v_anon
    )
  );
exception when others then
  raise warning 'run_volksoperwien_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('volksoperwien-detail-sync', '*/10 * * * *', $$ select run_volksoperwien_detail_sync(); $$);

create or replace function queue_near_term_volksoperwien_resync()
returns void language sql as $$
  update events
  set volksoperwien_detail_synced_at = null,
      volksoperwien_detail_sync_error = null
  where website_url ilike '%volksoper.at/%'
    and status in ('scheduled','sold_out')
    and start_datetime >= now()
    and start_datetime < now() + interval '30 days';
$$;

select cron.schedule('volksoperwien-near-term-resync', '30 2 * * *', $$ select queue_near_term_volksoperwien_resync(); $$);
