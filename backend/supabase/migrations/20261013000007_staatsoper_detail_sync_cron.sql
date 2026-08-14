create or replace function run_staatsoper_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-staatsoper-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_staatsoper_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

select cron.schedule('staatsoper-detail-sync','*/10 * * * *',$$ select run_staatsoper_detail_sync(); $$);

create or replace function queue_near_term_staatsoper_resync()
returns void language sql as $$
  update events
  set staatsoper_detail_synced_at = null,
      staatsoper_detail_sync_error = null
  where website_url ilike '%staatsoper.de/%'
    and status in ('scheduled','sold_out')
    and start_datetime >= now()
    and start_datetime < now() + interval '30 days';
$$;

select cron.schedule('staatsoper-near-term-resync','15 2 * * *',$$ select queue_near_term_staatsoper_resync(); $$);
