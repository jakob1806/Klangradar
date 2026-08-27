-- Rekonstruiert aus supabase_migrations.schema_migrations.statements der
-- echten Produktions-DB (2026-08-27) -- eine andere Session hatte dies
-- direkt gegen Produktion gepusht, ohne die SQL-Datei je zu committen.
-- Diese Datei stellt nur die Git-Historie wieder her (exakter Wortlaut
-- der bereits angewendeten Statements); die tatsächliche Anwendung auf
-- Produktion ist bereits erfolgt, siehe migration-repair-Verfahren.

-- Die Multi-City-Migration 20261031000005 hatte versehentlich eine ältere
-- search_all-Version ohne Entity-Aliase, Werke und Organisatoren wieder
-- eingeführt. Dadurch fand die native Suche zwar BRSO-Veranstaltungen, aber
-- nicht das über den Alias "BRSO" verknüpfte Hauptensemble. Teilanfragen wie
-- "bayerische s" lieferten ebenfalls kaum sinnvoll priorisierte Entitäten.

create or replace function public.search_token_prefix_match(p_value text, p_query text)
returns boolean
language sql
immutable
parallel safe
as $$
  select case
    when nullif(public.normalize_entity_name(p_value), '') is null
      or nullif(public.normalize_entity_name(p_query), '') is null then false
    else not exists (
      select 1
      from regexp_split_to_table(public.normalize_entity_name(p_query), '\s+') query_token
      where not exists (
        select 1
        from regexp_split_to_table(public.normalize_entity_name(p_value), '\s+') value_token
        where value_token like query_token || '%'
      )
    )
  end;
$$;

create or replace function public.search_text_score(p_value text, p_query text)
returns real
language sql
immutable
parallel safe
as $$
  select case
    when nullif(public.normalize_entity_name(p_value), '') is null
      or nullif(public.normalize_entity_name(p_query), '') is null then 0::real
    when public.normalize_entity_name(p_value) = public.normalize_entity_name(p_query) then 1::real
    when public.normalize_entity_name(p_value) like public.normalize_entity_name(p_query) || '%' then 0.95::real
    when public.search_token_prefix_match(p_value, p_query)
      then greatest(0.72, similarity(p_value, p_query))::real
    else similarity(p_value, p_query)::real
  end;
$$;

revoke all on function public.search_token_prefix_match(text, text) from public;

revoke all on function public.search_text_score(text, text) from public;

grant execute on function public.search_token_prefix_match(text, text) to anon, authenticated, service_role;

grant execute on function public.search_text_score(text, text) to anon, authenticated, service_role;

drop function if exists public.search_all(text, int, uuid);

create function public.search_all(
  q text,
  result_limit int default 8,
  p_city_id uuid default public.munich_city_id()
)
returns table (
  result_type text,
  id uuid,
  slug text,
  title text,
  subtitle text,
  score real,
  photo_url text,
  start_datetime timestamptz,
  price_min numeric,
  is_free boolean
)
language sql
stable
as $$
  with pattern as (
    select '%' || trim(q) || '%' as substring, trim(q) as raw
  )
  (
    select distinct
      'event'::text,
      e.id,
      e.slug,
      e.title,
      v.name || ' · ' || to_char(e.start_datetime at time zone 'Europe/Berlin', 'DD.MM.YYYY'),
      greatest(
        public.search_text_score(e.title, pattern.raw),
        public.search_text_score(v.name, pattern.raw) * 0.82,
        public.search_text_score(o.name, pattern.raw) * 0.82,
        coalesce((
          select max(public.search_text_score(alias.alias, pattern.raw)) * 0.82
          from public.entity_aliases alias
          where alias.entity_type = 'venue' and alias.entity_id = v.id
        ), 0),
        coalesce((
          select max(public.search_text_score(alias.alias, pattern.raw)) * 0.82
          from public.entity_aliases alias
          where alias.entity_type = 'organizer' and alias.entity_id = o.id
        ), 0),
        coalesce((
          select max(greatest(
            public.search_text_score(w.title, pattern.raw),
            coalesce(public.search_text_score(alias.alias, pattern.raw), 0)
          )) * 0.82
          from public.event_works ew
          join public.works w on w.id = ew.work_id
          left join public.entity_aliases alias
            on alias.entity_type = 'work' and alias.entity_id = w.id
          where ew.event_id = e.id
        ), 0),
        coalesce((
          select max(greatest(
            public.search_text_score(composer.full_name, pattern.raw),
            coalesce(public.search_text_score(alias.alias, pattern.raw), 0)
          )) * 0.82
          from public.event_works ew
          join public.works w on w.id = ew.work_id
          join public.persons composer on composer.id = w.composer_id
          left join public.entity_aliases alias
            on alias.entity_type = 'person' and alias.entity_id = composer.id
          where ew.event_id = e.id
        ), 0),
        coalesce((
          select max(greatest(
            public.search_text_score(person.full_name, pattern.raw),
            public.search_text_score(ensemble.name, pattern.raw),
            coalesce(public.search_text_score(alias.alias, pattern.raw), 0)
          )) * 0.82
          from public.event_participants ep
          left join public.persons person on person.id = ep.person_id
          left join public.ensembles ensemble on ensemble.id = ep.ensemble_id
          left join public.entity_aliases alias
            on (alias.entity_type = 'person' and alias.entity_id = person.id)
            or (alias.entity_type = 'ensemble' and alias.entity_id = ensemble.id)
          where ep.event_id = e.id
        ), 0)
      )::real,
      coalesce(e.image_urls[1], v.photo_url),
      e.start_datetime,
      e.price_min,
      e.is_free
    from public.events e
    join public.venues v on v.id = e.venue_id
    left join public.organizers o on o.id = e.organizer_id
    cross join pattern
    where e.status = 'scheduled'
      and e.start_datetime >= now()
      and (p_city_id is null or e.city_id = p_city_id)
      and (
        e.title ilike pattern.substring
        or e.subtitle ilike pattern.substring
        or public.search_token_prefix_match(e.title, pattern.raw)
        or public.search_token_prefix_match(e.subtitle, pattern.raw)
        or public.search_token_prefix_match(v.name, pattern.raw)
        or public.search_token_prefix_match(o.name, pattern.raw)
        or exists (
          select 1 from public.entity_aliases alias
          where alias.entity_type = 'venue' and alias.entity_id = v.id
            and (alias.alias ilike pattern.substring or public.search_token_prefix_match(alias.alias, pattern.raw))
        )
        or exists (
          select 1 from public.entity_aliases alias
          where alias.entity_type = 'organizer' and alias.entity_id = o.id
            and (alias.alias ilike pattern.substring or public.search_token_prefix_match(alias.alias, pattern.raw))
        )
        or exists (
          select 1
          from public.event_works ew
          join public.works w on w.id = ew.work_id
          left join public.entity_aliases alias on alias.entity_type = 'work' and alias.entity_id = w.id
          where ew.event_id = e.id and (
            w.title ilike pattern.substring
            or alias.alias ilike pattern.substring
            or public.search_token_prefix_match(w.title, pattern.raw)
            or public.search_token_prefix_match(alias.alias, pattern.raw)
          )
        )
        or exists (
          select 1
          from public.event_works ew
          join public.works w on w.id = ew.work_id
          join public.persons composer on composer.id = w.composer_id
          left join public.entity_aliases alias on alias.entity_type = 'person' and alias.entity_id = composer.id
          where ew.event_id = e.id and (
            composer.full_name ilike pattern.substring
            or alias.alias ilike pattern.substring
            or public.search_token_prefix_match(composer.full_name, pattern.raw)
            or public.search_token_prefix_match(alias.alias, pattern.raw)
          )
        )
        or exists (
          select 1
          from public.event_participants ep
          left join public.persons person on person.id = ep.person_id
          left join public.ensembles ensemble on ensemble.id = ep.ensemble_id
          left join public.entity_aliases alias
            on (alias.entity_type = 'person' and alias.entity_id = person.id)
            or (alias.entity_type = 'ensemble' and alias.entity_id = ensemble.id)
          where ep.event_id = e.id and (
            person.full_name ilike pattern.substring
            or ensemble.name ilike pattern.substring
            or alias.alias ilike pattern.substring
            or public.search_token_prefix_match(person.full_name, pattern.raw)
            or public.search_token_prefix_match(ensemble.name, pattern.raw)
            or public.search_token_prefix_match(alias.alias, pattern.raw)
          )
        )
      )
    order by 6 desc, e.start_datetime
    limit result_limit
  )
  union all
  (
    select 'person', p.id, p.slug, p.full_name, array_to_string(p.roles::text[], ', '),
      greatest(
        public.search_text_score(p.full_name, pattern.raw),
        coalesce((select max(public.search_text_score(alias.alias, pattern.raw)) from public.entity_aliases alias where alias.entity_type = 'person' and alias.entity_id = p.id), 0)
      )::real,
      p.photo_url, null::timestamptz, null::numeric, null::boolean
    from public.persons p cross join pattern
    where p.full_name ilike pattern.substring
      or public.search_token_prefix_match(p.full_name, pattern.raw)
      or exists (
        select 1 from public.entity_aliases alias
        where alias.entity_type = 'person' and alias.entity_id = p.id
          and (alias.alias ilike pattern.substring or public.search_token_prefix_match(alias.alias, pattern.raw))
      )
    order by 6 desc limit result_limit
  )
  union all
  (
    select 'ensemble', ensemble.id, ensemble.slug, ensemble.name, ensemble.type::text,
      greatest(
        public.search_text_score(ensemble.name, pattern.raw),
        coalesce((select max(public.search_text_score(alias.alias, pattern.raw)) from public.entity_aliases alias where alias.entity_type = 'ensemble' and alias.entity_id = ensemble.id), 0)
      )::real,
      ensemble.photo_url, null::timestamptz, null::numeric, null::boolean
    from public.ensembles ensemble cross join pattern
    where not ensemble.is_resolution_placeholder
      and not ensemble.is_family_root
      and (
        ensemble.name ilike pattern.substring
        or public.search_token_prefix_match(ensemble.name, pattern.raw)
        or exists (
          select 1 from public.entity_aliases alias
          where alias.entity_type = 'ensemble' and alias.entity_id = ensemble.id
            and (alias.alias ilike pattern.substring or public.search_token_prefix_match(alias.alias, pattern.raw))
        )
      )
    order by 6 desc limit result_limit
  )
  union all
  (
    select 'venue', venue.id, venue.slug, venue.name, venue.address_city,
      greatest(
        public.search_text_score(venue.name, pattern.raw),
        coalesce((select max(public.search_text_score(alias.alias, pattern.raw)) from public.entity_aliases alias where alias.entity_type = 'venue' and alias.entity_id = venue.id), 0)
      )::real,
      venue.photo_url, null::timestamptz, null::numeric, null::boolean
    from public.venues venue cross join pattern
    where (p_city_id is null or venue.city_id = p_city_id)
      and (
        venue.name ilike pattern.substring
        or public.search_token_prefix_match(venue.name, pattern.raw)
        or exists (
          select 1 from public.entity_aliases alias
          where alias.entity_type = 'venue' and alias.entity_id = venue.id
            and (alias.alias ilike pattern.substring or public.search_token_prefix_match(alias.alias, pattern.raw))
        )
      )
    order by 6 desc limit result_limit
  )
  union all
  (
    select 'work', work.id, null::text, work.title, composer.full_name,
      greatest(
        public.search_text_score(work.title, pattern.raw),
        coalesce((select max(public.search_text_score(alias.alias, pattern.raw)) from public.entity_aliases alias where alias.entity_type = 'work' and alias.entity_id = work.id), 0)
      )::real,
      null::text, null::timestamptz, null::numeric, null::boolean
    from public.works work
    left join public.persons composer on composer.id = work.composer_id
    cross join pattern
    where work.title ilike pattern.substring
      or public.search_token_prefix_match(work.title, pattern.raw)
      or exists (
        select 1 from public.entity_aliases alias
        where alias.entity_type = 'work' and alias.entity_id = work.id
          and (alias.alias ilike pattern.substring or public.search_token_prefix_match(alias.alias, pattern.raw))
      )
    order by 6 desc limit result_limit
  )
  order by 6 desc;
$$;

grant execute on function public.search_all(text, int, uuid) to anon, authenticated;

comment on function public.search_all(text, int, uuid) is
  'Stadtbezogene globale Suche mit Aliasauflösung, Token-Präfixen und priorisierten direkten Entitätstreffern.';
