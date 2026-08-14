alter table events
  add column if not exists staatsoper_detail_synced_at timestamptz,
  add column if not exists staatsoper_detail_sync_error text;

create index if not exists events_staatsoper_detail_pending_idx
  on events (start_datetime)
  where website_url ilike '%staatsoper.de/%'
    and staatsoper_detail_synced_at is null;

-- Der bisherige Offset-Backfill war nach Laufzeitabbrüchen nicht
-- fortsetzbar. Alle kommenden Staatsoper-Termine einmal in die neue,
-- zustandsbasierte Queue stellen; erfolgreiche Zeilen verschwinden daraus.
update events
set staatsoper_detail_synced_at = null,
    staatsoper_detail_sync_error = null
where website_url ilike '%staatsoper.de/%'
  and start_datetime >= now()
  and status in ('scheduled', 'sold_out');
