-- Rekonstruiert aus supabase_migrations.schema_migrations.statements der
-- echten Produktions-DB (2026-08-27) -- eine andere Session hatte dies
-- direkt gegen Produktion gepusht, ohne die SQL-Datei je zu committen.
-- Diese Datei stellt nur die Git-Historie wieder her (exakter Wortlaut
-- der bereits angewendeten Statements); die tatsächliche Anwendung auf
-- Produktion ist bereits erfolgt, siehe migration-repair-Verfahren.

-- Verified against mdw's server-rendered year calendar on 2026-08-27.
-- The normal /veranstaltungen/ route redirects; /veranstaltung/ exposes the
-- actual calendar and accepts an explicit date range.
set role postgres;

update sources
set type = 'scrape',
    url = 'https://www.mdw.ac.at/veranstaltung/?daterange=27.08.2026+%E2%80%93+27.08.2027',
    status = 'under_review',
    config = jsonb_build_object(
      'parser', 'scrape',
      'itemSelector', 'ul.VerUeb > li.clearfix',
      'titleSelector', '.verMain h2',
      'titleFullText', true,
      'urlSelector', '.verMain a:has(h2)[href]',
      'dateSelector', '.verMain',
      'tagsSelector', '.Themen a',
      'includeIfTagContains', jsonb_build_array(
        'konzert', 'musik', 'orchester', 'oper', 'gesang', 'kammermusik',
        'chor', 'alte musik', 'neue musik'
      ),
      'venueAfterSelector', '.Themen',
      'venueStripPattern', ',\\s*[^,]+,\\s*\\d{4}\\s+Wien.*$',
      'venueNameMap', jsonb_build_object(
        'Clara Schumann-Saal', 'mdw – Universität für Musik und darstellende Kunst',
        'Neuer Konzertsaal', 'mdw – Universität für Musik und darstellende Kunst',
        'Alter Konzertsaal', 'mdw – Universität für Musik und darstellende Kunst',
        'Franz Liszt-Saal', 'mdw – Universität für Musik und darstellende Kunst',
        'Joseph Haydn-Saal', 'mdw – Universität für Musik und darstellende Kunst',
        'Fanny Hensel-Saal', 'mdw – Universität für Musik und darstellende Kunst',
        'Festsaal', 'mdw – Universität für Musik und darstellende Kunst',
        'Konzertsaal, Future Art Lab', 'mdw – Universität für Musik und darstellende Kunst',
        'Musikverein Wien', 'Wiener Musikverein',
        'ORF RadioKulturhaus', 'ORF RadioKulturhaus'
      ),
      'imageSelector', '.verBild img',
      'baseUrl', 'https://www.mdw.ac.at',
      'deferImageEnrichment', true
    )
where id = 'fd148ef6-ad4c-4fba-908f-6ebbf9075be8';

-- DSO was live-tested through its official public JSON endpoint: 40 valid
-- future events, all mapped to known Berlin venues.
update sources
set status = 'active'
where id = '28b23419-020d-4dd5-8552-568dc11f2757';
