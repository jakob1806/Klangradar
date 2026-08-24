-- Strukturierte/enge Ergänzungen für Inspirationskategorien, die im aktuellen
-- Katalog sonst leer wären. Keine unscharfe Volltextsuche beim Abruf.
insert into work_attributes
select w.id,a.id,.95,'heuristic' from works w join attributes a on a.slug='musik_20_jh'
where w.composition_year between 1900 and 1999
on conflict do nothing;

with rules(slug,pattern,weight) as (values
 ('festival','festival|festspiele|festwoche',1.0),
 ('open_air','open[ -]?air|freiluft',1.0),
 ('matinee','matinee|matinée',1.0),
 ('musik_20_jh','20\. jahrhundert|moderne klassik',.9)
)
insert into event_attributes
select e.id,a.id,r.weight,'heuristic' from events e cross join rules r join attributes a on a.slug=r.slug
where lower(concat_ws(' ',e.title,e.subtitle,e.category,e.description_de,e.program_notes_de)) ~ r.pattern
on conflict do nothing;
