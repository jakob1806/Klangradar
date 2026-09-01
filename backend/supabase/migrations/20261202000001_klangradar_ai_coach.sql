-- Klangradar AI Coach: WHOOP-Coach-Prinzip für Kulturentscheidungen.
-- Keine erfundenen "Gesundheits-Scores": Passung, Kulturrhythmus und
-- Entdeckung werden aus transparenten Nutzeraktionen plus Check-ins gebildet.

create table if not exists coach_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null default 'Klangradar Coach',
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists coach_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references coach_conversations(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  content text not null,
  intent text,
  evidence jsonb not null default '[]'::jsonb,
  actions jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

-- "My Memory": einzelne, sicht- und löschbare Fakten statt einer
-- undurchsichtigen Prompt-Textwand. Coach darf nur bestätigte Fakten nutzen.
create table if not exists coach_memory_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  category text not null check (category in ('taste','budget','schedule','travel','accessibility','social','avoid','goal','other')),
  label text not null,
  value jsonb not null,
  source text not null default 'user_confirmed' check (source in ('user_confirmed','profile','behavior')),
  confidence numeric not null default 1 check (confidence between 0 and 1),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists coach_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null check (kind in ('concert_frequency','discover_genres','budget','follow_artist','custom')),
  title text not null,
  target_value numeric,
  period text check (period is null or period in ('week','month','quarter','year')),
  metadata jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Schneller situativer Kontext wie WHOOPs Tageszustand, aber bewusst
-- subjektiv und vom Nutzer angegeben: Stimmung, Energie, Zeit, Budget.
create table if not exists coach_checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  mood text check (mood is null or mood in ('calm','curious','romantic','social','focused','adventurous','emotional')),
  energy smallint check (energy between 1 and 5),
  available_minutes int check (available_minutes between 15 and 1440),
  budget numeric check (budget >= 0),
  companion text check (companion is null or companion in ('alone','partner','friends','family','children')),
  note text,
  created_at timestamptz not null default now()
);

-- Besuchsreflexionen ermöglichen echte Trends. Aussagen bleiben
-- Korrelationen und werden erst ab ausreichender Stichprobe ausgegeben.
create table if not exists coach_event_reflections (
  user_id uuid not null references profiles(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  rating smallint check (rating between 1 and 5),
  energy_before smallint check (energy_before between 1 and 5),
  energy_after smallint check (energy_after between 1 and 5),
  companion text check (companion is null or companion in ('alone','partner','friends','family','children')),
  tags text[] not null default '{}',
  note text,
  attended_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id,event_id)
);

create table if not exists coach_insights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null check (kind in ('planning','ticket','goal','reflection','trend','discovery')),
  fingerprint text not null,
  title text not null,
  body text not null,
  evidence jsonb not null default '[]'::jsonb,
  actions jsonb not null default '[]'::jsonb,
  priority smallint not null default 0 check (priority between 0 and 3),
  valid_until timestamptz,
  read_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id,fingerprint)
);

create index if not exists coach_messages_conversation_idx on coach_messages(conversation_id,created_at);
create index if not exists coach_checkins_user_idx on coach_checkins(user_id,created_at desc);
create index if not exists coach_reflections_user_idx on coach_event_reflections(user_id,created_at desc);
create index if not exists coach_insights_user_idx on coach_insights(user_id,priority desc,created_at desc);

alter table coach_conversations enable row level security;
alter table coach_messages enable row level security;
alter table coach_memory_items enable row level security;
alter table coach_goals enable row level security;
alter table coach_checkins enable row level security;
alter table coach_event_reflections enable row level security;
alter table coach_insights enable row level security;

create policy "Eigene Coach-Konversationen" on coach_conversations for all
  using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "Eigene Coach-Nachrichten lesen" on coach_messages for select using(exists(
  select 1 from coach_conversations c where c.id=conversation_id and c.user_id=auth.uid()));
create policy "Eigene Coach-Nachrichten anlegen" on coach_messages for insert with check(exists(
  select 1 from coach_conversations c where c.id=conversation_id and c.user_id=auth.uid()));
create policy "Eigene Coach-Erinnerungen" on coach_memory_items for all
  using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "Eigene Coach-Ziele" on coach_goals for all
  using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "Eigene Coach-Checkins" on coach_checkins for all
  using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "Eigene Konzertreflexionen" on coach_event_reflections for all
  using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "Eigene Coach-Insights" on coach_insights for all
  using(user_id=auth.uid()) with check(user_id=auth.uid());

-- Eine konsolidierte, kleine Kontextschicht: Das Sprachmodell erhält keine
-- unbeschränkten Tabellenzugriffe, sondern nur diese belegbaren Fakten.
create or replace function coach_context_snapshot()
returns jsonb language sql stable security invoker as $$
with signal_counts as (
  select
    (select count(*) from profile_interest_genres where user_id=auth.uid()) genre_interests,
    (select count(*) from user_favorite_persons where user_id=auth.uid()) followed_persons,
    (select count(*) from user_favorite_ensembles where user_id=auth.uid()) followed_ensembles,
    (select count(*) from user_favorite_venues where user_id=auth.uid()) followed_venues,
    (select count(*) from user_favorite_works where user_id=auth.uid()) followed_works,
    (select count(*) from event_views where user_id=auth.uid() and viewed_at>=now()-interval '90 days') recent_views,
    (select count(*) from ticket_clicks where user_id=auth.uid() and clicked_at>=now()-interval '90 days') recent_ticket_clicks,
    (select count(*) from calendar_adds where user_id=auth.uid() and added_at>=now()-interval '90 days') recent_calendar_adds,
    (select count(*) from favorites where user_id=auth.uid()) saved_events,
    (select count(*) from favorites f join events e on e.id=f.event_id where f.user_id=auth.uid() and f.status='attending' and e.start_datetime>=now()) planned_events,
    (select count(*) from coach_event_reflections where user_id=auth.uid()) reflected_events
), top_genres as (
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',label_de,'signals',signals) order by signals desc),'[]'::jsonb) value
  from (select g.id,g.label_de,count(*) signals from (
    select f.event_id from favorites f where f.user_id=auth.uid()
    union all select ev.event_id from event_views ev where ev.user_id=auth.uid() and ev.viewed_at>=now()-interval '90 days'
    union all select tc.event_id from ticket_clicks tc where tc.user_id=auth.uid() and tc.clicked_at>=now()-interval '180 days'
  ) s join event_genres eg on eg.event_id=s.event_id join genres g on g.id=eg.genre_id
  group by g.id,g.label_de order by signals desc limit 5) ranked
), latest_checkin as (
  select to_jsonb(c) value from coach_checkins c where c.user_id=auth.uid() order by created_at desc limit 1
), upcoming as (
  select coalesce(jsonb_agg(to_jsonb(x) order by x.start_datetime),'[]'::jsonb) value from (
    select e.id,e.slug,e.title,e.start_datetime,e.price_min,e.remaining_tickets_status,v.name venue_name
    from favorites f join events e on e.id=f.event_id left join venues v on v.id=e.venue_id
    where f.user_id=auth.uid() and e.start_datetime>=now() order by e.start_datetime limit 8
  ) x
), memory as (
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'category',category,'label',label,'value',value,'confidence',confidence)),'[]'::jsonb) value
  from coach_memory_items where user_id=auth.uid() and confirmed_at is not null
), goals as (
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'target',target_value,'period',period,'metadata',metadata)),'[]'::jsonb) value
  from coach_goals where user_id=auth.uid() and active
)
select jsonb_build_object(
  'signals',to_jsonb(signal_counts),
  'signal_quality',case when recent_views+recent_ticket_clicks+saved_events>=20 then 'high' when recent_views+recent_ticket_clicks+saved_events>=6 then 'medium' else 'low' end,
  'coach_lenses',jsonb_build_object(
    'fit',jsonb_build_object('known_preferences',genre_interests+followed_persons+followed_ensembles+followed_venues+followed_works,'recent_intent_signals',recent_ticket_clicks+recent_calendar_adds),
    'rhythm',jsonb_build_object('planned',planned_events,'reflected_visits',reflected_events,'saved',saved_events),
    'discovery',jsonb_build_object('top_genres',top_genres.value,'recent_views',recent_views)
  ),
  'latest_checkin',coalesce(latest_checkin.value,'null'::jsonb),
  'upcoming_saved_events',upcoming.value,'memory',memory.value,'goals',goals.value
) from signal_counts cross join top_genres left join latest_checkin on true cross join upcoming cross join memory cross join goals;
$$;

-- Echte Kandidaten; das LLM darf nur Filter formulieren, nie Events erfinden.
create or replace function coach_search_events(p_filters jsonb default '{}'::jsonb,p_limit int default 8)
returns jsonb language sql stable security invoker as $$
with candidates as (
  select e.id,e.slug,e.title,e.subtitle,e.start_datetime,e.duration_minutes,e.price_min,e.price_max,e.price_currency,e.is_free,
    e.remaining_tickets_status,e.ticket_url,e.website_url,v.id venue_id,v.name venue_name,v.address_city,
    array_remove(array[
      case when e.is_free then 'Eintritt frei' end,
      case when exists(select 1 from user_favorite_venues f where f.user_id=auth.uid() and f.venue_id=e.venue_id) then 'Du folgst diesem Ort' end,
      case when exists(select 1 from event_genres eg join profile_interest_genres i using(genre_id) where eg.event_id=e.id and i.user_id=auth.uid()) then 'Passt zu deinen Interessen' end,
      case when exists(select 1 from event_participants ep join user_favorite_persons f using(person_id) where ep.event_id=e.id and f.user_id=auth.uid()) then 'Mit einer Person, der du folgst' end,
      case when exists(select 1 from event_participants ep join user_favorite_ensembles f using(ensemble_id) where ep.event_id=e.id and f.user_id=auth.uid()) then 'Mit einem Ensemble, dem du folgst' end,
      case when not exists(select 1 from favorites f join events old on old.id=f.event_id where f.user_id=auth.uid() and exists(select 1 from event_genres a join event_genres b using(genre_id) where a.event_id=e.id and b.event_id=old.id)) then 'Eine neue Richtung für dich' end
    ],null) reasons
  from events e join venues v on v.id=e.venue_id
  where e.status='scheduled'
    and e.start_datetime>=coalesce((p_filters->>'date_from')::timestamptz,now())
    and e.start_datetime<coalesce((p_filters->>'date_to')::timestamptz,now()+interval '90 days')
    and (p_filters->>'max_budget' is null or e.is_free or e.price_min is null or e.price_min<=(p_filters->>'max_budget')::numeric)
    and (p_filters->>'city' is null or v.address_city ilike '%'||(p_filters->>'city')||'%')
    and (coalesce((p_filters->>'exclude_opera')::boolean,false)=false or coalesce(e.category,'')<>'opera')
    and (p_filters->>'query' is null or e.title ilike '%'||(p_filters->>'query')||'%' or coalesce(e.subtitle,'') ilike '%'||(p_filters->>'query')||'%' or exists(
      select 1 from event_genres eg join genres g on g.id=eg.genre_id where eg.event_id=e.id and (g.label_de ilike '%'||(p_filters->>'query')||'%' or g.slug ilike '%'||(p_filters->>'query')||'%')))
)
select coalesce(jsonb_agg(to_jsonb(x) order by x.personal_score desc,x.start_datetime),'[]'::jsonb)
from (select c.*,cardinality(reasons) personal_score from candidates c order by personal_score desc,start_datetime limit greatest(1,least(p_limit,20))) x;
$$;

-- Verhaltenstrends erst ab 3 Beobachtungen; Formulierung liefert Differenz
-- und Stichprobe, die UI/LLM muss sie als Zusammenhang, nicht Ursache nennen.
create or replace function coach_behavior_trends()
returns jsonb language sql stable security invoker as $$
select coalesce(jsonb_agg(to_jsonb(t) order by sample_size desc),'[]'::jsonb) from (
  select 'companion' dimension,coalesce(companion,'unknown') value,count(*) sample_size,
    round(avg(rating)::numeric,2) avg_rating,
    round(avg(energy_after-energy_before)::numeric,2) avg_energy_change
  from coach_event_reflections where user_id=auth.uid() and rating is not null
  group by companion having count(*)>=3
  union all
  select 'tag',tag,count(*),round(avg(rating)::numeric,2),round(avg(energy_after-energy_before)::numeric,2)
  from coach_event_reflections r cross join lateral unnest(r.tags) tag
  where user_id=auth.uid() and rating is not null group by tag having count(*)>=3
) t;
$$;

grant execute on function coach_context_snapshot() to authenticated;
grant execute on function coach_search_events(jsonb,int) to authenticated;
grant execute on function coach_behavior_trends() to authenticated;
notify pgrst,'reload schema';
