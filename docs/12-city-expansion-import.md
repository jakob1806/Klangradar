# Stadt-Erweiterung: Import Berlin, Hamburg, Frankfurt, Wien

Stand: 2026-08-26. Dokumentiert den Import aus `Klangradar_Stadtkatalog_Import.xlsx`
(kuratierte Recherche, Stand 26.08.2026) in die Migrationen
`20261029000003`–`20261029000007`.

## Umfang

128 Personen, 128 Ensembles, 128 Venues (je 32 pro Stadt: Berlin, Hamburg,
Frankfurt am Main, Wien) plus 384 Aliase. Erweitert den bisher auf München
fokussierten Scope (siehe README) auf vier weitere Städte — explizite
Produktentscheidung, nicht nur ein Datenimport.

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

## `is_active = false` — bewusst nicht sofort live

Alle vier neuen Regionen (Land/Bundesland/Stadt) sind mit `is_active = false`
angelegt, dem bestehenden Feature-Flag-Muster folgend ("München startet als
einzige aktive Region", siehe `20260819000005_regions.sql`). Grund: Die
Quelldatei markiert sich selbst als nicht produktionsreif (QA-Blatt:
"Koordinaten, Kontaktdaten, Barrierefreiheit und Bildrechte vor
Produktivimport vervollständigen"). Freischaltung ist ein separater,
redaktioneller Schritt, sobald die Daten geprüft sind.

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

## Bekannte Lücke: `home_venue_slug`

Die Quelldatei lässt `home_venue_slug` für **alle 128 Ensembles** leer
(`residency_de` verweist stattdessen nur auf die Stadt, z. B. "Berlin;
konkrete Stammspielstätte vor Import über home_venue_slug verknüpfen").
**Dieser Import hat das nicht nachgeholt** — eine Zuordnung "Wiener
Philharmoniker → Musikverein Wien" o. ä. aus allgemeinem Wissen zu raten
wäre riskanter als eine bewusste Lücke, da falsche Verknüpfungen schwerer zu
entdecken sind als fehlende. `ensembles.home_venue_id` ist für alle neu
importierten Ensembles `NULL`. Folge: Diese Ensembles sind aktuell nicht
über `home_venue_id → venues.region_id` einer Stadt zuordenbar — die einzige
Stadt-Zuordnung ist die Datei-/Migrationszugehörigkeit selbst. Empfehlung:
redaktionelle Nachpflege pro Ensemble vor Freischaltung.

## Nicht importiert

Programme/Events selbst sind nicht Teil dieser Datei — nur Stammdaten
(Personen/Ensembles/Venues). Event-Ingestion für diese Städte bräuchte
eigene Quellen (siehe `docs/10-legal-status.md` zur rechtlichen Prüfpflicht
vor jeder neuen Scrape-Quelle).
