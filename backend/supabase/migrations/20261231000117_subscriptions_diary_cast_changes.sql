-- Erstellt von Claude Code (26.10.2026): Abos/Zyklen der Veranstalter,
-- eigene Abos im Profil, Konzerttagebuch und Besetzungsänderungen.

-- 1. Abos / Zyklen (Name "concert_subscriptions", weil
--    organizer_subscriptions bereits das Veranstalter-Pro-Abo ist).
create table if not exists public.concert_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organizer text not null,
  organizer_name text not null,
  code text not null,
  name text not null,
  season text not null,
  url text,
  created_at timestamptz not null default now(),
  unique (organizer, season, code)
);
create table if not exists public.event_concert_subscriptions (
  event_id uuid not null references public.events(id) on delete cascade,
  subscription_id uuid not null references public.concert_subscriptions(id) on delete cascade,
  primary key (event_id, subscription_id)
);
create index if not exists event_concert_subscriptions_sub_idx on public.event_concert_subscriptions(subscription_id);
alter table public.concert_subscriptions enable row level security;
alter table public.event_concert_subscriptions enable row level security;
create policy "Abos öffentlich lesbar" on public.concert_subscriptions for select using (true);
create policy "Abo-Termine öffentlich lesbar" on public.event_concert_subscriptions for select using (true);
grant select on public.concert_subscriptions, public.event_concert_subscriptions to anon, authenticated;

-- Eigene Abos ("Ich habe dieses Abo") – fließen in den Saisonplaner.
create table if not exists public.user_concert_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  subscription_id uuid not null references public.concert_subscriptions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, subscription_id)
);
alter table public.user_concert_subscriptions enable row level security;
create policy "Eigene Abos" on public.user_concert_subscriptions for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, delete on public.user_concert_subscriptions to authenticated;

alter table public.events add column if not exists subscriptions_synced_at timestamptz;

-- Abo-Übersicht mit Terminen (für Konzertseite, Abo-Seite und Profil).
create or replace function public.subscription_overview(p_subscription_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'subscription', to_jsonb(s),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime,
               'image_urls', e.image_urls, 'venue_name', v.name) order by e.start_datetime)
      from event_concert_subscriptions es join events e on e.id = es.event_id left join venues v on v.id = e.venue_id
      where es.subscription_id = s.id and e.status in ('scheduled', 'sold_out')), '[]'::jsonb),
    'is_mine', exists (select 1 from user_concert_subscriptions u where u.subscription_id = s.id and u.user_id = auth.uid())
  )
  from concert_subscriptions s where s.id = p_subscription_id;
$$;
grant execute on function public.subscription_overview(uuid) to anon, authenticated;

-- Abo-Erkennung: Abos, aus denen der Nutzer ≥ 3 Termine gemerkt/geplant hat.
create or replace function public.suggested_subscriptions()
returns table (subscription_id uuid, name text, organizer_name text, season text, url text, matched int, total int)
language sql stable security definer set search_path = public as $$
  with mine as (
    select event_id from favorites where user_id = auth.uid()
    union select event_id from event_attendance where user_id = auth.uid() and status = 'planned'
  )
  select s.id, s.name, s.organizer_name, s.season, s.url,
         count(*) filter (where es.event_id in (select event_id from mine))::int,
         count(*)::int
  from concert_subscriptions s
  join event_concert_subscriptions es on es.subscription_id = s.id
  join events e on e.id = es.event_id and e.start_datetime >= now()
  where not exists (select 1 from user_concert_subscriptions u where u.subscription_id = s.id and u.user_id = auth.uid())
  group by s.id
  having count(*) filter (where es.event_id in (select event_id from mine)) >= 3
  order by 6 desc limit 5;
$$;
grant execute on function public.suggested_subscriptions() to authenticated;

create or replace function run_subscription_sync()
returns void language plpgsql as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/sync-event-subscriptions',
    body := '{"limit":40}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon,
      'x-internal-secret', internal_function_secret()),
    timeout_milliseconds := 150000
  );
exception when others then
  raise warning 'run_subscription_sync: % (%)', sqlerrm, sqlstate;
end;
$$;
select cron.unschedule(jobid) from cron.job where jobname in ('subscription-sync', 'subscription-resync', 'detect-cast-changes');
select cron.schedule('subscription-sync', '*/5 * * * *', $$ select run_subscription_sync(); $$);
select cron.schedule('subscription-resync', '50 3 * * 1',
  $$ update events set subscriptions_synced_at = null where start_datetime >= now() $$);

-- 2. Konzerttagebuch (Bewertung bleibt in event_ratings).
create table if not exists public.concert_diary_entries (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  note text check (note is null or char_length(note) <= 4000),
  companions text check (companions is null or char_length(companions) <= 200),
  restaurant text check (restaurant is null or char_length(restaurant) <= 200),
  other_places text check (other_places is null or char_length(other_places) <= 400),
  photo_paths text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, event_id)
);
alter table public.concert_diary_entries enable row level security;
create policy "Eigenes Tagebuch" on public.concert_diary_entries for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.concert_diary_entries to authenticated;

insert into storage.buckets (id, name, public) values ('diary-photos', 'diary-photos', false)
on conflict (id) do nothing;
create policy "Tagebuchfotos lesen" on storage.objects for select
  using (bucket_id = 'diary-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Tagebuchfotos hochladen" on storage.objects for insert
  with check (bucket_id = 'diary-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Tagebuchfotos löschen" on storage.objects for delete
  using (bucket_id = 'diary-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- 3. Besetzungsänderungen: Schnappschuss je Termin vergleichen und
--    Abweichungen als event_changes(field_name='cast') protokollieren;
--    notify-changes schickt daraus den Push an alle, die den Termin gemerkt haben.
create table if not exists public.event_cast_snapshots (
  event_id uuid primary key references public.events(id) on delete cascade,
  names text[] not null,
  updated_at timestamptz not null default now()
);
alter table public.event_cast_snapshots enable row level security;

create or replace function public.detect_cast_changes()
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    with current_cast as (
      select e.id as event_id,
             array_agg(distinct coalesce(p.full_name, en.name) order by coalesce(p.full_name, en.name))
               filter (where coalesce(p.full_name, en.name) is not null) as names
      from events e
      join event_participants ep on ep.event_id = e.id
      left join persons p on p.id = ep.person_id
      left join ensembles en on en.id = ep.ensemble_id
      where e.start_datetime between now() and now() + interval '90 days'
        and e.status in ('scheduled', 'sold_out')
      group by e.id
    )
    select c.event_id, c.names, s.names as old_names
    from current_cast c left join event_cast_snapshots s on s.event_id = c.event_id
    where s.names is distinct from c.names
  loop
    -- Erstes Auftauchen = Ausgangsstand, kein Push. Ebenso keine Meldung,
    -- wenn vorher noch niemand eingetragen war.
    if r.old_names is not null and cardinality(r.old_names) > 0 and cardinality(r.names) > 0 then
      insert into event_changes(event_id, field_name, old_value, new_value)
      values (r.event_id, 'cast',
        nullif(array_to_string(array(select unnest(r.old_names) except select unnest(r.names)), ', '), ''),
        nullif(array_to_string(array(select unnest(r.names) except select unnest(r.old_names)), ', '), ''));
      v_count := v_count + 1;
    end if;
    insert into event_cast_snapshots(event_id, names, updated_at) values (r.event_id, r.names, now())
    on conflict (event_id) do update set names = excluded.names, updated_at = now();
  end loop;
  return v_count;
end;
$$;
select cron.schedule('detect-cast-changes', '20 * * * *', $$ select detect_cast_changes(); $$);
