insert into attributes(slug,label_de,group_key,inspiration_enabled,sort_order)
values('klassik_allgemein','Klassik allgemein','gattung',false,1)
on conflict(slug) do nothing;

insert into event_attributes select e.id,a.id,.25,'heuristic' from events e join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from event_attributes x where x.event_id=e.id) on conflict do nothing;
insert into work_attributes select w.id,a.id,.25,'heuristic' from works w join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from work_attributes x where x.work_id=w.id) on conflict do nothing;
insert into person_attributes select p.id,a.id,.25,'heuristic' from persons p join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from person_attributes x where x.person_id=p.id) on conflict do nothing;
insert into ensemble_attributes select e.id,a.id,.25,'heuristic' from ensembles e join attributes a on a.slug='klassik_allgemein'
where not exists(select 1 from ensemble_attributes x where x.ensemble_id=e.id) on conflict do nothing;
