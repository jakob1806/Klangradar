-- Der einzige bestehende Theaterakademie-Termin verwendet als Website eine
-- mailto:-Adresse und konnte deshalb nicht über die Domain-Zuordnung der
-- vorigen Migration erkannt werden. Das Stiftungsdinner wird ausdrücklich
-- von der August Everding Stiftung veranstaltet.

update public.events
set organizer_id = (select id from public.organizers where slug = 'august-everding-stiftung')
where organizer_id is null
  and title ilike '%Stiftungsdinner%'
  and website_url ilike '%theaterakademie.de%';

update public.sources s
set venue_id = null,
    person_id = null,
    ensemble_id = null,
    organizer_id = (select id from public.organizers where slug = 'august-everding-stiftung')
where s.id in (
  select distinct e.source_id from public.events e
  where e.organizer_id = (select id from public.organizers where slug = 'august-everding-stiftung')
    and e.source_id is not null
);
