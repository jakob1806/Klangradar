# Stadt-Erweiterung: Import Berlin, Hamburg, Frankfurt, Wien

Stand: 2026-08-26. Dokumentiert den Import aus `Klangradar_Stadtkatalog_Import.xlsx`
(kuratierte Recherche, Stand 26.08.2026) in die Migrationen
`20261029000003`–`20261029000007`.

## Umfang

128 Personen, 128 Ensembles, 128 Venues (je 32 pro Stadt: Berlin, Hamburg,
Frankfurt am Main, Wien) plus 92 Aliase (von 384 in der Quelldatei — 292
waren reine Duplikate des kanonischen Namens, siehe unten). Erweitert den
bisher auf München fokussierten Scope (siehe README) auf vier weitere
Städte — explizite Produktentscheidung, nicht nur ein Datenimport.

## Trennung nach Städten

Jede Stadt hat eine eigene Migrationsdatei
(`20261029000004_city_import_berlin.sql` usw.), damit ein Fehler oder eine
nötige Korrektur in den Daten einer Stadt isoliert behoben/zurückgerollt
werden kann, ohne die anderen drei anzufassen. `regions`-Migration
(`20261029000003`) legt für jede Stadt eine eigene `country → state → city`
Kette an (Berlin/Hamburg/Wien: Land = Stadtname, da Stadtstaaten;
Frankfurt: Land = Hessen), analog zur bestehenden München-Struktur aus
`20260819000005_regions.sql`. `venues.region_id` verlinkt jede Venue auf
ihre Stadt-Region — darüber laufen auch alle bestehenden Queries, die
`events.venue_id → venues.region_id` joinen (siehe
`20260823000001_source_confidence_thresholds_and_index.sql`).

## `is_active = true` — auf ausdrücklichen Nutzerwunsch live geschaltet

Alle vier neuen Regionen (Land/Bundesland/Stadt) wurden zunächst mit
`is_active = false` angelegt (Feature-Flag-Muster aus
`20260819000005_regions.sql`), da die Quelldatei sich selbst als nicht
produktionsreif markiert (QA-Blatt: "Koordinaten, Kontaktdaten,
Barrierefreiheit und Bildrechte vor Produktivimport vervollständigen").
**`20261029000008_activate_city_expansion.sql` schaltet sie dennoch live** —
explizite Nutzerentscheidung nach Hinweis auf die Konsequenzen (siehe
Session-Verlauf): Nutzer:innen sehen die 4 Städte jetzt, bevor Bilder,
redaktionelle Freigabe (`is_verified`) und Events existieren.

## Was vor dem Import erledigt wurde

- **Geocoding**: Alle 128 Venue-Adressen wurden per OpenStreetMap/Nominatim
  geokodiert (`venues.location` ist `NOT NULL` — ohne Koordinaten ließe sich
  gar nicht einfügen). Plausibilitätsprüfung gegen grobe Stadt-Bounding-Boxes
  bestand für alle 128 Punkte. Ein Fallback war nötig
  (`wiener-hofburgkapelle`: volle Adresse "Hofburg, Schweizerhof" lieferte
  kein Ergebnis, vereinfacht auf "Hofburg, 1010 Wien" — Koordinate zeigt auf
  den Hofburg-Gesamtkomplex, nicht den exakten Kapellenflügel).
- **Rollen-Mapping** (`persons.roles`, freies `text[]` seit
  `20261013000014_persons_roles_free_text.sql`): Quelldatei nutzt englische
  Token (roles_json), App-Vokabular ist deutsch. Mapping:
  `conductor→dirigent, composer→komponist, pianist/organist/singer/soloist→solist`
  (folgt der bestehenden München-Konvention, wo Sänger:innen/Instrumentalist:innen
  einheitlich als "solist" geführt werden), `director→regisseur`,
  `musician→musiker` (beide ohne bestehendes Label in
  `role_labels.dart` — zeigen bis zu einer UI-Ergänzung den Rohwert an,
  genau der Fall, für den `roles` bewusst auf freien Text geöffnet wurde).
- **Ensemble-Typ-Mapping** (`ensembles.type` ist weiterhin ein striktes Enum:
  `chor/orchester/kammerensemble/big_band/sonstiges`): 16 englische
  Quellwerte auf diese 5 gemappt, z. B. `symphony_orchestra/opera_orchestra/
  chamber_orchestra→orchester`, `choir/opera_chorus→chor`,
  `string_quartet/chamber_ensemble/early_music_ensemble→kammerensemble`,
  `choir_or_orchestra→sonstiges` (mangels Eindeutigkeit).
- **Alias-Filterung**: `entity_aliases` hat einen Trigger
  (`validate_entity_alias_target_trigger`, `20261013000016_canonical_entity_alias_system.sql`),
  der jeden Alias ablehnt, dessen normalisierte Form exakt dem
  normalisierten kanonischen Namen entspricht ("Alias must differ from
  canonical name"). 292 der 384 Alias-Zeilen der Quelldatei waren genau
  das (z. B. Alias "Berliner Philharmoniker" für das gleichnamige
  Ensemble — vermutlich ursprünglich für Such-Indexierung gedacht) und
  wurden vor dem Import herausgefiltert; die verbleibenden 92 sind echte
  Kurzformen (z. B. "Staatskapelle" als Alias für "Staatskapelle Berlin").
- **Upsert-Strategie**: Alle Inserts laufen über `ON CONFLICT (slug) DO
  UPDATE`, wie von der Quelldatei selbst vorgegeben (`import_action:
  upsert`/`upsert_global`). `is_verified` wird beim Update **nie**
  überschrieben (nicht in der `SET`-Klausel enthalten) — eine bereits
  redaktionell freigegebene Zeile (z. B. eine Person, die schon aus dem
  München-Bestand existiert) bleibt verifiziert, auch wenn dieser Import sie
  erneut trifft. `persons.roles` wird bei Konflikt vereinigt (bestehende +
  neue Rollen), nicht ersetzt.
- **Getestet**: Lokal gegen ein aus den aktuellen Migrationen abgeleitetes
  Schema (persons/ensembles/venues/regions/entity_aliases exakt in ihrer
  heutigen Spaltenform) mit echtem Postgres+PostGIS verifiziert — alle 4
  Städte-Migrationen laufen fehlerfrei, sind idempotent (mehrfaches Ausführen
  erzeugt keine Duplikate/Fehler), alle 384 Aliase lösen korrekt auf, keine
  Venue ohne Koordinate.

## `home_venue_id`-Backfill (`20261029000009_backfill_home_venues.sql`)

Die Quelldatei ließ `home_venue_slug` für **alle 128 Ensembles** leer.
`20261029000009` trägt das für **18 Ensembles** nach — bewusst nur die
Fälle, in denen die Zuordnung öffentlich eindeutig/institutionell
untrennbar ist (z. B. Berliner Philharmoniker → Philharmonie Berlin,
Staatskapelle Berlin → Staatsoper Unter den Linden, Wiener Philharmoniker →
Musikverein). Für die übrigen ~110 Ensembles wurde **bewusst nichts
geraten** — eine falsche Verknüpfung ist schwerer zu entdecken als eine
fehlende. Redaktionelle Nachpflege bleibt offen.

## Karten-Zentrierung (Flutter + iOS-native)

`app/lib/features/map/presentation/map_screen.dart` und
`ios-native/.../VenueMapView.swift` zentrierten die Kartenansicht fix auf
München — ohne Fix wären Venues in den 4 neuen Städten unsichtbar gewesen,
bis man manuell dorthin scrollt. Beide zentrieren jetzt einmalig auf den
Nutzerstandort (falls verfügbar) oder andernfalls auf die Bounding-Box aller
geladenen Venues.

## Stadt-Filter für die Karte (`20261029000010_venues_with_latlng_region_filter.sql`)

`venues_with_latlng()` bekam einen optionalen `p_region_id`-Parameter
(rückwärtskompatibel: `null` = alle Venues, altes Verhalten). Die Flutter-App
hat jetzt einen Städte-Umschalter auf der Karte
(`app/lib/core/regions/region_providers.dart`,
`selectedCityRegionProvider`/`activeCityRegionsProvider`) — Chip in der
Filterleiste, nur sichtbar sobald mehr als eine Stadt aktiv ist. Die Auswahl
ist bewusst nur In-Memory (kein Persistieren über SharedPreferences), setzt
bei App-Neustart also auf "alle Städte" zurück.

**Bekannte Einschränkung, nicht behoben:** Nur die Karte filtert. Suche
(`search_all`), Home-Feed und Kalender kennen weiterhin keinen Stadt-Filter
— `preferred_region_id` auf dem Nutzerprofil wird gespeichert, aber
nirgends gelesen. Diese RPCs auf denselben `p_region_id`-Parameter
umzustellen (plus die entsprechende UI in Suche/Home/Kalender) ist eine
größere, hier nicht umgesetzte Folgeänderung. iOS-native hat noch keinen
Städte-Umschalter (siehe unten).

## Event-Ingestion — je eine echte Quelle pro Stadt, weiterhin weit von München entfernt

Programme/Events selbst sind nicht Teil dieser Datei — nur Stammdaten
(Personen/Ensembles/Venues). Auf Basis einer vom Nutzer bereitgestellten,
priorisierten Quellenliste (`Klangradar_Konzertquellen_Scraper.xlsx`) wurde
je eine reale, gegen echtes HTML mit Deno einzeln verifizierte Quelle pro
Stadt angelegt (Migrationen `20261029000011`–`20261029000014`):

- **Berlin**: berlin.de Ticketseite (`schema_org`, 15 Events, kuratierte
  Highlight-Auswahl, kein vollständiger Berliner Konzertkalender)
- **Frankfurt**: Alte Oper Frankfurt (`scrape`, 10 Events)
- **Wien**: Wiener Konzerthaus (`scrape`, 4 echte Konzerte nach Ausfiltern
  von Führungen/Backstage-Terminen)
- **Hamburg**: Hamburgische Staatsoper inkl. Philharmonisches
  Staatsorchester Hamburg (`scrape`, 25 Termine)
- **Berlin (2)**: Komische Oper Berlin (`scrape`, 35 Termine — bisher
  größte Einzelquelle)
- **Wien (2)**: Volksoper Wien (`scrape`, 27 Termine, 0 Parse-Fehler)

Jede dieser sechs Quellen brauchte handgebaute, gegen die echte
Seitenstruktur getestete CSS-Selektoren (wie schon bei den 10 Münchner
Scrape-Quellen) plus in Summe vier additive, durch die bestehende
Testsuite (`ingest-source/`, weiterhin 5/5 grün) abgesicherte Erweiterungen
von `parseFlexibleDate()` in `parsers/scrape.ts` für bis dahin nicht
unterstützte Datums-/Zeitformate.

**Bewusst ausgenommen wegen robots.txt** (`User-agent: ClaudeBot /
Disallow: /`, unabhängig vom technisch gesendeten User-Agent respektiert):
Elbphilharmonie & Laeiszhalle, Wiener Staatsoper, Theater an der Wien.

**Geprüft, aber technisch nicht umsetzbar mit dem bestehenden
single-page-`scrape`/`schema_org`-Connector** (bräuchten entweder
JS-Rendering — die Seite liefert ohne Browser keinen befüllten HTML-Body —
oder Mehrseiten-Crawling — Events liegen auf vielen Einzelseiten statt
einer Listing-Seite): Wiener Musikverein, Konzerthaus Berlin, Berliner
Philharmoniker, Staatsoper Unter den Linden, Deutsche Oper Berlin,
Oper Frankfurt, hr-Sinfonieorchester, Ensemble Resonanz, Ensemble Modern,
Kampnagel, Pierre Boulez Saal. ORF RSO Wien: die in der Quellenliste
genannte URL (`rso.orf.at/konzerte/`) existiert nicht mehr (404).

Jede neue Quelle bleibt laut `docs/10-legal-status.md` rechtlich ungeprüft
(so vermerkt in ihrem `legal_basis`-Feld). Reale Volumina liegen bei 4–35
Terminen pro Quelle zum Zeitpunkt der Erstellung — weit von Münchens ~900
entfernt, die aus 10 einzeln über Wochen gebauten Quellen stammen. Um die
oben als "technisch nicht umsetzbar" markierten JS-lastigen Seiten
(die Mehrheit der großen Häuser) doch noch zu erschließen, bräuchte es
entweder eine Ingestion-Architektur-Erweiterung um echtes
Browser-Rendering (z.B. Headless-Chrome-Fetch statt plain HTTP-GET) oder
Mehrseiten-Crawling — beides eine größere, hier nicht umgesetzte
Folgeänderung, kein reiner Config-Eintrag mehr wie bei den sechs
bestehenden Quellen.
