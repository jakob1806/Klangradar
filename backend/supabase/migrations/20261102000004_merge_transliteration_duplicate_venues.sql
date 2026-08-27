-- Nutzeranfrage "frankfurt hat noch erstaunlich wenige konzerte. ebenso wie
-- berlin" führte zur Prüfung der neu importierten Venues: detect_venue_
-- duplicate_candidates() (bisher nur wöchentlich per Cron, seit dem Import
-- der vier neuen Städte noch nicht gelaufen) fand u.a. echte Dubletten aus
-- der Zusammenführung der beiden parallelen Stammdaten-Importe — dieselbe
-- Venue mit/ohne Stadt-Suffix oder in zwei Umlaut-Transliterationen
-- (ä→ae vs. weggelassen, z.B. "Kühlhaus"→"kuehlhaus-berlin"/"kuhlhaus-berlin").
--
-- Nur eindeutige Fälle (identische Adresse, reine Schreibvariante derselben
-- Institution) werden hier automatisch gemerged — Gebäude mit mehreren
-- echten Sälen (z.B. Musikverein Wien, Wiener Konzerthaus, Elbphilharmonie,
-- Alte Oper Frankfurt, Laeiszhalle) bleiben als getrennte Venues bestehen,
-- genau wie München "Großer/Kleiner Konzertsaal der HMTM" schon vorher.
-- Diese und alle übrigen unklaren Kandidaten bleiben als 'pending' in
-- venue_duplicate_candidates für die manuelle Prüfung im Admin-Dashboard
-- (/duplicates) stehen.
--
-- Merge-Logik ist absichtlich identisch zu admin/src/app/(dashboard)/
-- duplicates/venues/actions.ts (resolveVenueDuplicateAsMerged), nur als
-- SQL statt Server-Action, weil hier keine interaktive Admin-Session zur
-- Verfügung steht.

do $$
declare
  pair record;
  keep_id uuid;
  remove_id uuid;
  remove_name text;
begin
  for pair in
    select * from (values
      ('arnold-schoenberg-center', 'arnold-schonberg-center'),
      ('hauptkirche-st-katharinen', 'st-katharinen-hamburg'),
      ('heimathafen-neukoelln', 'heimathafen-neukolln'),
      ('kaiser-wilhelm-gedaechtniskirche', 'kaiser-wilhelm-gedachtniskirche'),
      ('kuehlhaus-berlin', 'kuhlhaus-berlin'),
      ('orangerie-schonbrunn', 'orangery-schoenbrunn'),
      ('porgy-and-bess-wien', 'porgy-bess'),
      ('radialsystem', 'radialsystem-berlin'),
      ('schillertheater-berlin', 'schillertheater'),
      ('ndr-rolf-liebermann-studio', 'rolf-liebermann-studio'),
      ('gethsemanekirche', 'gethsemanekirche-berlin'),
      ('kulturkirche-altona', 'st-johannis-altona'),
      ('hofburgkapelle', 'wiener-hofburgkapelle'),
      ('karlskirche', 'karlskirche-wien'),
      ('minoritenkirche', 'minoritenkirche-wien'),
      ('votivkirche', 'votivkirche-wien'),
      ('stephansdom', 'stephansdom-wien'),
      ('thalia-theater-hamburg', 'thalia-theater'),
      ('st-katharinen-frankfurt', 'st-katharinenkirche'),
      ('frankfurter-dom', 'kaiserdom-st-bartholomaus')
    ) as t(keep_slug, remove_slug)
  loop
    select id into keep_id from venues where slug = pair.keep_slug;
    select id into remove_id from venues where slug = pair.remove_slug;

    if keep_id is null or remove_id is null then
      raise notice 'Ueberspringe %/%: eine Seite fehlt (keep=%, remove=%)', pair.keep_slug, pair.remove_slug, keep_id, remove_id;
      continue;
    end if;

    select name into remove_name from venues where id = remove_id;

    update events set venue_id = keep_id where venue_id = remove_id;
    update sources set venue_id = keep_id where venue_id = remove_id;
    update ensembles set home_venue_id = keep_id where home_venue_id = remove_id;
    update entity_candidates set suggested_venue_id = keep_id where suggested_venue_id = remove_id;

    delete from user_favorite_venues old where old.venue_id = remove_id and exists (
      select 1 from user_favorite_venues kept where kept.user_id = old.user_id and kept.venue_id = keep_id
    );
    update user_favorite_venues set venue_id = keep_id where venue_id = remove_id;

    update images set is_primary = false
      where origin_type = 'venue' and origin_id = remove_id and is_primary
        and exists (select 1 from images where origin_type = 'venue' and origin_id = keep_id and is_primary);
    update images set origin_id = keep_id where origin_type = 'venue' and origin_id = remove_id;

    delete from field_provenance old where old.entity_type = 'venue' and old.entity_id = remove_id and exists (
      select 1 from field_provenance kept where kept.entity_type = 'venue' and kept.entity_id = keep_id and kept.field_name = old.field_name
    );
    update field_provenance set entity_id = keep_id where entity_type = 'venue' and entity_id = remove_id;

    delete from entity_aliases old where old.entity_type = 'venue' and old.entity_id = remove_id and (
      old.alias_normalized = public.normalize_entity_name((select name from venues where id = keep_id)) or exists (
        select 1 from entity_aliases kept where kept.entity_type = 'venue' and kept.entity_id = keep_id and kept.alias_normalized = old.alias_normalized
      )
    );
    update entity_aliases set entity_id = keep_id where entity_type = 'venue' and entity_id = remove_id;
    if public.normalize_entity_name(remove_name) <> public.normalize_entity_name((select name from venues where id = keep_id)) then
      insert into entity_aliases(entity_type, entity_id, alias) values ('venue', keep_id, remove_name) on conflict do nothing;
    end if;

    update venue_duplicate_candidates set status = 'merged', reviewed_at = now()
      where status = 'pending' and remove_id in (venue_a_id, venue_b_id) and keep_id in (venue_a_id, venue_b_id);
    update venue_duplicate_candidates set status = 'dismissed', reviewed_at = now()
      where status = 'pending' and remove_id in (venue_a_id, venue_b_id);

    delete from venues where id = remove_id;
  end loop;
end $$;

-- Eindeutige Falsch-Treffer aus derselben Detektionsrunde (gleicher/
-- aehnlicher Name, aber andere Stadt oder anderes Gebaeude) direkt als
-- 'dismissed' markieren, damit sie die Admin-Warteschlange nicht unnoetig
-- fuellen: St. Michael München vs. St. Michaelis Hamburg, Konzerthaus
-- Berlin vs. Wiener Konzerthaus, Philharmonie Berlin vs. Elbphilharmonie,
-- sowie die beiden Falsch-Treffer der (jetzt eindeutigen) Frankfurter
-- Katharinenkirche gegen Hamburger Katharinenkirche-Varianten. Per
-- fester ID statt Slug-Join, weil die Merge-Schleife oben einige der
-- beteiligten Venues bereits geloescht (und ihre Referenz in dieser
-- Tabelle per ON DELETE SET NULL genullt) haben kann.
update venue_duplicate_candidates
  set status = 'dismissed', reviewed_at = now()
  where status = 'pending'
    and id in (
      '87d908a4-0883-4614-abb3-9f0a30fe6081', -- st-michael <> st-michaelis-michel
      '9ed81140-fe46-4226-b606-12e97f52a293', -- konzerthaus-berlin-grosser-saal <> wiener-konzerthaus-grosser-saal
      '8637b6b6-0461-461a-a7db-f8b2d80455c2', -- philharmonie-berlin-grosser-saal <> elbphilharmonie-grosser-saal
      'a5400314-53bb-4820-a9dd-659e70caa353', -- st-katharinenkirche(FFM) <> st-katharinen-hamburg
      'f84d381c-e4f1-45d1-b7e0-4f8251f43025'  -- st-katharinenkirche(FFM) <> hauptkirche-st-katharinen
    );
