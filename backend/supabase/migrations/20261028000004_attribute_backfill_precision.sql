-- Präzisiert den initialen Backfill: "oper" darf nicht mitten in Wörtern
-- wie "Kooperation" matchen. Ergänzt Komponistinnen, sofern die vorhandene
-- Biografie/Rollenbeschreibung dies explizit ausweist.
delete from event_attributes ea using attributes a
where ea.attribute_id=a.id and a.slug='oper' and ea.source='heuristic';
delete from work_attributes wa using attributes a
where wa.attribute_id=a.id and a.slug='oper' and wa.source='heuristic';

insert into event_attributes
select e.id,a.id,1,'heuristic' from events e join attributes a on a.slug='oper'
where lower(concat_ws(' ',e.title,e.subtitle,e.category,e.description_de,e.program_notes_de))
  ~ '(^|[^[:alpha:]])oper([^[:alpha:]]|$)|musiktheater|zauberflöte|figaro|traviata|carmen'
on conflict do nothing;
insert into work_attributes
select w.id,a.id,1,'heuristic' from works w join attributes a on a.slug='oper'
where lower(concat_ws(' ',w.title,w.genre,w.description_de))
  ~ '(^|[^[:alpha:]])oper([^[:alpha:]]|$)|musiktheater|zauberflöte|figaro|traviata|carmen'
on conflict do nothing;

insert into person_attributes
select p.id,a.id,1,'heuristic' from persons p join attributes a on a.slug='komponistin'
where lower(concat_ws(' ',p.biography_de,p.biography_en)) ~ 'komponistin|female composer|composeress'
on conflict do nothing;
