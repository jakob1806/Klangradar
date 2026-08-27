# Stadt-Erweiterung: Import Berlin, Hamburg, Frankfurt, Wien

Stand: 2026-08-26. Dokumentiert den Import aus `Klangradar_Stadtkatalog_Import.xlsx`
(kuratierte Recherche, Stand 26.08.2026) in die Migrationen
`20261101000010`–`20261101000014`.

## Umfang

128 Personen, 128 Ensembles, 128 Venues (je 32 pro Stadt: Berlin, Hamburg,
Frankfurt am Main, Wien) plus 92 Aliase (von 384 in der Quelldatei — 292
waren reine Duplikate des kanonischen Namens, siehe unten). Erweitert den
bisher auf München fokussierten Scope (siehe README) auf vier weitere
Städte — explizite Produktentscheidung, nicht nur ein Datenimport.

## Trennung nach Städten

Jede Stadt hat eine eigene Migrationsdatei
(`20261101000011_city_import_berlin.sql` usw.), damit ein Fehler oder eine
nötige Korrektur in den Daten einer Stadt isoliert behoben/zurückgerollt
werden kann, ohne die anderen drei anzufassen. `regions`-Migration
(`20261101000010`) legt für jede Stadt eine eigene `country → state → city`
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
**`20261101000015_activate_city_expansion.sql` schaltet sie dennoch live** —
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

## `home_venue_id`-Backfill (`20261101000016_backfill_home_venues.sql`)

Die Quelldatei ließ `home_venue_slug` für **alle 128 Ensembles** leer.
`20261101000016` trägt das für **18 Ensembles** nach — bewusst nur die
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

Seit `20261029000020`/`20261029000021` filtern zusätzlich Suche
(`search_all`) und Home-Feed (`recommended_events`, das regelbasierte
"Für dich"-Modul) über denselben `selectedCityRegionProvider` — beide
lesen die auf der Karte getroffene Stadt-Auswahl mit, kein eigener
UI-Umschalter auf diesen Screens nötig. `favorite_events_home()`/
`followed_events()` (rein persönliche Rails: gefolgte Personen/Venues/
Ensembles) und `discovery_events()` bleiben bewusst UNGEFILTERT — eine
gefolgte Person kann in jeder Stadt auftreten, ein Stadt-Filter würde dort
eher Ergebnisse verstecken als helfen.

Seit `0d8792c` filtert zusätzlich der Kalender (Monats- und
Agenda-Ansicht, `calendar_providers.dart`) über denselben Provider —
direkte PostgREST-Query auf `events` mit `venues!inner(...)` +
`.eq('venues.region_id', ...)` statt einer RPC-Änderung. Damit filtern
jetzt alle vier Haupt-Screens (Karte, Suche, Home, Kalender) konsistent
über dieselbe In-Memory-Auswahl.

Seit `8254042` seedet `selectedCityRegionProvider` sich außerdem einmalig
aus `profiles.preferred_region_id` (`preferredCityRegionProvider`), sobald
sie vorliegt und der Nutzer noch keine eigene Auswahl in dieser Session
getroffen hat — vorher wurde dieses beim Onboarding gesetzte Feld nirgends
gelesen.

**Bekannte Einschränkung, nicht behoben:** iOS-native hat noch keinen
Städte-Umschalter (siehe unten) — dort noch offen, weil der Build/Test-
Zyklus laut `ios-native/CLAUDE.md` einen Mac mit Xcode voraussetzt, den
diese Umgebung nicht hat.

## Event-Ingestion — je eine echte Quelle pro Stadt, weiterhin weit von München entfernt

Programme/Events selbst sind nicht Teil dieser Datei — nur Stammdaten
(Personen/Ensembles/Venues). Auf Basis einer vom Nutzer bereitgestellten,
priorisierten Quellenliste (`Klangradar_Konzertquellen_Scraper.xlsx`) wurde
je eine reale, gegen echtes HTML mit Deno einzeln verifizierte Quelle pro
Stadt angelegt (Migrationen `20261101000017`–`20261101000020`):

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

## Reconciliation mit paralleler Codex-Session (`fix/migration-history-reconciliation`, `fix/sources-city-id`)

Eine unabhängig laufende Session hat zeitgleich eine eigene
Städte-Erweiterung gebaut und direkt gegen Produktion gepusht (nie in
`main` gemerged) — mit einer eigenen `city_id`/`city_area_id`-Spalte
(statt der hier verwendeten bestehenden `region_id`), eigenen
city-gefilterten RPCs (`search_all`/`venues_with_latlng`/
`recommended_events`/`popular_events`/`discovery_events`, alle mit
`p_city_id`-Parameter statt `p_region_id`) und 4 handkuratierten
Flaggschiff-Venues+Events (München-Land+neue Städte). `city_id` ist jetzt
die produktiv vollständig befüllte, kanonische Stadt-Spalte (`region_id`
blieb bei einigen älteren Venues leer) — die App (Karte/Suche/Home/
Kalender) und alle 9 Event-Quellen aus diesem Dokument wurden entsprechend
auf `city_id`/`p_city_id` umgestellt. Details zum Konflikt und zur Lösung:
Commit-Messages von `82ea140` (PR #168) und `23dfc2b` (PR #169).

Die 128 Personen/Ensembles/Venues aus diesem Dokument bleiben zusätzlich
zu Codex' 4 Flaggschiff-Venues bestehen (upsert per `slug`, keine
Kollision, da unterschiedliche Slug-Konvention) — echte Namens-Duplikate
(z.B. "Philharmonie Berlin" als eigene Zeile UND als
"Philharmonie Berlin – Großer Saal"/"– Kammermusiksaal" aus diesem Import)
sind ein bekannter, nicht kritischer Nebeneffekt zweier unabhängiger
Importe derselben realen Institutionen — werden von der bestehenden
Venue-Dedup-Review-Queue (`detect_venue_duplicate_candidates`, wöchentlicher
Cron) automatisch zur redaktionellen Prüfung vorgeschlagen, nicht
automatisch gemergt.

### Nachtrag 2026-08-27: Migrationsreihenfolge korrigiert

Der ursprüngliche Zeitstempel-Block (`20261029000003`–`20261029000019`)
lief in einem frischen `migrate-and-seed`-Durchlauf (CI, komplette
Neuaufsetzung nach Dateireihenfolge) VOR Codex' `20261031000002`, das die
`city_id`-Spalte auf `venues` erst anlegt — obwohl er inhaltlich davon
abhängt (`city_id` in allen Venue-/Source-Inserts). In der echten
Produktionshistorie hatte das keine Auswirkung, weil Codex' Migration
bereits direkt (außerhalb dieser Pipeline) lief, bevor dieser Block je
über `supabase db push` angewendet wurde — ein frischer CI-Durchlauf
deckte die eigentliche Abhängigkeit aber sofort auf (Fehler `column
"city_id" of relation "venues" does not exist`). Behoben durch Umbenennen
des gesamten Blocks auf `20261101000010`–`20261101000025` (Inhalt
unverändert), sodass er nach dem vollständigen Codex-Block
(`20261031000001`–`013`) läuft — die Dateien waren zu diesem Zeitpunkt
noch nie erfolgreich über die Deploy-Pipeline auf Produktion angewendet
worden (alle bisherigen `deploy-migrations`-Läufe seit PR #168 blieben in
"waiting"/"cancelled"/"failure" hängen), das Umbenennen war daher
gefahrlos möglich.
