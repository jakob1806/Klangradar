-- Wallet-Karten aktuell halten (09.11.2026): Apple-Wallet-Webdienst.
-- Jede erzeugte Karte wird mit ihren Parametern gemerkt; Geräte melden sich
-- für Aktualisierungen an. Ändert sich ein Konzert (Zeit, Titel, Ort,
-- Absage), wird die Karte als geändert markiert und wallet-service benachrichtigt.
create table if not exists public.wallet_passes (
  serial text primary key,
  event_id uuid references public.events(id) on delete cascade,
  params text not null,
  updated_at timestamptz not null default now()
);
create index if not exists wallet_passes_event on public.wallet_passes (event_id);
alter table public.wallet_passes enable row level security;

create table if not exists public.wallet_registrations (
  device_id text not null,
  serial text not null references public.wallet_passes(serial) on delete cascade,
  push_token text not null,
  created_at timestamptz not null default now(),
  primary key (device_id, serial)
);
alter table public.wallet_registrations enable row level security;
-- Zugriff ausschließlich über Edge Functions (Service-Rolle).

create or replace function public.venue_latlng(p_venue uuid)
returns table (lat double precision, lng double precision)
language sql stable security definer set search_path = public, extensions as $$
  select ST_Y(location::geometry), ST_X(location::geometry) from venues where id = p_venue and location is not null;
$$;
grant execute on function public.venue_latlng(uuid) to service_role;

create or replace function public.wallet_mark_event_changed()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if (new.start_datetime is distinct from old.start_datetime) or (new.title is distinct from old.title)
     or (new.venue_id is distinct from old.venue_id) or (new.status is distinct from old.status) then
    update wallet_passes set updated_at = now() where event_id = new.id;
    if found then
      begin
        perform net.http_post(
          url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/wallet-service/internal/push',
          body := jsonb_build_object('event_id', new.id),
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', internal_function_secret(),
            'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
          timeout_milliseconds := 10000);
      exception when others then
        raise warning 'wallet_mark_event_changed: % (%)', sqlerrm, sqlstate;
      end;
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists wallet_event_changed on public.events;
create trigger wallet_event_changed after update on public.events
  for each row execute function public.wallet_mark_event_changed();
