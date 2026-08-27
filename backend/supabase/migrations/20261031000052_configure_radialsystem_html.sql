-- Rekonstruiert aus supabase_migrations.schema_migrations.statements der
-- echten Produktions-DB (2026-08-27) -- eine andere Session hatte dies
-- direkt gegen Produktion gepusht, ohne die SQL-Datei je zu committen.
-- Diese Datei stellt nur die Git-Historie wieder her (exakter Wortlaut
-- der bereits angewendeten Statements); die tatsächliche Anwendung auf
-- Produktion ist bereits erfolgt, siehe migration-repair-Verfahren.

update sources
set type='scrape',
    url='https://www.radialsystem.de/de/programm/',
    venue_id=(select id from venues where slug='radialsystem-berlin'),
    status='under_review',
    config=jsonb_build_object(
      'parser','scrape',
      'itemSelector','.event-list-entry',
      'titleSelector','.the-name a',
      'titleFullText',true,
      'urlSelector','.the-name a[href]',
      'dateSelector','.the-date .to-desktop .dateblock',
      'tagsSelector','.the-format .tag',
      'includeIfTagContains',jsonb_build_array('musik','konzert','klang'),
      'defaultVenueName','Radialsystem',
      'venueDetailSelector','.the-date .location',
      'baseUrl','https://www.radialsystem.de',
      'deferImageEnrichment',true
    )
where id='55b884bb-5f41-4976-abaa-53a64fed3072';
