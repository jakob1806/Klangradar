-- Erstellt von Claude Code (07.11.2026): Termine ohne Genre (z. B.
-- „DIE ZAUBERFLÖTE“ am 22.11., während der 20.11. „Oper“ hat) erben die
-- Genres anderer Termine derselben Produktion: gleicher Titel, gleiche
-- Spielstätte. Danach zeigt die Konzertseite wieder „Oper“ usw.
create or replace function public.inherit_sibling_genres()
returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  insert into event_genres (event_id, genre_id)
  select distinct e.id, eg.genre_id
  from events e
  join events s on s.id <> e.id
    and s.venue_id = e.venue_id
    and lower(trim(s.title)) = lower(trim(e.title))
  join event_genres eg on eg.event_id = s.id
  where e.start_datetime >= now() - interval '1 day'
    and e.venue_id is not null
    and not exists (select 1 from event_genres x where x.event_id = e.id)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end; $$;

revoke all on function public.inherit_sibling_genres() from public, anon, authenticated;

select public.inherit_sibling_genres();

-- Täglich nachziehen (neu importierte Termine).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('inherit-sibling-genres') where exists (select 1 from cron.job where jobname = 'inherit-sibling-genres');
    perform cron.schedule('inherit-sibling-genres', '17 4 * * *', 'select public.inherit_sibling_genres()');
  end if;
end $$;
