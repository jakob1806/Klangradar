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

**Bekannte Einschränkung, nicht behoben:** Weder Backend-Query
(`venues_with_latlng`-RPC) noch App/iOS filtern Venues/Events nach Stadt —
es gibt keinen Regions-/Stadt-Filter irgendwo in der Abfragekette
(`preferred_region_id` wird gespeichert, aber nirgends benutzt). Mit jetzt 5
aktiven Städten zeigt die Karte alle ~165 Venues gleichzeitig; der
Auto-Fit-auf-alle-Venues zoomt entsprechend weit heraus. Ein echter
Stadt-Umschalter (UI + Filter in `search_all`/`filter_events`/Home-Feed-RPCs
etc.) ist eine eigene, größere Funktion und war nicht Teil dieser Änderung.

## Event-Ingestion — nicht umgesetzt

Programme/Events selbst sind nicht Teil dieser Datei — nur Stammdaten
(Personen/Ensembles/Venues). Geprüft: Die großen Häuser (Elbphilharmonie,
Berliner Philharmoniker, Wiener Musikverein, Konzerthaus Berlin, Alte Oper
Frankfurt) bieten weder RSS/iCal noch Schema.org-Event-Markup auf ihren
öffentlichen Seiten (nur `Organization`/`WebSite`-Markup) — genau wie
seinerzeit bei den Münchner Quellen. Echte `scrape`-Connectors bräuchten
pro Venue handgebaute, gegen die echte Seitenstruktur getestete
CSS-Selektoren (wie in `parsers/scrape.ts` für die bestehenden 10
Münchner Scrape-Quellen) — das für 128 Venues blind zu erstellen hätte
nur leere/kaputte Quellen erzeugt, keinen echten Nutzen. Zusätzlich bräuchte
jede neue Quelle laut `docs/10-legal-status.md` eine rechtliche
Einzelprüfung. Event-Ingestion für diese Städte bleibt vollständig offen.
