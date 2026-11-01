-- Erstellt von Claude Code (Nutzerwunsch 01.11.2026): "Gesamtquelle
-- Bayerische Staatsoper, eine Kombination aus mehreren Quellen, die immer auf
-- Duplikate, Erweiterungen und Änderungen checkt … früher gingen doppelte
-- Veranstaltungen durch, nur weil sie einen anderen Titel hatten."
--
-- Befund vor dieser Migration (Simulation gegen die Live-Daten 01.11.2026):
--  * Trotz hide_cross_source_duplicates (Migration 104) sichtbare Dubletten,
--    z. B. "Pelléas et Mélisande" (Rattle) 3×, "Lancelot" 3×, "Christmas
--    Oratorio" 3×, "Noh – The Aesthetics of Stillness" 2× aus DERSELBEN Quelle.
--  * Ursachen: Abgleich nur über gemeinsame Titelwörter, Werke zählten gar
--    nicht, gleiche Quelle wurde nie verglichen, und bei einem Treffer konnte
--    jede Aggregator-Quelle die Daten der offiziellen Quelle überschreiben.
--  * Fallen, die NICHT zusammengeführt werden dürfen: verschiedene Säle zur
--    selben Zeit (Elbphilharmonie, Musikverein, Gärtnerplatz: "Hänsel und
--    Gretel" vs. "Kinderbetreuung", "Skaterherz" vs. "Alcina").
--
-- Inhalt:
--  1. Quellen-Verbünde (source_groups) mit Rangfolge je Quelle
--     (sources.priority). Höherer Rang gewinnt bei Widersprüchen, niedrigerer
--     Rang füllt nur Lücken (siehe ingest-source/write.ts).
--  2. Gesamtquelle "Bayerische Staatsoper": offizieller Spielplan (100),
--     Concerti-Spielstättenseite (70, wieder aktiv), Cuvilliés via
--     in-muenchen (55), IN-Muenchen Klassik (45), Concerti München (40),
--     BayernCloud Tourismus (30).
--  3. venues.slot_exclusive: Bühnen mit genau einer Vorstellung zur selben
--     Zeit (Nationaltheater, Cuvilliés, Prinzregententheater, Gärtnerplatz).
--  4. event_duplicate_pairs(): mehrstufige Bewertung je Paar mit Begründung.
--  5. resolve_event_duplicates(): eindeutige Fälle automatisch zusammenführen
--     (Lücken des behaltenen Termins aus dem anderen füllen, anderen
--     ausblenden, Protokoll), unsichere in die Prüfliste der Redaktion.
--     Ersetzt den Cron-Job hide-cross-source-duplicates.

set statement_timeout = '10min';

-- 1. Verbünde und Rangfolge ---------------------------------------------------

create table if not exists public.source_groups (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);
alter table public.source_groups enable row level security;
drop policy if exists "Redaktion liest Quellen-Verbünde" on public.source_groups;
create policy "Redaktion liest Quellen-Verbünde" on public.source_groups
  for select to authenticated using (is_admin_or_editor());
drop policy if exists "Redaktion pflegt Quellen-Verbünde" on public.source_groups;
create policy "Redaktion pflegt Quellen-Verbünde" on public.source_groups
  for all to authenticated using (is_admin_or_editor()) with check (is_admin_or_editor());

alter table public.sources add column if not exists group_id uuid references public.source_groups(id) on delete set null;
alter table public.sources add column if not exists priority smallint check (priority between 0 and 100);
comment on column public.sources.priority is
  'Rang bei Widersprüchen zwischen Quellen (0–100). Leer = 80 für Quellen mit fester Spielstätte/Ensemble/Person/Veranstalter, sonst 40 (Aggregator). Redaktionell angelegte Termine (ohne Quelle) zählen 90.';

create or replace function public.source_priority(p_source_id uuid)
returns int language sql stable as $$
  select coalesce(
    (select coalesce(s.priority,
       case when s.venue_id is not null or s.ensemble_id is not null
              or s.person_id is not null or s.organizer_id is not null then 80 else 40 end)
     from sources s where s.id = p_source_id),
    90)
$$;

-- 3. Bühnen mit genau einer Vorstellung gleichzeitig ---------------------------

alter table public.venues add column if not exists slot_exclusive boolean not null default false;
comment on column public.venues.slot_exclusive is
  'Eine Bühne, ein Termin: zwei Veranstaltungen zur selben Zeit (±15 Min., gleicher Raum) sind hier praktisch immer derselbe Termin.';
update public.venues set slot_exclusive = true
 where name in ('Nationaltheater München', 'Cuvilliés-Theater', 'Prinzregententheater', 'Staatstheater am Gärtnerplatz');

-- Herkunft einer Zusammenführung, damit sie sich nachvollziehen und
-- rückgängig machen lässt.
alter table public.events add column if not exists duplicate_of uuid references public.events(id) on delete set null;
create index if not exists events_duplicate_of_idx on public.events (duplicate_of) where duplicate_of is not null;

alter table public.duplicate_candidates add column if not exists reasons text[];

create table if not exists public.event_duplicate_log (
  id uuid primary key default gen_random_uuid(),
  kept_id uuid not null references public.events(id) on delete cascade,
  dropped_id uuid not null references public.events(id) on delete cascade,
  score numeric not null,
  reasons text[] not null default '{}',
  filled_fields text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists event_duplicate_log_created_idx on public.event_duplicate_log (created_at desc);
alter table public.event_duplicate_log enable row level security;
drop policy if exists "Redaktion liest Dubletten-Protokoll" on public.event_duplicate_log;
create policy "Redaktion liest Dubletten-Protokoll" on public.event_duplicate_log
  for select to authenticated using (is_admin_or_editor());

-- 4. Bewertung -----------------------------------------------------------------

-- Aussagekräftige Titelwörter: ohne Umlaute/Akzente, ohne Füllwörter und ohne
-- Wörter aus dem Namen der Spielstätte ("Konzert im Wiener Konzerthaus" hat
-- dann keine – ein solcher Titel allein beweist nichts).
create or replace function public.event_dedupe_tokens(p_title text, p_venue_name text default null)
returns text[] language sql immutable as $$
  with norm as (
    select translate(lower(coalesce(p_title, '')),
             'àáâäãåèéêëìíîïòóôöõùúûüýçñœ', 'aaaaaaeeeeiiiiooooouuuuycno') t,
           translate(lower(coalesce(p_venue_name, '')),
             'àáâäãåèéêëìíîïòóôöõùúûüýçñœ', 'aaaaaaeeeeiiiiooooouuuuycno') v
  )
  select coalesce(array_agg(distinct w), '{}')
  from norm, regexp_split_to_table(norm.t, '[^a-z0-9]+') w
  where length(w) >= 4
    and w !~ '^[0-9]+$'
    and w <> all (regexp_split_to_array(norm.v, '[^a-z0-9]+'))
    and w not in (
      'konzert','konzerte','orchester','symphonieorchester','sinfonieorchester','rundfunks','rundfunkorchester',
      'bayerischen','bayerische','bayerisches','munchner','muenchner','munchen','muenchen','wiener','berliner',
      'philharmoniker','philharmonie','kammerorchester','staatsorchester','staatsoper','chor','werke','werken',
      'live','abend','sinfoniekonzert','symphoniekonzert','abonnementkonzert','akademiekonzert','saal','premiere',
      'wiederaufnahme','with','mit','und','dirigiert','dirigent','leitung','von','oper','ballett','konzertant',
      'musik','klassik','festival','reihe','zyklus','matinee','soiree','gala','sonntagskonzert','familienkonzert',
      'akte','akten','aufzugen','aufzuegen','drei','vier','zwei','fuenf','funf','in','the','and','des','der','die',
      'das','dem','den','eine','einer','einem','fur','fuer','zum','zur','studierende','studienkonzert')
$$;

-- Vergleichstitel ohne Hausnamen-Präfix und Satzzeichen (für Trigramm-
-- Ähnlichkeit): "Bayerische Staatsoper: La Bohème" -> "la boheme".
create or replace function public.event_dedupe_title(p_title text)
returns text language sql immutable as $$
  select trim(regexp_replace(regexp_replace(
    translate(lower(coalesce(p_title, '')), 'àáâäãåèéêëìíîïòóôöõùúûüýçñœ', 'aaaaaaeeeeiiiiooooouuuuycno'),
    '^(bayerische staatsoper|bayerisches staatsorchester|staatsoper|symphonieorchester des bayerischen rundfunks|brso|mko|munchner rundfunkorchester|chor des bayerischen rundfunks|munchner philharmoniker|mphil)\s*[:|–-]\s*', ''),
    '[^a-z0-9]+', ' ', 'g'))
$$;

-- Liefert alle Paare kommender Termine, die möglicherweise derselbe Termin
-- sind, mit Punktzahl, Begründung und Entscheidung ('auto' | 'review').
-- Wird von resolve_event_duplicates() und der Admin-Vorschau genutzt.
create or replace function public.event_duplicate_pairs(p_from timestamptz default now() - interval '1 day')
returns table (a_id uuid, b_id uuid, score numeric, reasons text[], action text)
language sql stable set search_path = public as $$
  with ev as (
    select e.id, e.title, e.source_id, e.venue_id, e.start_datetime, e.venue_detail,
           v.slot_exclusive,
           event_dedupe_tokens(e.title, v.name) tokens,
           event_dedupe_title(e.title) ctitle,
           regexp_replace(lower(e.title), '[^[:alnum:]]+', '', 'g') exact_title,
           (select array_agg(coalesce(ep.person_id, ep.ensemble_id)) from event_participants ep
             where ep.event_id = e.id and coalesce(ep.role::text, '') || coalesce(ep.role_label, '') !~* 'moderation|einführung|gast') cast_ids,
           (select array_agg(ew.work_id) from event_works ew where ew.event_id = e.id) work_ids
    from events e
    join venues v on v.id = e.venue_id
    where e.status in ('scheduled', 'sold_out', 'cancelled', 'postponed')
      and e.duplicate_of is null
      and e.start_datetime >= p_from
  ),
  pairs as (
    select a.id a_id, b.id b_id,
      a.source_id is not distinct from b.source_id same_source,
      abs(extract(epoch from b.start_datetime - a.start_datetime)) / 60 dmin,
      (select count(*) from unnest(a.tokens) t where t = any(b.tokens)) shared,
      least(cardinality(a.tokens), cardinality(b.tokens)) min_tokens,
      similarity(a.ctitle, b.ctitle) csim,
      (length(a.ctitle) >= 5 and length(b.ctitle) >= 5
        and (a.ctitle like '%' || b.ctitle || '%' or b.ctitle like '%' || a.ctitle || '%')) contained,
      a.exact_title = b.exact_title exact,
      coalesce(a.cast_ids && b.cast_ids, false) cast_overlap,
      coalesce(a.work_ids && b.work_ids, false) work_overlap,
      a.slot_exclusive,
      (a.venue_detail is null or b.venue_detail is null) one_room_unknown
    from ev a
    join ev b on b.venue_id = a.venue_id and a.id < b.id
     and abs(extract(epoch from b.start_datetime - a.start_datetime)) <= 3 * 3600
     and (a.start_datetime at time zone 'Europe/Berlin')::date = (b.start_datetime at time zone 'Europe/Berlin')::date
     -- Verschiedene, bekannte Räume sind nie derselbe Termin.
     and (a.venue_detail is null or b.venue_detail is null or lower(a.venue_detail) = lower(b.venue_detail))
  ),
  scored as (
    select p.*,
      array_remove(array[
        case when dmin <= 15 then 'gleiche Zeit' when dmin <= 180 then 'gleicher Tag, ' || round(dmin) || ' Min. versetzt' end,
        case when exact then 'identischer Titel' when contained then 'Titel enthält den anderen'
             when csim >= 0.5 then 'ähnlicher Titel (' || round(csim::numeric, 2) || ')' end,
        case when shared > 0 then shared || ' gemeinsame Titelwörter' end,
        case when cast_overlap then 'gemeinsame Mitwirkende' end,
        case when work_overlap then 'gemeinsame Werke' end,
        case when slot_exclusive then 'Bühne mit nur einer Vorstellung' end,
        case when same_source then 'gleiche Quelle' end
      ], null) reasons,
      case
        -- Gleiche Quelle: nur bei identischem Titel zur selben Zeit (die Quelle
        -- hat denselben Termin unter zwei Adressen geliefert).
        when same_source then case when dmin <= 15 and exact and min_tokens > 0 then 'auto' end
        when dmin <= 15 then case
          when shared >= 2 then 'auto'
          when shared >= 1 and (csim >= 0.3 or contained or cast_overlap or work_overlap) then 'auto'
          when min_tokens > 0 and (csim >= 0.5 or contained) then 'auto'
          when cast_overlap and work_overlap then 'auto'
          when slot_exclusive and one_room_unknown and (cast_overlap or work_overlap or csim >= 0.2) then 'auto'
          when cast_overlap or work_overlap then 'review'
          when slot_exclusive and one_room_unknown then 'review'
        end
        -- Gleicher Tag, andere Uhrzeit: nie automatisch (könnte eine zweite
        -- Vorstellung sein) – aber als mögliche Zeitänderung prüfen lassen.
        when (shared >= 2 or (min_tokens > 0 and (csim >= 0.75 or contained))) then 'review'
      end action,
      least(1.0,
        case when dmin <= 15 then 0.4 else 0.1 end
        + least(0.3, 0.12 * shared)
        + 0.2 * greatest(csim, case when contained then 0.8 else 0 end)
        + case when cast_overlap then 0.15 else 0 end
        + case when work_overlap then 0.15 else 0 end
        + case when slot_exclusive and dmin <= 15 then 0.1 else 0 end)::numeric(4, 3) score
    from pairs p
  )
  select a_id, b_id, score, reasons, action from scored where action is not null
$$;
revoke all on function public.event_duplicate_pairs(timestamptz) from public, anon;
grant execute on function public.event_duplicate_pairs(timestamptz) to authenticated;

-- 5. Auflösung -----------------------------------------------------------------

create or replace function public.resolve_event_duplicates()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r record;
  k events%rowtype;
  d events%rowtype;
  v_filled text[];
  v_merged int := 0;
  v_flagged int := 0;
  v_dropped uuid[] := '{}';
begin
  for r in
    select p.*,
      -- Behalten wird: höherer Quellen-Rang, dann mehr Programm/Besetzung,
      -- dann der ältere Eintrag.
      case when (source_priority(ea.source_id), ra.richness, eb.created_at, eb.id::text)
              >= (source_priority(eb.source_id), rb.richness, ea.created_at, ea.id::text)
           then p.a_id else p.b_id end keep_id
    from event_duplicate_pairs() p
    join events ea on ea.id = p.a_id
    join events eb on eb.id = p.b_id
    cross join lateral (select (select count(*) from event_works w where w.event_id = ea.id)
                             + (select count(*) from event_participants x where x.event_id = ea.id) richness) ra
    cross join lateral (select (select count(*) from event_works w where w.event_id = eb.id)
                             + (select count(*) from event_participants x where x.event_id = eb.id) richness) rb
    order by p.action, p.score desc
  loop
    if r.action = 'review' then
      if not exists (
        select 1 from duplicate_candidates c
        where (c.event_a_id, c.event_b_id) in ((r.a_id, r.b_id), (r.b_id, r.a_id))
      ) then
        insert into duplicate_candidates (event_a_id, event_b_id, similarity_score, status, reasons)
        values (r.a_id, r.b_id, r.score, 'pending', r.reasons);
        v_flagged := v_flagged + 1;
      end if;
      continue;
    end if;

    -- Ketten: ein schon ausgeblendeter Termin wird nicht nochmal verarbeitet.
    if r.a_id = any(v_dropped) or r.b_id = any(v_dropped) then continue; end if;
    -- Von der Redaktion als "keine Dublette" verworfen -> respektieren.
    if exists (
      select 1 from duplicate_candidates c
      where (c.event_a_id, c.event_b_id) in ((r.a_id, r.b_id), (r.b_id, r.a_id)) and c.status = 'dismissed'
    ) then continue; end if;

    select * into k from events where id = r.keep_id;
    select * into d from events where id = case when r.keep_id = r.a_id then r.b_id else r.a_id end;
    -- Redaktionell gesperrte Programme nicht anfassen; der gesperrte Termin
    -- bleibt in jedem Fall stehen.
    if d.program_locked_at is not null and k.program_locked_at is null then
      select * into k from events where id = d.id;
      select * into d from events where id = r.keep_id;
    end if;

    v_filled := '{}';
    if k.description_de is null and d.description_de is not null then v_filled := array_append(v_filled, 'description_de'); end if;
    if k.price_min is null and d.price_min is not null then v_filled := array_append(v_filled, 'price_min'); end if;
    if k.price_max is null and d.price_max is not null then v_filled := array_append(v_filled, 'price_max'); end if;
    if k.ticket_url is null and d.ticket_url is not null then v_filled := array_append(v_filled, 'ticket_url'); end if;
    if k.end_datetime is null and d.end_datetime is not null then v_filled := array_append(v_filled, 'end_datetime'); end if;
    if coalesce(cardinality(k.image_urls), 0) = 0 and coalesce(cardinality(d.image_urls), 0) > 0 then v_filled := array_append(v_filled, 'image_urls'); end if;
    if k.primary_image_id is null and d.primary_image_id is not null then v_filled := array_append(v_filled, 'primary_image_id'); end if;
    -- Titel komplett in Großbuchstaben ("UN BALLO IN MASCHERA") durch die
    -- normal geschriebene Variante der anderen Quelle ersetzen.
    if k.title = upper(k.title) and k.title <> lower(k.title) and d.title <> upper(d.title) then
      v_filled := array_append(v_filled, 'title');
    end if;

    update events set
      description_de = coalesce(k.description_de, d.description_de),
      price_min = coalesce(k.price_min, d.price_min),
      price_max = coalesce(k.price_max, d.price_max),
      ticket_url = coalesce(k.ticket_url, d.ticket_url),
      end_datetime = coalesce(k.end_datetime, d.end_datetime),
      image_urls = case when coalesce(cardinality(k.image_urls), 0) = 0 then d.image_urls else k.image_urls end,
      primary_image_id = coalesce(k.primary_image_id, d.primary_image_id),
      title = case when 'title' = any(v_filled) then d.title else k.title end,
      updated_at = now()
    where id = k.id;

    -- Programm und Besetzung nur übernehmen, wenn der behaltene Termin keine hat.
    if not exists (select 1 from event_works where event_id = k.id) and exists (select 1 from event_works where event_id = d.id) then
      insert into event_works (event_id, work_id, position, after_intermission)
      select k.id, work_id, position, after_intermission from event_works where event_id = d.id
      on conflict do nothing;
      v_filled := array_append(v_filled, 'event_works');
    end if;
    if not exists (select 1 from event_participants where event_id = k.id) and exists (select 1 from event_participants where event_id = d.id) then
      insert into event_participants (event_id, person_id, ensemble_id, role, role_label, display_order)
      select k.id, person_id, ensemble_id, role, role_label, display_order from event_participants where event_id = d.id
      on conflict do nothing;
      v_filled := array_append(v_filled, 'event_participants');
    end if;
    -- Favoriten/Merklisten wandern mit, damit niemand einen Termin verliert.
    update favorites f set event_id = k.id
     where f.event_id = d.id and not exists (select 1 from favorites g where g.event_id = k.id and g.user_id = f.user_id);

    update events set status = 'draft', review_status = 'rejected', duplicate_of = k.id, updated_at = now()
     where id = d.id;

    insert into event_duplicate_log (kept_id, dropped_id, score, reasons, filled_fields)
    values (k.id, d.id, r.score, r.reasons, v_filled);
    update duplicate_candidates set status = 'merged', reviewed_at = now()
     where status = 'pending' and (event_a_id, event_b_id) in ((k.id, d.id), (d.id, k.id));

    v_dropped := array_append(v_dropped, d.id);
    v_merged := v_merged + 1;
  end loop;

  return jsonb_build_object('merged', v_merged, 'flagged', v_flagged);
end;
$$;
revoke all on function public.resolve_event_duplicates() from public, anon, authenticated;

-- Admin: Zusammenführung rückgängig machen.
create or replace function public.admin_undo_event_duplicate(p_dropped_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'Nur für die Redaktion'; end if;
  update events set status = 'scheduled', review_status = 'published', duplicate_of = null, updated_at = now()
   where id = p_dropped_id and duplicate_of is not null;
  update duplicate_candidates set status = 'dismissed', reviewed_by = auth.uid(), reviewed_at = now()
   where event_a_id = p_dropped_id or event_b_id = p_dropped_id;
  insert into duplicate_candidates (event_a_id, event_b_id, similarity_score, status, reasons, reviewed_by, reviewed_at)
  select l.kept_id, l.dropped_id, l.score, array_append(l.reasons, 'von der Redaktion getrennt'), 'dismissed', auth.uid(), now()
  from event_duplicate_log l where l.dropped_id = p_dropped_id
  order by l.created_at desc limit 1;
end;
$$;
revoke all on function public.admin_undo_event_duplicate(uuid) from public, anon;
grant execute on function public.admin_undo_event_duplicate(uuid) to authenticated;

-- 2. Gesamtquelle Bayerische Staatsoper ----------------------------------------

insert into public.source_groups (slug, name, description)
values ('bayerische-staatsoper', 'Bayerische Staatsoper (Gesamtquelle)',
        'Offizieller Spielplan plus Concerti, in-muenchen und BayernCloud. Termine werden über alle Quellen abgeglichen; der offizielle Spielplan hat Vorrang, die anderen füllen Lücken.')
on conflict (slug) do update set name = excluded.name, description = excluded.description;

with g as (select id from source_groups where slug = 'bayerische-staatsoper'),
     m(name, prio) as (values
       ('Bayerische Staatsoper – offizieller Spielplan', 100),
       ('Bayerische Staatsoper via Concerti', 70),
       ('Cuvilliés-Theater via Concerti', 55),
       ('IN-Muenchen (nur Klassik)', 45),
       ('Concerti München', 40),
       ('BayernCloud Tourismus Events (API)', 30))
update public.sources s set group_id = g.id, priority = m.prio
from g, m where s.name = m.name;

-- Die Concerti-Seite der Staatsoper listet Nationaltheater, Cuvilliés,
-- Prinzregententheater und weitere Spielorte: Spielstätte je Termin erkennen
-- statt fest Nationaltheater, und wieder einlesen.
update public.sources
   set status = 'active', venue_id = null, consecutive_failures = 0,
       config = jsonb_set(config - 'httpCache', '{httpCache}', '{}'::jsonb)
 where name = 'Bayerische Staatsoper via Concerti';

-- Cron: ersetzt hide-cross-source-duplicates.
select cron.unschedule(jobid) from cron.job where jobname in ('hide-cross-source-duplicates', 'resolve-event-duplicates');
select cron.schedule('resolve-event-duplicates', '7,37 * * * *', $$ select public.resolve_event_duplicates(); $$);

select public.resolve_event_duplicates();
