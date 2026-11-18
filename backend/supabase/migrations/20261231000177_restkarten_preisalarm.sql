-- Erstellt von Claude Code (18.11.2026): Restkarten- und Preisalarm für
-- gemerkte Konzerte. Stündlicher Vergleich von Ticketstatus und Mindestpreis;
-- Änderungen landen in event_changes (field_name 'tickets' / 'price_min'),
-- notify-changes schickt den Push an alle, die das Konzert gemerkt haben.
create table if not exists public.event_ticket_snapshots (
  event_id uuid primary key references events(id) on delete cascade,
  status text,
  price_min numeric,
  updated_at timestamptz not null default now()
);
alter table public.event_ticket_snapshots enable row level security;

create or replace function public.detect_ticket_changes()
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select e.id, e.remaining_tickets_status as status, e.price_min, s.status as old_status, s.price_min as old_price, s.event_id is not null as known
    from events e
    left join event_ticket_snapshots s on s.event_id = e.id
    where e.start_datetime between now() and now() + interval '120 days'
      and e.status in ('scheduled', 'sold_out')
      and exists (select 1 from favorites f where f.event_id = e.id)
      and (s.event_id is null or s.status is distinct from e.remaining_tickets_status or s.price_min is distinct from e.price_min)
  loop
    if r.known then
      -- Wieder Karten: vorher ausverkauft, jetzt verfügbar/wenige.
      if r.old_status = 'sold_out' and coalesce(r.status, 'available') <> 'sold_out' then
        insert into event_changes(event_id, field_name, old_value, new_value) values (r.id, 'tickets', r.old_status, coalesce(r.status, 'available'));
        v_count := v_count + 1;
      end if;
      -- Günstiger: Mindestpreis um mindestens 10 % bzw. 5 € gesunken.
      if r.old_price is not null and r.price_min is not null and r.price_min > 0
         and r.price_min <= r.old_price * 0.9 and r.old_price - r.price_min >= 5 then
        insert into event_changes(event_id, field_name, old_value, new_value) values (r.id, 'price_min', r.old_price::text, r.price_min::text);
        v_count := v_count + 1;
      end if;
    end if;
    insert into event_ticket_snapshots(event_id, status, price_min, updated_at) values (r.id, r.status, r.price_min, now())
    on conflict (event_id) do update set status = excluded.status, price_min = excluded.price_min, updated_at = now();
  end loop;
  return v_count;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'detect-ticket-changes';
select cron.schedule('detect-ticket-changes', '27 * * * *', $$ select detect_ticket_changes(); $$);
