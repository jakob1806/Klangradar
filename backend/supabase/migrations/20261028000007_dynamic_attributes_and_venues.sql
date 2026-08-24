alter table attributes add column if not exists icon_name text;
alter table attributes add column if not exists color_key text not null default 'accent';

create table venue_attributes (
  venue_id uuid not null references venues(id) on delete cascade,
  attribute_id uuid not null references attributes(id) on delete cascade,
  weight numeric(3,2) not null check (weight > 0 and weight <= 1),
  source text not null default 'editorial' check (source in ('editorial','import','heuristic','ai')),
  primary key (venue_id, attribute_id)
);
create index venue_attributes_attribute_idx on venue_attributes(attribute_id, weight desc);
alter table venue_attributes enable row level security;
create policy "Venue-Attribute öffentlich lesbar" on venue_attributes for select using (true);
create policy "Redaktion verwaltet Venue-Attribute" on venue_attributes for all using (is_admin_or_editor()) with check (is_admin_or_editor());

update attributes set icon_name=case slug
 when 'oper' then 'theatermasks.fill' when 'kammermusik' then 'music.quarternote.3'
 when 'kostenlos' then 'ticket.fill' when 'symphonik' then 'music.note.house.fill'
 when 'vokal' then 'person.3.fill' when 'neue_musik' then 'waveform'
 when 'orgel' then 'pianokeys' when 'lied' then 'music.mic'
 when 'klavier' then 'pianokeys.inverse' when 'alte_musik' then 'scroll.fill'
 when 'ballett_tanz' then 'figure.dance' when 'festival' then 'sparkles'
 when 'familie' then 'figure.2.and.child.holdinghands' when 'romantik' then 'heart.fill'
 when 'open_air' then 'sun.max.fill' when 'matinee' then 'cup.and.saucer.fill'
 when 'geistlich' then 'building.columns.fill' when 'schlagwerk' then 'circle.grid.cross.fill'
 when 'dirigieren' then 'figure.wave' when 'komponistin' then 'person.fill'
 when 'premiere' then 'star.fill' else 'music.note' end,
 color_key=case mod(sort_order,6) when 0 then 'blue' when 1 then 'purple' when 2 then 'orange' when 3 then 'teal' when 4 then 'pink' else 'indigo' end
where inspiration_enabled;

drop function if exists inspiration_events(text,int);
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
 union all select e.id,va.weight*.80 from events e join venue_attributes va on va.venue_id=e.venue_id join target t on t.id=va.attribute_id
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
