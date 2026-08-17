-- Sechste Quelle mit eigener Termin-Detailseiten-Pipeline (Nutzeranfrage:
-- "füge noch lauter weitere websiten hinzu") — br-chor.de teilt dieselbe
-- Seitenvorlage wie brso.de (gleicher Sender BR), wird deshalb über
-- dieselbe parseBrsoEventDetail()-Logik verarbeitet (siehe brsoDetail.ts),
-- nur mit eigenen Sync-Tracking-Spalten/eigenem Cron.
alter table events
  add column if not exists br_chor_detail_synced_at timestamptz,
  add column if not exists br_chor_detail_sync_error text;

create index if not exists events_br_chor_detail_pending_idx
  on events (start_datetime)
  where website_url ilike '%br-chor.de/%'
    and br_chor_detail_synced_at is null;

update events
set br_chor_detail_synced_at = null,
    br_chor_detail_sync_error = null
where website_url ilike '%br-chor.de/%'
  and start_datetime >= now()
  and status in ('scheduled', 'sold_out');

create or replace function run_br_chor_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-br-chor-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_br_chor_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('br-chor-detail-sync','*/10 * * * *',$$ select run_br_chor_detail_sync(); $$);

create or replace function queue_near_term_br_chor_resync()
returns void language sql as $$
  update events
  set br_chor_detail_synced_at = null,
      br_chor_detail_sync_error = null
  where website_url ilike '%br-chor.de/%'
    and status in ('scheduled','sold_out')
    and start_datetime >= now()
    and start_datetime < now() + interval '30 days';
$$;

select cron.schedule('br-chor-near-term-resync','45 2 * * *',$$ select queue_near_term_br_chor_resync(); $$);
