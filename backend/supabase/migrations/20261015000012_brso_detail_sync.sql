-- Nutzeranfrage: "das sollen auch andere websites können [wie die
-- Staatsoper]" — zweite Quelle mit eigener Termin-Detailseiten-Pipeline
-- (hydrate-brso-events), analog zu staatsoper_detail_synced_at/
-- staatsoper_detail_sync_error (siehe 20261013000001_staatsoper_detail_sync_state.sql).
alter table events
  add column if not exists brso_detail_synced_at timestamptz,
  add column if not exists brso_detail_sync_error text;

create index if not exists events_brso_detail_pending_idx
  on events (start_datetime)
  where website_url ilike '%brso.de/%'
    and brso_detail_synced_at is null;

update events
set brso_detail_synced_at = null,
    brso_detail_sync_error = null
where website_url ilike '%brso.de/%'
  and start_datetime >= now()
  and status in ('scheduled', 'sold_out');

create or replace function run_brso_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-brso-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_brso_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('brso-detail-sync','*/10 * * * *',$$ select run_brso_detail_sync(); $$);

create or replace function queue_near_term_brso_resync()
returns void language sql as $$
  update events
  set brso_detail_synced_at = null,
      brso_detail_sync_error = null
  where website_url ilike '%brso.de/%'
    and status in ('scheduled','sold_out')
    and start_datetime >= now()
    and start_datetime < now() + interval '30 days';
$$;

select cron.schedule('brso-near-term-resync','20 2 * * *',$$ select queue_near_term_brso_resync(); $$);
