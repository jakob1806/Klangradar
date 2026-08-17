-- Fünfte Quelle mit eigener Termin-Detailseiten-Pipeline nach Staatsoper,
-- BRSO, Münchner Philharmoniker, Gasteig und MKO (Nutzeranfrage: "das
-- sollen auch andere websites können"). gaertnerplatztheater.de liefert die
-- reichste Besetzung nach Staatsoper (Bio-Links für fast alle Mitwirkenden)
-- — kein eigenes Eventfoto nötig, die Bio-Seiten selbst haben saubere
-- Porträts, die über die bestehende Bildrecherche gefunden werden.
alter table events
  add column if not exists gaertnerplatz_detail_synced_at timestamptz,
  add column if not exists gaertnerplatz_detail_sync_error text;

create index if not exists events_gaertnerplatz_detail_pending_idx
  on events (start_datetime)
  where website_url ilike '%gaertnerplatztheater.de/%'
    and gaertnerplatz_detail_synced_at is null;

update events
set gaertnerplatz_detail_synced_at = null,
    gaertnerplatz_detail_sync_error = null
where website_url ilike '%gaertnerplatztheater.de/%'
  and start_datetime >= now()
  and status in ('scheduled', 'sold_out');

create or replace function run_gaertnerplatz_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-gaertnerplatz-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_gaertnerplatz_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('gaertnerplatz-detail-sync','*/10 * * * *',$$ select run_gaertnerplatz_detail_sync(); $$);

create or replace function queue_near_term_gaertnerplatz_resync()
returns void language sql as $$
  update events
  set gaertnerplatz_detail_synced_at = null,
      gaertnerplatz_detail_sync_error = null
  where website_url ilike '%gaertnerplatztheater.de/%'
    and status in ('scheduled','sold_out')
    and start_datetime >= now()
    and start_datetime < now() + interval '30 days';
$$;

select cron.schedule('gaertnerplatz-near-term-resync','40 2 * * *',$$ select queue_near_term_gaertnerplatz_resync(); $$);
