-- Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Ausbau "Push & Promote"
-- im Veranstalterportal.
--
-- 1. Preise je Tag, abhängig von der Zeit bis zum Konzert (Staffeln, im
--    Admin unter /promotion-preise pflegbar). Push ist ein einzelner Versand:
--    dort gilt der Staffelpreis als Preis pro Versand.
-- 2. Laufzeit frei wählbar (Start/Ende statt "ab Zahlung bis Konzert"),
--    optional Tagesbudget (teurere Tage werden ausgelassen) und Gesamtbudget
--    (es zählen die Tage direkt vor dem Konzert, bis das Budget erreicht ist).
-- 3. Targeting: Fans der Mitwirkenden/des Orts, Interessierte der Genres,
--    Hörer:innen derselben Komponist:innen. Ausgewertet serverseitig in
--    active_event_promotions(); ohne Targeting sehen alle in der Stadt die
--    Promotion wie bisher.
--
-- Die Staffelpreise sind Startwerte. Solange dynamic_enabled = false bleibt,
-- kassiert der Checkout weiter die festen Stripe-Preise; Laufzeit, Budget und
-- Targeting wirken trotzdem.

create table if not exists public.promotion_pricing_settings (
  id boolean primary key default true check (id),
  dynamic_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
insert into public.promotion_pricing_settings (id) values (true) on conflict do nothing;
alter table public.promotion_pricing_settings enable row level security;
create policy "Preiseinstellungen lesen" on public.promotion_pricing_settings for select using (true);
grant select on public.promotion_pricing_settings to anon, authenticated;

create table if not exists public.promotion_price_tiers (
  placement text not null check (placement in ('standard', 'featured', 'local_spotlight', 'homepage_feature', 'push')),
  min_days_before int not null check (min_days_before >= 0),
  rate_cents int not null check (rate_cents >= 0),
  primary key (placement, min_days_before)
);
alter table public.promotion_price_tiers enable row level security;
create policy "Preisstaffeln lesen" on public.promotion_price_tiers for select using (true);
grant select on public.promotion_price_tiers to anon, authenticated;

-- Startwerte (Cent pro Tag bzw. pro Push): letzte 7 Tage, 8–30 Tage, ab 31 Tagen.
insert into public.promotion_price_tiers (placement, min_days_before, rate_cents) values
  ('standard', 0, 900), ('standard', 8, 500), ('standard', 31, 300),
  ('featured', 0, 1800), ('featured', 8, 1000), ('featured', 31, 600),
  ('local_spotlight', 0, 1400), ('local_spotlight', 8, 800), ('local_spotlight', 31, 500),
  ('homepage_feature', 0, 4500), ('homepage_feature', 8, 2500), ('homepage_feature', 31, 1500),
  ('push', 0, 9900), ('push', 8, 6900), ('push', 31, 4900)
on conflict do nothing;

alter table public.event_promotions
  add column if not exists run_start date,
  add column if not exists run_end date,
  add column if not exists daily_cap_cents int check (daily_cap_cents is null or daily_cap_cents > 0),
  add column if not exists total_budget_cents int check (total_budget_cents is null or total_budget_cents > 0),
  add column if not exists target_audiences text[] not null default '{}',
  add column if not exists quoted_amount_cents int;
alter table public.event_promotions drop constraint if exists event_promotions_target_audiences_check;
alter table public.event_promotions add constraint event_promotions_target_audiences_check
  check (target_audiences <@ array['followers', 'genre', 'composers']::text[]);

create or replace function public.berlin_today()
returns date language sql stable as $$ select (now() at time zone 'Europe/Berlin')::date $$;

create or replace function public.promotion_rate_cents(p_placement text, p_days_before int)
returns int language sql stable security definer set search_path = public as $$
  select t.rate_cents from promotion_price_tiers t
  where t.placement = p_placement and t.min_days_before <= greatest(p_days_before, 0)
  order by t.min_days_before desc limit 1;
$$;
grant execute on function public.promotion_rate_cents(text, int) to anon, authenticated;

-- Angebot: Tage der Laufzeit mit Staffelpreis; Tagesbudget lässt teurere
-- Tage aus, Gesamtbudget behält die Tage direkt vor dem Konzert.
create or replace function public.promotion_quote(
  p_event_id uuid, p_placement text, p_start date default null, p_end date default null,
  p_daily_cap_cents int default null, p_total_budget_cents int default null
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_concert date;
  v_today date := berlin_today();
  v_start date;
  v_end date;
  v_days jsonb := '[]'::jsonb;
  v_amount int := 0;
  v_first date;
  v_last date;
  v_rate int;
  v_day date;
  v_budget_left int := p_total_budget_cents;
  v_dynamic boolean;
begin
  select (e.start_datetime at time zone 'Europe/Berlin')::date into v_concert
  from events e where e.id = p_event_id and e.start_datetime > now();
  if v_concert is null then return jsonb_build_object('error', 'Das Event liegt in der Vergangenheit.'); end if;
  select dynamic_enabled into v_dynamic from promotion_pricing_settings;

  if p_placement = 'push' then
    v_start := least(greatest(coalesce(p_start, v_today), v_today), v_concert);
    v_rate := promotion_rate_cents(p_placement, v_concert - v_start);
    return jsonb_build_object(
      'dynamic', coalesce(v_dynamic, false), 'unit', 'push', 'concert_day', v_concert,
      'first_day', v_start, 'last_day', v_start, 'days_included', 1,
      'amount_cents', coalesce(v_rate, 0),
      'days', jsonb_build_array(jsonb_build_object('day', v_start, 'days_before', v_concert - v_start, 'rate_cents', v_rate, 'included', true)));
  end if;

  v_start := greatest(coalesce(p_start, v_today), v_today);
  v_end := least(coalesce(p_end, v_concert), v_concert);
  if v_end < v_start then return jsonb_build_object('error', 'Das Ende liegt vor dem Start.'); end if;
  if v_end - v_start > 366 then v_start := v_end - 366; end if;

  -- Rückwärts vom letzten Tag: so bleiben bei Gesamtbudget die Tage kurz
  -- vor dem Konzert erhalten.
  v_day := v_end;
  while v_day >= v_start loop
    v_rate := coalesce(promotion_rate_cents(p_placement, v_concert - v_day), 0);
    if p_daily_cap_cents is not null and v_rate > p_daily_cap_cents then
      v_days := jsonb_build_array(jsonb_build_object('day', v_day, 'days_before', v_concert - v_day, 'rate_cents', v_rate, 'included', false, 'reason', 'daily_cap')) || v_days;
    elsif v_budget_left is not null and v_rate > v_budget_left then
      v_days := jsonb_build_array(jsonb_build_object('day', v_day, 'days_before', v_concert - v_day, 'rate_cents', v_rate, 'included', false, 'reason', 'budget')) || v_days;
    else
      v_days := jsonb_build_array(jsonb_build_object('day', v_day, 'days_before', v_concert - v_day, 'rate_cents', v_rate, 'included', true)) || v_days;
      v_amount := v_amount + v_rate;
      if v_budget_left is not null then v_budget_left := v_budget_left - v_rate; end if;
      v_last := coalesce(v_last, v_day);
      v_first := v_day;
    end if;
    v_day := v_day - 1;
  end loop;

  return jsonb_build_object(
    'dynamic', coalesce(v_dynamic, false), 'unit', 'day', 'concert_day', v_concert,
    'first_day', v_first, 'last_day', v_last,
    'days_included', (select count(*) from jsonb_array_elements(v_days) d where (d->>'included')::boolean),
    'amount_cents', v_amount, 'days', v_days);
end;
$$;
grant execute on function public.promotion_quote(uuid, text, date, date, int, int) to authenticated;

-- Targeting-Prüfung für die angemeldete Person.
create or replace function public.promotion_targets_user(p_event_id uuid, p_audiences text[], p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select cardinality(coalesce(p_audiences, '{}')) = 0
    or (p_user is not null and (
      ('followers' = any(p_audiences) and (
         exists (select 1 from event_participants ep join user_favorite_persons f on f.person_id = ep.person_id
                 where ep.event_id = p_event_id and f.user_id = p_user)
         or exists (select 1 from event_participants ep join user_favorite_ensembles f on f.ensemble_id = ep.ensemble_id
                    where ep.event_id = p_event_id and f.user_id = p_user)
         or exists (select 1 from events e join user_favorite_venues f on f.venue_id = e.venue_id
                    where e.id = p_event_id and f.user_id = p_user)))
      or ('genre' = any(p_audiences) and exists (
         select 1 from event_genres eg join profile_interest_genres g on g.genre_id = eg.genre_id
         where eg.event_id = p_event_id and g.user_id = p_user))
      or ('composers' = any(p_audiences) and exists (
         select 1 from event_works ew join works w on w.id = ew.work_id
         where ew.event_id = p_event_id and w.composer_id is not null and (
           exists (select 1 from user_favorite_persons f where f.user_id = p_user and f.person_id = w.composer_id)
           or exists (select 1 from favorites fav join event_works ew2 on ew2.event_id = fav.event_id
                      join works w2 on w2.id = ew2.work_id
                      where fav.user_id = p_user and fav.event_id <> p_event_id and w2.composer_id = w.composer_id))))
    ));
$$;
revoke all on function public.promotion_targets_user(uuid, text[], uuid) from public, anon, authenticated;

-- Ausspielung: zusätzlich Laufzeit-Tage, Tagesbudget und Targeting. Dazu
-- ein Fix: im Portal-Pro-Abo enthaltene Promotionen (payment_status
-- 'included') wurden bisher nie ausgespielt, weil nur 'paid' zählte.
create or replace function public.active_event_promotions()
returns table (event_id uuid, placement text, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.event_id, p.placement, p.ends_at
  from event_promotions p
  join events e on e.id = p.event_id
  where p.status = 'approved'
    and p.payment_status in ('paid', 'included')
    and p.starts_at <= now()
    and (p.ends_at is null or p.ends_at > now())
    and e.status = 'scheduled'
    and e.start_datetime > now()
    and (p.run_start is null or berlin_today() >= p.run_start)
    and (p.run_end is null or berlin_today() <= p.run_end)
    and (p.daily_cap_cents is null
         or coalesce(promotion_rate_cents(p.placement, (e.start_datetime at time zone 'Europe/Berlin')::date - berlin_today()), 0) <= p.daily_cap_cents)
    and promotion_targets_user(p.event_id, p.target_audiences, auth.uid())
  order by p.starts_at;
$$;
grant execute on function public.active_event_promotions() to anon, authenticated;

-- Admin: Preise pflegen.
create or replace function public.admin_set_promotion_pricing(p_dynamic_enabled boolean, p_tiers jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tier jsonb;
begin
  if not is_admin() then raise exception 'Keine Berechtigung'; end if;
  update promotion_pricing_settings set dynamic_enabled = coalesce(p_dynamic_enabled, false), updated_at = now(), updated_by = auth.uid();
  for v_tier in select * from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) loop
    if (v_tier->>'rate_cents')::int < 0 then raise exception 'Preise dürfen nicht negativ sein'; end if;
    insert into promotion_price_tiers(placement, min_days_before, rate_cents)
    values (v_tier->>'placement', (v_tier->>'min_days_before')::int, (v_tier->>'rate_cents')::int)
    on conflict (placement, min_days_before) do update set rate_cents = excluded.rate_cents;
  end loop;
end;
$$;
revoke all on function public.admin_set_promotion_pricing(boolean, jsonb) from public, anon;
grant execute on function public.admin_set_promotion_pricing(boolean, jsonb) to authenticated;

notify pgrst, 'reload schema';
