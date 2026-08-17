-- Raum/Buehne als Zusatz der Veranstaltung statt kuenstlicher Einzel-Venue.
alter table events add column if not exists venue_detail text;
comment on column events.venue_detail is
  'Saal, Raum oder Buehne innerhalb der verknuepften Venue; keine eigene Kartenposition.';

update sources
set config = config
  || jsonb_build_object(
    'itemAllowClassContains', jsonb_build_array('ort-57','ort-107'),
    'venueDetailSelector', '.col-xl-3 .text-produktion-font-color span',
    'parserVersion', 2
  )
  - 'itemExcludeClassContains',
  last_run_at = null
where id='c1100000-0000-4000-8000-000000000002'::uuid;

update events set venue_detail='Probebühne'
where source_id='c1100000-0000-4000-8000-000000000002'::uuid
  and external_id like '%ID_Vorstellung=5477%';
update events set venue_detail='Studiobühne'
where source_id='c1100000-0000-4000-8000-000000000002'::uuid
  and external_id like '%ID_Vorstellung=5478%';

-- Diese Gastspiele liegen laut offizieller Detailseite in Grassau bzw.
-- Gruenwald und gehoeren nicht zur Muenchner Stamm-Venue.
update events set status='cancelled'
where source_id='c1100000-0000-4000-8000-000000000002'::uuid
  and (external_id like '%ID_Vorstellung=5180%' or external_id like '%ID_Vorstellung=5444%');
