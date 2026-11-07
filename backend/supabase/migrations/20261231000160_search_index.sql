-- Suche v2 (Nutzerfeedback 07.11.2026: keine Treffer, zu langsam, Groß-
-- schreibung wie "ZAUBERFLÖTE" nicht erkannt, Reihenfolge unlogisch).
--
-- Bisher durchsuchte search_all() bei jedem Tastendruck alle kommenden
-- Termine samt Werken, Komponisten, Mitwirkenden und Aliasen mit
-- korrelierten Unterabfragen. Jetzt:
--  * search_index: ein vorberechneter, normalisierter Suchtext pro Termin,
--    Person, Ensemble, Spielstätte und Werk (alle 10 Minuten neu gebaut).
--  * search_norm(): Kleinschreibung, Umlaute/Akzente auch in Großbuchstaben
--    (Ö -> o, ß -> ss), Satzzeichen weg – unabhängig von der DB-Collation.
--  * Treffer: jedes Suchwort als Wortanfang im Suchtext; sonst Trigramm-
--    Ähnlichkeit (Tippfehler wie "Zauberflöe", "Mahlr").
--  * Rang: exakter Titel > Titel beginnt mit > alle Wörter im Titel > nur in
--    Werken/Mitwirkenden; Personen/Ensembles zusätzlich nach Bekanntheit,
--    Termine bei gleichem Rang nach Datum.

create extension if not exists pg_trgm;

create or replace function public.search_norm(p text)
returns text language sql immutable parallel safe as $$
  select trim(regexp_replace(
    translate(
      lower(replace(replace(coalesce(p, ''), 'ß', 'ss'), 'ẞ', 'ss')),
      'ÄÖÜÀÁÂÃÅÈÉÊËÌÍÎÏÒÓÔÕÙÚÛÝÇÑŒäöüàáâãåèéêëìíîïòóôõùúûýçñœ',
      'aouaaaaaeeeeiiiioooouuuycnoaouaaaaaeeeeiiiioooouuuycno'),
    '[^a-z0-9]+', ' ', 'g'))
$$;

create table if not exists public.search_index (
  kind text not null,
  id uuid not null,
  slug text,
  title text not null,
  subtitle text,
  photo_url text,
  start_datetime timestamptz,
  price_min numeric,
  is_free boolean,
  city_id uuid,
  norm_title text not null,
  norm_all text not null,
  popularity real not null default 0,
  primary key (kind, id)
);
create index if not exists search_index_norm_all_trgm on public.search_index using gin (norm_all gin_trgm_ops);
create index if not exists search_index_norm_title_trgm on public.search_index using gin (norm_title gin_trgm_ops);
alter table public.search_index enable row level security;
-- Nur über search_all() (security definer) lesbar.

create or replace function public.refresh_search_index()
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  drop table if exists si_new;
  create temp table si_new (like public.search_index) on commit drop;

  insert into si_new
  select 'event', e.id, e.slug, e.title,
         v.name || ' · ' || to_char(e.start_datetime at time zone 'Europe/Berlin', 'DD.MM.YYYY'),
         coalesce(e.image_urls[1], v.photo_url), e.start_datetime, e.price_min, e.is_free, e.city_id,
         search_norm(e.title),
         search_norm(concat_ws(' ', e.title, e.subtitle, v.name, o.name,
           (select string_agg(a.alias, ' ') from entity_aliases a where a.entity_type = 'venue' and a.entity_id = v.id),
           (select string_agg(concat_ws(' ', w.title, c.full_name), ' ')
              from event_works ew join works w on w.id = ew.work_id left join persons c on c.id = w.composer_id
             where ew.event_id = e.id),
           (select string_agg(coalesce(p.full_name, en.name), ' ')
              from event_participants ep left join persons p on p.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
             where ep.event_id = e.id))),
         0
  from events e
  join venues v on v.id = e.venue_id
  left join organizers o on o.id = e.organizer_id
  where e.status in ('scheduled', 'sold_out')
    and e.duplicate_of is null
    and e.start_datetime >= now() - interval '3 hours';

  insert into si_new
  select 'person', p.id, p.slug, p.full_name, array_to_string(p.roles::text[], ', '), p.photo_url,
         null, null, null, null,
         search_norm(p.full_name),
         search_norm(concat_ws(' ', p.full_name,
           (select string_agg(a.alias, ' ') from entity_aliases a where a.entity_type = 'person' and a.entity_id = p.id))),
         coalesce((select ep.score + coalesce(ep.boost, 0) from entity_prominence ep where ep.kind = 'person' and ep.entity_id = p.id), 0)
  from persons p where p.full_name is not null;

  insert into si_new
  select 'ensemble', en.id, en.slug, en.name, en.type::text, en.photo_url,
         null, null, null, null,
         search_norm(en.name),
         search_norm(concat_ws(' ', en.name,
           (select string_agg(a.alias, ' ') from entity_aliases a where a.entity_type = 'ensemble' and a.entity_id = en.id))),
         coalesce((select ep.score + coalesce(ep.boost, 0) from entity_prominence ep where ep.kind = 'ensemble' and ep.entity_id = en.id), 0)
  from ensembles en
  where en.name is not null and not coalesce(en.is_resolution_placeholder, false) and not coalesce(en.is_family_root, false);

  insert into si_new
  select 'venue', v.id, v.slug, v.name, v.address_city, v.photo_url,
         null, null, null, v.city_id,
         search_norm(v.name),
         search_norm(concat_ws(' ', v.name, v.address_city,
           (select string_agg(a.alias, ' ') from entity_aliases a where a.entity_type = 'venue' and a.entity_id = v.id))),
         coalesce((select ep.score + coalesce(ep.boost, 0) from entity_prominence ep where ep.kind = 'venue' and ep.entity_id = v.id), 0)
  from venues v where v.name is not null;

  insert into si_new
  select 'work', w.id, null, w.title, c.full_name, null,
         null, null, null, null,
         search_norm(w.title),
         search_norm(concat_ws(' ', w.title, c.full_name)),
         0
  from works w left join persons c on c.id = w.composer_id
  where w.title is not null;

  delete from public.search_index;
  insert into public.search_index select * from si_new;
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke all on function public.refresh_search_index() from public, anon, authenticated;

drop function if exists public.search_all(text, int, uuid);
create function public.search_all(
  q text,
  result_limit int default 8,
  p_city_id uuid default public.munich_city_id()
)
returns table (
  result_type text, id uuid, slug text, title text, subtitle text, score real,
  photo_url text, start_datetime timestamptz, price_min numeric, is_free boolean
)
language sql stable security definer set search_path = public as $$
  with query as (
    select search_norm(q) nq,
           array_remove(regexp_split_to_array(search_norm(q), ' '), '') toks
  ),
  candidates as (
    select s.*, query.nq, query.toks,
      -- jedes Suchwort als Wortanfang im gesamten Suchtext
      not exists (select 1 from unnest(query.toks) t where position(' ' || t in ' ' || s.norm_all) = 0) all_words,
      not exists (select 1 from unnest(query.toks) t where position(' ' || t in ' ' || s.norm_title) = 0) title_words,
      word_similarity(query.nq, s.norm_title) wsim_title,
      word_similarity(query.nq, s.norm_all) wsim_all
    from search_index s, query
    where length(query.nq) >= 2
      and (s.city_id is null or p_city_id is null or s.city_id = p_city_id or s.kind <> 'event')
      and (s.kind <> 'venue' or p_city_id is null or s.city_id is null or s.city_id = p_city_id)
      and (s.norm_all like '%' || query.toks[1] || '%' or query.nq <% s.norm_all)
  ),
  scored as (
    select c.*,
      (case
        when c.norm_title = c.nq then 1.0
        when c.norm_title like c.nq || '%' then 0.92
        when c.title_words then 0.84
        when c.all_words then 0.62
        else 0.35 * greatest(c.wsim_title, c.wsim_all * 0.8)
      end
      + case when c.kind in ('person', 'ensemble', 'venue') then least(c.popularity, 7) * 0.012 else 0 end
      + case when c.kind = 'event' and c.title_words then 0.03 else 0 end
      )::real sc
    from candidates c
    where c.all_words or greatest(c.wsim_title, c.wsim_all) >= 0.45
  ),
  ranked as (
    select s.*, row_number() over (partition by s.kind order by s.sc desc, s.start_datetime nulls last, s.title) rn
    from scored s
  )
  select r.kind, r.id, r.slug, r.title, r.subtitle, r.sc, r.photo_url, r.start_datetime, r.price_min, r.is_free
  from ranked r
  where r.rn <= greatest(result_limit, 1)
  order by r.sc desc, r.start_datetime nulls last, r.title
$$;
grant execute on function public.search_all(text, int, uuid) to anon, authenticated;

select public.refresh_search_index();

select cron.unschedule('refresh-search-index') where exists (select 1 from cron.job where jobname = 'refresh-search-index');
select cron.schedule('refresh-search-index', '4-59/10 * * * *', $$ select public.refresh_search_index(); $$);
