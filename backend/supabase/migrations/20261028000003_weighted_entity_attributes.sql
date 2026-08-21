-- Einheitliche, gewichtete Taxonomie für Events, Werke, Personen und Ensembles.
-- Direkte Zuordnungen sind redaktionell/automatisch pflegbar; Events erben
-- beim Abruf zusätzlich Attribute ihrer Werke und Mitwirkenden.

create table attributes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9_]+$'),
  label_de text not null,
  description_de text,
  group_key text not null default 'thema',
  inspiration_title text,
  inspiration_enabled boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table event_attributes (
  event_id uuid not null references events(id) on delete cascade,
  attribute_id uuid not null references attributes(id) on delete cascade,
  weight numeric(3,2) not null check (weight > 0 and weight <= 1),
  source text not null default 'editorial' check (source in ('editorial','import','heuristic','inherited','ai')),
  primary key (event_id, attribute_id)
);
create table work_attributes (
  work_id uuid not null references works(id) on delete cascade,
  attribute_id uuid not null references attributes(id) on delete cascade,
  weight numeric(3,2) not null check (weight > 0 and weight <= 1),
  source text not null default 'editorial' check (source in ('editorial','import','heuristic','ai')),
  primary key (work_id, attribute_id)
);
create table person_attributes (
  person_id uuid not null references persons(id) on delete cascade,
  attribute_id uuid not null references attributes(id) on delete cascade,
  weight numeric(3,2) not null check (weight > 0 and weight <= 1),
  source text not null default 'editorial' check (source in ('editorial','import','heuristic','ai')),
  primary key (person_id, attribute_id)
);
create table ensemble_attributes (
  ensemble_id uuid not null references ensembles(id) on delete cascade,
  attribute_id uuid not null references attributes(id) on delete cascade,
  weight numeric(3,2) not null check (weight > 0 and weight <= 1),
  source text not null default 'editorial' check (source in ('editorial','import','heuristic','ai')),
  primary key (ensemble_id, attribute_id)
);

create index event_attributes_attribute_idx on event_attributes(attribute_id, weight desc);
create index work_attributes_attribute_idx on work_attributes(attribute_id, weight desc);
create index person_attributes_attribute_idx on person_attributes(attribute_id, weight desc);
create index ensemble_attributes_attribute_idx on ensemble_attributes(attribute_id, weight desc);

alter table attributes enable row level security;
alter table event_attributes enable row level security;
alter table work_attributes enable row level security;
alter table person_attributes enable row level security;
alter table ensemble_attributes enable row level security;
create policy "Attribute öffentlich lesbar" on attributes for select using (true);
create policy "Event-Attribute öffentlich lesbar" on event_attributes for select using (true);
create policy "Werk-Attribute öffentlich lesbar" on work_attributes for select using (true);
create policy "Person-Attribute öffentlich lesbar" on person_attributes for select using (true);
create policy "Ensemble-Attribute öffentlich lesbar" on ensemble_attributes for select using (true);
create policy "Redaktion verwaltet Attribute" on attributes for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Redaktion verwaltet Event-Attribute" on event_attributes for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Redaktion verwaltet Werk-Attribute" on work_attributes for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Redaktion verwaltet Person-Attribute" on person_attributes for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Redaktion verwaltet Ensemble-Attribute" on ensemble_attributes for all using (is_admin_or_editor()) with check (is_admin_or_editor());

insert into attributes (slug,label_de,group_key,inspiration_title,inspiration_enabled,sort_order) values
 ('klassik_allgemein','Klassik allgemein','gattung',null,false,1),
 ('oper','Oper','gattung','Oper & Musiktheater',true,10),
 ('musiktheater','Musiktheater','gattung','Oper & Musiktheater',false,11),
 ('kammermusik','Kammermusik','gattung','Kammermusik entdecken',true,20),
 ('symphonik','Symphonik','gattung','Große Symphonik',true,30),
 ('vokal','Vokalmusik','besetzung','Chor & Vokalmusik',true,40),
 ('chor','Chor','besetzung','Chor & Vokalmusik',false,41),
 ('neue_musik','Neue Musik','epoche','Neue Musik',true,50),
 ('orgel','Orgel','instrument','Orgel entdecken',true,60),
 ('lied','Lied & Gesang','gattung','Lied & Gesang',true,70),
 ('klavier','Klavier','instrument','Klavier Highlights',true,80),
 ('streicher','Violine & Streicher','instrument','Violine & Streicher',true,90),
 ('alte_musik','Alte Musik','epoche','Alte Musik',true,100),
 ('ballett_tanz','Ballett & Tanz','gattung','Ballett & Tanz',true,110),
 ('festival','Festival & Reihe','kontext','Festivals & Reihen',true,120),
 ('familie','Familie & Kinder','publikum','Familienkonzerte',true,130),
 ('barock','Barock','epoche','Barocke Klangwelten',true,140),
 ('romantik','Romantik','epoche','Romantik pur',true,150),
 ('solo','Solo','besetzung','Solo-Abende',true,160),
 ('open_air','Open Air','kontext','Open Air Konzerte',true,170),
 ('matinee','Matinee','kontext','Matineen am Sonntag',true,180),
 ('musik_20_jh','Musik des 20. Jahrhunderts','epoche','Musik des 20. Jahrhunderts',true,190),
 ('geistlich','Geistliche Musik','kontext','Geistliche Musik',true,200),
 ('blechblaeser','Blechbläser & Brass','instrument','Blechbläser & Brass',true,210),
 ('schlagwerk','Schlagwerk & Rhythmus','instrument','Schlagwerk & Rhythmus',true,220),
 ('zupfinstrumente','Gitarre & Zupfinstrumente','instrument','Gitarre & Zupfinstrumente',true,230),
 ('jazz','Jazz','gattung','Jazz trifft Klassik',true,240),
 ('dirigieren','Dirigieren','rolle','Dirigent:innen im Fokus',true,250),
 ('komponistin','Komponistinnen','rolle','Komponistinnen entdecken',true,260),
 ('premiere','Uraufführung & Premiere','kontext','Uraufführungen & Premieren',true,270),
 ('kostenlos','Freier Eintritt','kontext','Freier Eintritt',true,25)
on conflict (slug) do update set label_de=excluded.label_de, inspiration_title=excluded.inspiration_title,
 inspiration_enabled=excluded.inspiration_enabled, sort_order=excluded.sort_order;

-- Strukturierte Bestandsdaten zuerst (hohe Konfidenz).
insert into event_attributes
select e.id,a.id,1,'heuristic' from events e join attributes a on
 (a.slug='kostenlos' and e.is_free) or (a.slug='open_air' and e.is_open_air) or
 (a.slug='familie' and e.is_family_friendly) or
 (a.slug='festival' and e.festival_id is not null) or
 (a.slug='matinee' and extract(hour from e.start_datetime) < 14 and extract(isodow from e.start_datetime)=7)
on conflict do nothing;

-- Vollständige Bestandsabdeckung ohne falsche Präzision: Was sich aus den
-- vorhandenen strukturierten Feldern/Texten nicht genauer ableiten lässt,
-- erhält nur das schwache neutrale Dachattribut.
insert into event_attributes select e.id,a.id,.25,'heuristic' from events e join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from event_attributes x where x.event_id=e.id) on conflict do nothing;
insert into work_attributes select w.id,a.id,.25,'heuristic' from works w join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from work_attributes x where x.work_id=w.id) on conflict do nothing;
insert into person_attributes select p.id,a.id,.25,'heuristic' from persons p join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from person_attributes x where x.person_id=p.id) on conflict do nothing;
insert into ensemble_attributes select e.id,a.id,.25,'heuristic' from ensembles e join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from ensemble_attributes x where x.ensemble_id=e.id) on conflict do nothing;

insert into ensemble_attributes
select e.id,a.id,case when a.slug in ('chor','symphonik') then 1 else .85 end,'heuristic'
from ensembles e join attributes a on
 (a.slug='chor' and e.type::text='chor') or
 (a.slug='symphonik' and e.type::text='orchester') or
 (a.slug='kammermusik' and e.type::text='kammerensemble') or
 (a.slug='jazz' and e.type::text='big_band')
on conflict do nothing;

insert into person_attributes
select p.id,a.id,case when a.slug='dirigieren' then 1 else .9 end,'heuristic'
from persons p join attributes a on
 (a.slug='dirigieren' and 'dirigent'=any(p.roles::text[])) or
 (a.slug='orgel' and lower(coalesce(p.instrument,'')) ~ 'orgel') or
 (a.slug='klavier' and lower(coalesce(p.instrument,'')) ~ 'klavier|piano') or
 (a.slug='streicher' and lower(coalesce(p.instrument,'')) ~ 'violine|viola|cello|kontrabass') or
 (a.slug='blechblaeser' and lower(coalesce(p.instrument,'')) ~ 'trompete|posaune|horn|tuba') or
 (a.slug='schlagwerk' and lower(coalesce(p.instrument,'')) ~ 'schlagwerk|perkussion') or
 (a.slug='zupfinstrumente' and lower(coalesce(p.instrument,'')) ~ 'gitarre|harfe|laute|mandoline')
on conflict do nothing;

-- Textheuristik für Bestand; Redaktion/KI kann diese Gewichte danach präzisieren.
with rules(slug,pattern,weight) as (values
 ('oper','(^|[^[:alpha:]])oper([^[:alpha:]]|$)|musiktheater|zauberflöte|figaro|traviata|carmen',1.0),
 ('musiktheater','oper|musiktheater|singspiel',.9), ('kammermusik','kammermusik|quartett|quintett|trio',.9),
 ('symphonik','symphon|sinfon|orchesterkonzert',.9), ('vokal','vokal|gesang|chor|messe|requiem|passion',.8),
 ('chor','chor',1.0), ('neue_musik','neue musik|zeitgenöss|contemporary',.9), ('orgel','orgel',1.0),
 ('lied','liederabend|kunstlied|gesang',.9), ('klavier','klavier|piano',.9),
 ('streicher','violine|viola|cello|streich|quartett',.8), ('alte_musik','alte musik|renaissance|mittelalter',.9),
 ('ballett_tanz','ballett|tanz|dance',1.0), ('familie','familie|kinder|jugend',.9),
 ('barock','barock|bach|händel|vivaldi',.8), ('romantik','romantik|romantic',.8),
 ('solo','solo|rezital|recital',.8), ('musik_20_jh','20. jahrhundert|modernismus',.8),
 ('geistlich','geistlich|kirchenmusik|messe|requiem|passion|oratorium',.9),
 ('blechblaeser','blech|brass|trompete|posaune|horn|tuba',.9),
 ('schlagwerk','schlagwerk|perkussion|rhythm',.9), ('zupfinstrumente','gitarre|harfe|laute|mandoline',.9),
 ('jazz','jazz|big band|swing',1.0), ('premiere','uraufführung|premiere|erstaufführung',1.0)
)
insert into work_attributes
select w.id,a.id,r.weight,'heuristic' from works w cross join rules r join attributes a on a.slug=r.slug
where lower(concat_ws(' ',w.title,w.genre,w.description_de)) ~ r.pattern
on conflict do nothing;

insert into work_attributes
select w.id,a.id,.95,'heuristic' from works w join attributes a on a.slug='musik_20_jh'
where w.composition_year between 1900 and 1999
on conflict do nothing;

with rules(slug,pattern,weight) as (values
 ('oper','(^|[^[:alpha:]])oper([^[:alpha:]]|$)|musiktheater|zauberflöte|figaro|traviata|carmen',1.0), ('kammermusik','kammermusik|quartett|quintett|trio',.9),
 ('symphonik','symphon|sinfon|orchester',.9), ('vokal','vokal|gesang|chor|messe|requiem|passion',.8),
 ('neue_musik','neue musik|zeitgenöss',.9), ('orgel','orgel',1.0), ('lied','lied|gesang',.9),
 ('klavier','klavier|piano',.9), ('streicher','violine|viola|cello|streich',.8), ('alte_musik','alte musik|renaissance|mittelalter',.9),
 ('ballett_tanz','ballett|tanz',1.0), ('barock','barock|bach|händel|vivaldi',.8), ('romantik','romantik',.8),
 ('geistlich','geistlich|kirchenmusik|messe|requiem|passion|oratorium',.9), ('jazz','jazz|big band|swing',1.0),
 ('premiere','uraufführung|premiere|erstaufführung',1.0)
)
insert into event_attributes
select e.id,a.id,r.weight,'heuristic' from events e cross join rules r join attributes a on a.slug=r.slug
where lower(concat_ws(' ',e.title,e.subtitle,e.category,e.description_de,e.program_notes_de)) ~ r.pattern
on conflict do nothing;

-- Attributbasierte Inspiration: direkte Event-Zuordnung plus gewichtete
-- Vererbung Werk 0.95, Ensemble 0.85, Person 0.70. MAX statt Summe verhindert,
-- dass viele schwache Verknüpfungen eine fachlich starke überstimmen.
create function inspiration_events(p_attribute_slug text, p_result_limit int default 60)
returns table (
 id uuid, slug text, title text, subtitle text, start_datetime timestamptz,
 image_urls text[], status event_status, category text, is_free boolean,
 venues jsonb, event_genres jsonb, event_participants jsonb, attribute_score numeric
) language sql stable as $$
with target as (select id from attributes where attributes.slug=p_attribute_slug), signals as (
 select ea.event_id,ea.weight score from event_attributes ea join target t on t.id=ea.attribute_id
 union all select ew.event_id,wa.weight*.95 from event_works ew join work_attributes wa using(work_id) join target t on t.id=wa.attribute_id
 union all select ep.event_id,pa.weight*.70 from event_participants ep join person_attributes pa using(person_id) join target t on t.id=pa.attribute_id
 union all select ep.event_id,ea.weight*.85 from event_participants ep join ensemble_attributes ea using(ensemble_id) join target t on t.id=ea.attribute_id
), ranked as (select event_id,max(score) score from signals group by event_id)
select e.id,e.slug,e.title,e.subtitle,e.start_datetime,e.image_urls,e.status,e.category,e.is_free,
 jsonb_build_object('id',v.id,'name',v.name,'photo_url',v.photo_url),
 coalesce((select jsonb_agg(jsonb_build_object('genres',jsonb_build_object('id',g.id,'slug',g.slug,'label_de',g.label_de))) from event_genres eg join genres g on g.id=eg.genre_id where eg.event_id=e.id),'[]'::jsonb),
 coalesce((select jsonb_agg(jsonb_build_object('persons',case when p.id is null then null else jsonb_build_object('id',p.id,'full_name',p.full_name,'photo_url',p.photo_url) end,'ensembles',case when en.id is null then null else jsonb_build_object('id',en.id,'name',en.name,'photo_url',en.photo_url) end)) from event_participants ep left join persons p on p.id=ep.person_id left join ensembles en on en.id=ep.ensemble_id where ep.event_id=e.id),'[]'::jsonb),
 round(r.score,2)
from ranked r join events e on e.id=r.event_id join venues v on v.id=e.venue_id
where e.status='scheduled' and e.start_datetime>=now()
order by r.score desc,e.start_datetime asc limit greatest(1,least(p_result_limit,100));
$$;
grant execute on function inspiration_events(text,int) to anon,authenticated;
