-- Programm der kommenden Münchner-Philharmoniker-Konzerte neu einlesen.
-- Die KI-Programmextraktion bekam bisher den vollen Seitentext inklusive des
-- "Further Events"-Karussells (andere Konzerte) und legte dadurch falsche
-- oder doppelte Werke an (z. B. "Psalm 42" doppelt, "Così fan tutte" einmal
-- als Ouvertüre und einmal als Oper). pageText.ts schneidet diesen Bereich
-- jetzt ab (siehe stripRelatedSections); damit die bereits angelegten
-- Fehl-Verknüpfungen nicht stehen bleiben (die Anreicherung überspringt
-- vorhandene event_works), werden sie entfernt und die Events zur erneuten
-- Extraktion vorgemerkt.
with mphil as (
  select id from events
  where website_url ilike '%mphil.de/%'
    and status = 'scheduled'
    and start_datetime >= now()
), cleared as (
  delete from event_works where event_id in (select id from mphil) returning event_id
)
update events
set program_extraction_status = 'pending',
    references_checked_at = null,
    program_retry_after = null
where id in (select id from mphil);
