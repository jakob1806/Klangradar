-- Erstellt von Claude Code (14.11.2026): Social-Media-Recherche zusätzlich
-- über die eigene Website (research-social-links, zweiter Durchgang) und
-- etwas häufiger (stündlich statt alle 2 Stunden).
alter table public.persons add column if not exists social_links_web_checked_at timestamptz;
alter table public.ensembles add column if not exists social_links_web_checked_at timestamptz;
alter table public.venues add column if not exists social_links_web_checked_at timestamptz;

-- Offensichtlich kaputte Einträge (kein http-Link) entfernen, damit die
-- Recherche die Plattform neu befüllen kann.
update persons set social_links = (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(social_links) x(k, v) where jsonb_typeof(v) = 'string' and v #>> '{}' ~* '^https?://')
where social_links is not null and social_links <> '{}' and exists (select 1 from jsonb_each(social_links) x(k, v) where jsonb_typeof(v) <> 'string' or v #>> '{}' !~* '^https?://');
update ensembles set social_links = (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(social_links) x(k, v) where jsonb_typeof(v) = 'string' and v #>> '{}' ~* '^https?://')
where social_links is not null and social_links <> '{}' and exists (select 1 from jsonb_each(social_links) x(k, v) where jsonb_typeof(v) <> 'string' or v #>> '{}' !~* '^https?://');
update venues set social_links = (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(social_links) x(k, v) where jsonb_typeof(v) = 'string' and v #>> '{}' ~* '^https?://')
where social_links is not null and social_links <> '{}' and exists (select 1 from jsonb_each(social_links) x(k, v) where jsonb_typeof(v) <> 'string' or v #>> '{}' !~* '^https?://');

do $$
declare j bigint;
begin
  select jobid into j from cron.job where jobname = 'social-links-research';
  if j is not null then perform cron.alter_job(j, schedule := '11 * * * *'); end if;
end $$;
