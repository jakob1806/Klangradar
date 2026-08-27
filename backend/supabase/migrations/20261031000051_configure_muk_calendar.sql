-- Rekonstruiert aus supabase_migrations.schema_migrations.statements der
-- echten Produktions-DB (2026-08-27) -- eine andere Session hatte dies
-- direkt gegen Produktion gepusht, ohne die SQL-Datei je zu committen.
-- Diese Datei stellt nur die Git-Historie wieder her (exakter Wortlaut
-- der bereits angewendeten Statements); die tatsächliche Anwendung auf
-- Produktion ist bereits erfolgt, siehe migration-repair-Verfahren.

insert into public.venues
  (slug,name,address_street,address_zip,address_city,location,website_url,is_verified,venue_type,region_id,city_id)
values
  ('muk-wien','MUK – Musik und Kunst Privatuniversität Wien','Johannesgasse 4a','1010','Wien',
   st_setsrid(st_makepoint(16.3747,48.2047),4326)::geography,'https://muk.ac.at/',false,'konzertsaal',
   (select id from regions where slug='vienna'),(select id from regions where slug='vienna'))
on conflict (slug) do update set name=excluded.name, website_url=excluded.website_url,
  region_id=excluded.region_id, city_id=excluded.city_id;

update sources
set type='scrape',
    url='https://muk.ac.at/veranstaltungsuebersicht.html',
    venue_id=(select id from venues where slug='muk-wien'),
    status='under_review',
    config=jsonb_build_object(
      'parser','scrape',
      'itemSelector','.events-list .item-wrap.item-list',
      'titleSelector','h3 a',
      'titleFullText',true,
      'urlSelector','h3 a[href]',
      'dateSelector','.date.smaller',
      'venueSelector','.location .city',
      'venueNameMap',jsonb_build_object(
        'MUK, Verschiedene Säle','MUK – Musik und Kunst Privatuniversität Wien',
        'MUK, MUK.theater','MUK – Musik und Kunst Privatuniversität Wien',
        'MUK, Seminarraum','MUK – Musik und Kunst Privatuniversität Wien',
        'OWA, Pavillon 10','MUK – Musik und Kunst Privatuniversität Wien',
        'Otto Wagner Areal','MUK – Musik und Kunst Privatuniversität Wien'
      ),
      'venueExcludeIfContains',jsonb_build_array('Verschiedene Orte'),
      'nextPageSelector','a.page-link[title="next"]',
      'baseUrl','https://muk.ac.at',
      'deferImageEnrichment',true
    )
where id='cf5c8600-eab2-418b-8ce9-d09a1102d4c7';
