-- Erstellt von Claude Code (Nutzerwunsch 27.10.2026): Klangradar Plus
-- serverseitig, Einlöse-Codes, Sofort-Alarm für Plus und ein reicheres
-- "Dein Konzertjahr".
--
-- 1. plus_entitlements: Freischaltung je Nutzer. Quelle 'code' (eingelöst)
--    oder später 'app_store' (App Store Server Notifications). Die App
--    wertet Plus als aktiv, wenn StoreKit ODER my_plus_status() es meldet.
-- 2. plus_codes + redeem_plus_code(): Codes mit Laufzeit, Nutzungszahl und
--    optional einer erlaubten E-Mail-Adresse. Erster Code: nur für
--    jakob@klangradar.com (Test-/Gründerzugang).
-- 3. push_candidates: Plus-Mitglieder bekommen neue Konzerte von Gefolgten
--    sofort, einzeln pro Konzert (statt einmal täglich gesammelt).
-- 4. my_concert_year: zusätzlich Monats- und Wochentagsverteilung,
--    Top-Säle, Top-Mitwirkende, Städte und Werke.

create table if not exists public.plus_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  source text not null check (source in ('code', 'app_store')),
  code text,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.plus_entitlements enable row level security;
create policy "Eigene Plus-Freischaltung lesen" on public.plus_entitlements for select using (user_id = auth.uid());

create table if not exists public.plus_codes (
  code text primary key,
  allowed_email text,
  duration interval,              -- null = unbegrenzt
  max_uses int not null default 1,
  uses int not null default 0,
  valid_until timestamptz,
  note text,
  created_at timestamptz not null default now()
);
alter table public.plus_codes enable row level security;  -- keine Policies: nur über redeem_plus_code

create table if not exists public.plus_code_redemptions (
  code text not null references public.plus_codes(code) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  primary key (code, user_id)
);
alter table public.plus_code_redemptions enable row level security;

create or replace function public.is_plus(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from plus_entitlements
                  where user_id = p_user_id and starts_at <= now() and (expires_at is null or expires_at > now()));
$$;
revoke all on function public.is_plus(uuid) from public, anon, authenticated;
grant execute on function public.is_plus(uuid) to service_role;

create or replace function public.my_plus_status()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('active', true, 'source', source, 'expires_at', expires_at)
                     from plus_entitlements
                    where user_id = auth.uid() and starts_at <= now() and (expires_at is null or expires_at > now())),
                  jsonb_build_object('active', false));
$$;
revoke all on function public.my_plus_status() from public, anon;
grant execute on function public.my_plus_status() to authenticated;

-- Liefert {ok, message, expires_at}. Fehlermeldungen sind für die App gedacht.
create or replace function public.redeem_plus_code(p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_code plus_codes%rowtype;
  v_email text;
  v_expires timestamptz;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'message', 'Bitte melde dich zuerst an.');
  end if;
  select * into v_code from plus_codes where upper(code) = upper(trim(p_code)) for update;
  if v_code.code is null or (v_code.valid_until is not null and v_code.valid_until < now()) then
    return jsonb_build_object('ok', false, 'message', 'Diesen Code kennen wir nicht oder er ist abgelaufen.');
  end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  if v_code.allowed_email is not null and lower(v_code.allowed_email) <> coalesce(v_email, '') then
    return jsonb_build_object('ok', false, 'message', 'Dieser Code gilt für ein anderes Konto.');
  end if;
  if exists (select 1 from plus_code_redemptions where code = v_code.code and user_id = auth.uid()) then
    return jsonb_build_object('ok', true, 'message', 'Du hast diesen Code bereits eingelöst.',
      'expires_at', (select expires_at from plus_entitlements where user_id = auth.uid()));
  end if;
  if v_code.uses >= v_code.max_uses then
    return jsonb_build_object('ok', false, 'message', 'Dieser Code wurde schon zu oft eingelöst.');
  end if;

  v_expires := case when v_code.duration is null then null else now() + v_code.duration end;
  insert into plus_code_redemptions (code, user_id) values (v_code.code, auth.uid());
  update plus_codes set uses = uses + 1 where code = v_code.code;
  insert into plus_entitlements (user_id, source, code, starts_at, expires_at)
  values (auth.uid(), 'code', v_code.code, now(), v_expires)
  on conflict (user_id) do update
    set source = 'code', code = excluded.code, starts_at = least(plus_entitlements.starts_at, now()),
        expires_at = case when plus_entitlements.expires_at is null or excluded.expires_at is null then null
                          else greatest(plus_entitlements.expires_at, excluded.expires_at) end,
        updated_at = now();
  return jsonb_build_object('ok', true, 'message', 'Klangradar Plus ist freigeschaltet.', 'expires_at', v_expires);
end; $$;
revoke all on function public.redeem_plus_code(text) from public, anon;
grant execute on function public.redeem_plus_code(text) to authenticated;

insert into public.plus_codes (code, allowed_email, duration, max_uses, note)
values ('KLANGRADAR-GRUENDER', 'jakob@klangradar.com', null, 1, 'Gründerzugang Jakob (Claude Code, 27.10.2026)')
on conflict (code) do nothing;

create or replace function public.push_candidates()
returns table (user_id uuid, kind text, dedupe_key text, event_id uuid, priority int, transactional boolean, facts jsonb)
language sql stable security definer set search_path = public as $$
  with users as (
    select distinct pt.user_id, coalesce(np.followed_ensemble_new_event, true) as p_followed,
      coalesce(np.almost_sold_out, true) as p_sold, coalesce(np.reminder_day_before, true) as p_remind,
      coalesce(np.new_matching_events, true) as p_match,
      p.display_name, p.active_city_id, public.is_plus(pt.user_id) as is_plus
    from push_tokens pt
    join profiles p on p.id = pt.user_id
    left join notification_preferences np on np.user_id = pt.user_id
  ),
  ev as (
    select e.id, e.slug, e.title, e.start_datetime, e.remaining_tickets_status, e.doors_info, e.image_urls[1] as image_url,
      v.name as venue_name, v.id as venue_id, e.created_at,
      (select string_agg(coalesce(pe.full_name, en.name), ', ' order by ep.display_order nulls last)
       from event_participants ep left join persons pe on pe.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
       where ep.event_id = e.id) as cast_names,
      (select string_agg(coalesce(c.full_name || ': ', '') || w.title, ' · ' order by ew.position)
       from event_works ew join works w on w.id = ew.work_id left join persons c on c.id = w.composer_id
       where ew.event_id = e.id) as program
    from events e left join venues v on v.id = e.venue_id
    where e.status = 'scheduled' and e.start_datetime >= now() - interval '2 days'
  ),
  -- 1. Neu angekündigt von Gefolgten (gesammelt: eine Mitteilung pro Nutzer und Tag)
  followed_new as (
    select u.user_id, 'new_followed'::text as kind,
      'new_followed:' || to_char(now() at time zone 'Europe/Berlin', 'YYYY-MM-DD') as dedupe_key,
      (array_agg(ev.id order by ev.start_datetime))[1] as event_id, 70 as priority, false as transactional,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1),
        'count', count(distinct ev.id),
        'followed', (array_agg(distinct coalesce(fp.full_name, fe.name, fv.name)))[1:3],
        'events', (jsonb_agg(distinct jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'slug', ev.slug, 'image_url', ev.image_url)))) as facts
    from users u
    join ev on ev.created_at > now() - interval '24 hours' and ev.start_datetime > now()
    left join event_participants ep on ep.event_id = ev.id
    left join persons fp on fp.id = ep.person_id and exists (select 1 from user_favorite_persons f where f.user_id = u.user_id and f.person_id = fp.id)
    left join ensembles fe on fe.id = ep.ensemble_id and exists (select 1 from user_favorite_ensembles f where f.user_id = u.user_id and f.ensemble_id = fe.id)
    left join venues fv on fv.id = ev.venue_id and exists (select 1 from user_favorite_venues f where f.user_id = u.user_id and f.venue_id = fv.id)
    where u.p_followed and not u.is_plus and (fp.id is not null or fe.id is not null or fv.id is not null)
    group by u.user_id, u.display_name
  ),
  -- 1b. Plus: Sofort-Alarm, eine Mitteilung pro neuem Konzert (außerhalb des Tagesbudgets, siehe select.ts)
  followed_instant as (
    select u.user_id, 'new_followed'::text as kind, 'new_followed:' || ev.id as dedupe_key, ev.id as event_id,
      90 as priority, false as transactional,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1),
        'count', 1, 'instant', true, 'slug', ev.slug, 'image_url', ev.image_url,
        'followed', (array_agg(distinct coalesce(fp.full_name, fe.name, fv.name)))[1:3],
        'events', jsonb_build_array(jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'slug', ev.slug, 'image_url', ev.image_url))) as facts
    from users u
    join ev on ev.created_at > now() - interval '24 hours' and ev.start_datetime > now()
    left join event_participants ep on ep.event_id = ev.id
    left join persons fp on fp.id = ep.person_id and exists (select 1 from user_favorite_persons f where f.user_id = u.user_id and f.person_id = fp.id)
    left join ensembles fe on fe.id = ep.ensemble_id and exists (select 1 from user_favorite_ensembles f where f.user_id = u.user_id and f.ensemble_id = fe.id)
    left join venues fv on fv.id = ev.venue_id and exists (select 1 from user_favorite_venues f where f.user_id = u.user_id and f.venue_id = fv.id)
    where u.p_followed and u.is_plus and (fp.id is not null or fe.id is not null or fv.id is not null)
    group by u.user_id, u.display_name, ev.id, ev.slug, ev.title, ev.start_datetime, ev.venue_name, ev.image_url
  ),
  -- 2. Fast ausverkauft (gemerkt, noch nicht "ich gehe hin")
  sold as (
    select u.user_id, 'almost_sold_out', 'almost_sold_out:' || ev.id, ev.id, 80, false,
      jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'cast', ev.cast_names, 'program', ev.program, 'slug', ev.slug, 'image_url', ev.image_url)
    from users u join favorites f on f.user_id = u.user_id and f.status = 'interested'
    join ev on ev.id = f.event_id and ev.remaining_tickets_status = 'few_left' and ev.start_datetime between now() and now() + interval '30 days'
    where u.p_sold
  ),
  -- 3. Konzerttag (Vormittag): Einlass, Anreise
  concert_day as (
    select u.user_id, 'concert_day', 'concert_day:' || ev.id, ev.id, 95, true,
      jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'doors', ev.doors_info, 'cast', ev.cast_names, 'program', ev.program, 'slug', ev.slug, 'image_url', ev.image_url)
    from users u join favorites f on f.user_id = u.user_id
    join ev on ev.id = f.event_id
      and (ev.start_datetime at time zone 'Europe/Berlin')::date = (now() at time zone 'Europe/Berlin')::date
      and ev.start_datetime > now() + interval '2 hours'
    where u.p_remind
  ),
  -- 4. "Wie war's?" am Morgen danach
  how_was_it as (
    select u.user_id, 'how_was_it', 'how_was_it:' || e.id, e.id, 60, false,
      jsonb_build_object('title', e.title, 'venue', v.name, 'slug', e.slug, 'image_url', e.image_urls[1])
    from users u join favorites f on f.user_id = u.user_id and f.status = 'attending'
    join events e on e.id = f.event_id
      and (e.start_datetime at time zone 'Europe/Berlin')::date = (now() at time zone 'Europe/Berlin')::date - 1
    left join venues v on v.id = e.venue_id
    where not exists (select 1 from event_ratings r where r.user_id = u.user_id and r.event_id = e.id)
  ),
  -- 5. Wochen-Tipp (donnerstags): das eine beste Konzert
  weekly as (
    select u.user_id, 'weekly_pick', 'weekly_pick:' || to_char(now() at time zone 'Europe/Berlin', 'IYYY-IW'), pick.event_id, 50, false,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1), 'title', pick.title, 'start', pick.start_datetime,
        'venue', pick.venue_name, 'reason', pick.reason_detail, 'slug', pick.slug, 'image_url', pick.image_url,
        'cast', (select cast_names from ev where ev.id = pick.event_id), 'program', (select program from ev where ev.id = pick.event_id))
    from users u
    cross join lateral (select * from newsletter_personal_picks(u.user_id, 10, 1)) pick
    where u.p_match and extract(isodow from now() at time zone 'Europe/Berlin') = 4
      and not exists (select 1 from favorites f where f.user_id = u.user_id and f.event_id = pick.event_id)
  ),
  -- 6. Wiederkehr (3 Wochen inaktiv, höchstens monatlich)
  reengage as (
    select u.user_id, 'reengagement', 'reengagement:' || to_char(now(), 'YYYY-MM'), pick.event_id, 30, false,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1), 'title', pick.title, 'start', pick.start_datetime,
        'venue', pick.venue_name, 'reason', pick.reason_detail, 'slug', pick.slug, 'image_url', pick.image_url)
    from users u
    cross join lateral (select * from newsletter_personal_picks(u.user_id, 14, 1)) pick
    where u.p_match
      and not exists (select 1 from event_views vw where vw.user_id = u.user_id and vw.viewed_at > now() - interval '21 days')
      and exists (select 1 from event_views vw where vw.user_id = u.user_id)
  )
  select c.* from (
    select * from followed_new
    union all select * from followed_instant
    union all select * from sold
    union all select * from concert_day
    union all select * from how_was_it
    union all select * from weekly
    union all select * from reengage
  ) c
  where not exists (select 1 from push_log l where l.user_id = c.user_id and l.dedupe_key = c.dedupe_key);
$$;

create or replace function public.my_concert_year(p_year int default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_year int := coalesce(p_year, extract(year from now())::int);
  v_from timestamptz := make_timestamptz(v_year, 1, 1, 0, 0, 0, 'Europe/Berlin');
  v_to timestamptz := make_timestamptz(v_year + 1, 1, 1, 0, 0, 0, 'Europe/Berlin');
  v_result jsonb;
begin
  if auth.uid() is null then return '{}'::jsonb; end if;
  with attended as (
    select e.id, e.slug, e.title, e.start_datetime, e.end_datetime, e.duration_minutes, e.venue_id from events e
     where e.start_datetime >= v_from and e.start_datetime < v_to and e.start_datetime <= now()
       and (exists (select 1 from event_attendance a where a.event_id = e.id and a.user_id = auth.uid())
            or exists (select 1 from event_ratings r where r.event_id = e.id and r.user_id = auth.uid())
            or exists (select 1 from favorites f where f.event_id = e.id and f.user_id = auth.uid() and f.status = 'attending'))
  ),
  journal as (
    select j.id, coalesce(j.title, 'Eigener Konzertabend') as title, j.starts_at, j.duration_minutes, j.venue_id,
           coalesce(v.name, j.venue_name) as venue_name, v.address_city as city, j.program, j.participants
      from user_concert_entries j left join venues v on v.id = j.venue_id
     where j.user_id = auth.uid() and j.starts_at >= v_from and j.starts_at < v_to and j.starts_at <= now()
  ),
  visits as (
    select a.start_datetime as d, v.name as venue_name, v.address_city as city from attended a left join venues v on v.id = a.venue_id
    union all
    select starts_at, venue_name, city from journal
  ),
  composers as (
    select a.id::text as concert, p.full_name as name from attended a
      join event_works ew on ew.event_id = a.id join works wk on wk.id = ew.work_id join persons p on p.id = wk.composer_id
    union
    select j.id::text, coalesce(p.full_name, item->>'composer') from journal j
      cross join lateral jsonb_array_elements(j.program) item
      left join works wk on wk.id = nullif(item->>'work_id', '')::uuid
      left join persons p on p.id = wk.composer_id
     where coalesce(p.full_name, item->>'composer') is not null
  ),
  works_heard as (
    select ew.work_id::text as work from attended a join event_works ew on ew.event_id = a.id
    union
    select coalesce(nullif(item->>'work_id', ''), lower(item->>'title')) from journal j cross join lateral jsonb_array_elements(j.program) item
  ),
  artists as (
    select coalesce(pp.full_name, en.name) as name from attended a join event_participants ep on ep.event_id = a.id
      left join persons pp on pp.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
    union all
    select item->>'name' from journal j cross join lateral jsonb_array_elements(j.participants) item
  )
  select jsonb_build_object(
    'year', v_year,
    'concerts', (select count(*) from visits),
    'minutes', (select coalesce(sum(coalesce(duration_minutes, extract(epoch from (end_datetime - start_datetime)) / 60, 120)), 0)::int from attended)
               + (select coalesce(sum(coalesce(duration_minutes, 120)), 0)::int from journal),
    'venues', (select count(distinct venue_name) from visits),
    'cities', (select count(distinct city) from visits),
    'works', (select count(*) from works_heard where work is not null),
    'months', (select jsonb_agg(coalesce(c, 0) order by m) from generate_series(1, 12) m
                left join (select extract(month from d at time zone 'Europe/Berlin')::int mo, count(*) c from visits group by 1) t on t.mo = m),
    'weekdays', (select jsonb_agg(coalesce(c, 0) order by w) from generate_series(1, 7) w
                left join (select extract(isodow from d at time zone 'Europe/Berlin')::int wd, count(*) c from visits group by 1) t on t.wd = w),
    'top_composers', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'count', c)) from (
        select name, count(distinct concert) c from composers group by name order by c desc, name limit 5) t), '[]'),
    'top_venues', coalesce((select jsonb_agg(jsonb_build_object('name', venue_name, 'count', c)) from (
        select venue_name, count(*) c from visits where venue_name is not null group by venue_name order by c desc, venue_name limit 4) t), '[]'),
    'top_artists', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'count', c)) from (
        select name, count(*) c from artists where name is not null group by name order by c desc, name limit 3) t), '[]'),
    'top_venue', (select venue_name from visits where venue_name is not null group by venue_name order by count(*) desc limit 1),
    'top_artist', (select name from artists where name is not null group by name order by count(*) desc limit 1),
    'best_rated', (select jsonb_build_object('title', e.title, 'stars', r.stars, 'slug', e.slug) from event_ratings r join attended e on e.id = r.event_id
                    where r.user_id = auth.uid() order by r.stars desc, e.start_datetime desc limit 1),
    'first', (select jsonb_build_object('title', title, 'date', d) from (
        select title, start_datetime d from attended union all select title, starts_at from journal) f order by d limit 1)
  ) into v_result;
  return v_result;
end; $$;
grant execute on function public.my_concert_year(int) to authenticated;
