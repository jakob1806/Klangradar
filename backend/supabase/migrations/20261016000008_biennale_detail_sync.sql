-- Siebte Quelle mit eigener Termin-Detailseiten-Pipeline (Nutzeranfrage:
-- "füge noch lauter weitere websiten hinzu"). Kein eigenes og:image auf
-- der Produktionsseite — die Bildrecherche läuft über die bestehende
-- Kaskade.
alter table events
  add column if not exists biennale_detail_synced_at timestamptz,
  add column if not exists biennale_detail_sync_error text;

create index if not exists events_biennale_detail_pending_idx
  on events (start_datetime)
  where website_url ilike '%muenchener-biennale.de/%'
    and biennale_detail_synced_at is null;

update events
set biennale_detail_synced_at = null,
    biennale_detail_sync_error = null
where website_url ilike '%muenchener-biennale.de/%'
  and start_datetime >= now()
  and status in ('scheduled', 'sold_out');

create or replace function run_biennale_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-biennale-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_biennale_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('biennale-detail-sync','*/10 * * * *',$$ select run_biennale_detail_sync(); $$);

create or replace function queue_near_term_biennale_resync()
returns void language sql as $$
  update events
  set biennale_detail_synced_at = null,
      biennale_detail_sync_error = null
  where website_url ilike '%muenchener-biennale.de/%'
    and status in ('scheduled','sold_out')
    and start_datetime >= now()
    and start_datetime < now() + interval '30 days';
$$;

select cron.schedule('biennale-near-term-resync','50 2 * * *',$$ select queue_near_term_biennale_resync(); $$);
