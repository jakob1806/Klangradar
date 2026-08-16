# 08 – Home-Feed: Empfehlungsalgorithmus & redaktionelles Kuratieren

> **Umsetzungsstatus (2026-08-16):** Phase A und Phase B (Abschnitt 10) sind
> vollständig umgesetzt — alle 9 Module aus Abschnitt 3 laufen live
> (inkl. Hero-Personalisierung, "Dein Ort/Ensemble hat Neuigkeiten",
> Saisonal/Festival), Diversitätsregeln 1–4 aus Abschnitt 5 sind aktiv,
> Ticketklick-/Verweildauer-Tracking läuft im Client. Details:
> `backend/supabase/migrations/20261016000009_home_feed_phase_b.sql`,
> `app/lib/features/home/application/home_providers.dart`. Zwei bewusste
> Abweichungen vom Entwurf: (1) `profile_interest_ensembles` aus Abschnitt 9
> wurde NICHT angelegt — Ensemble-Interesse existiert bereits als
> `user_favorite_ensembles` seit dem MVP; (2) Ticketklick-/Verweildauer-
> Signale sind keine eigenen additiven Summanden, sondern zusätzliche
> Evidenz für die bestehenden Venue-/Personen-/Ensemble-Interesse-Signale
> (siehe Kommentar in der Migration). Diversitätsregel 5 (Greedy-MMR-
> Re-Ranking) und die `home_feed_modules`-Konfigurationstabelle (Abschnitt
> 9, macht neue Module deploy-frei) sind bewusst NICHT gebaut — beide sind
> Verfeinerungen ohne unmittelbaren Nutzerwert bei der aktuellen Modulzahl
> (9 fest codierte Module wie bisher), nicht Blocker für ein vollständiges
> Kuratieren. Phase C (Abschnitt 8/10, ML-Ranking, zweite Stadt) bleibt wie
> geplant zurückgestellt. Das Festival-Modul ist technisch live, aber
> praktisch noch inaktiv: die einzige `festivals`-Zeile ("Münchner
> Opernfestspiele") hat noch kein `start_date`/`end_date` gesetzt — das ist
> jetzt eine redaktionelle Aufgabe (`/festivals` im Admin-Dashboard), keine
> Code-Aufgabe.

Ziel: der Home-Feed wird von einer festen Abfolge generischer Event-Listen
(Ist-Zustand) zu einem täglich frischen, personalisierten "digitalen
Kulturmagazin" — kuratiert wie Spotifys Startseite, nicht durchsucht wie
die Suche (die bleibt unverändert der Ort für gezieltes Finden).

Dieses Dokument ist ein **Entwurf**, keine fertige Spezifikation — vor der
Umsetzung sollten insbesondere Abschnitt 9 (Datenmodell) und der
Phasenplan in Abschnitt 10 mit dem Team abgestimmt werden.

## 0. Ausgangslage (Ist-Zustand)

Was heute schon existiert und worauf dieser Entwurf aufbaut:

- **Home-Feed** (`app/lib/features/home/`): sechs feste Sektionen in fixer
  Reihenfolge — Hero ("Empfehlung des Tages"), Heute in München, Beliebte
  Veranstaltungen, Empfehlungen für dich, Demnächst ausverkauft, Kostenlose
  Konzerte, Neue Veranstaltungen. Keine Personalisierung der Reihenfolge
  selbst, kein Storytelling zwischen den Sektionen.
- **`recommended_events()`** (SQL-Funktion, siehe
  `20260730000001_recommended_events_visited_venues.sql`): ein einzelnes,
  bereits funktionierendes Scoring — Genre-Interesse (+5), Venue-Interesse
  oder schon besucht (+3), Komponist/Mitwirkende-Interesse (+4),
  Popularität (Favoriten × 0.5), zeitlicher Abschlag (Tage bis zum Event /
  30). Das ist der Kern von Abschnitt 4 unten, nur noch nicht modular
  genug für mehrere Module mit unterschiedlicher Gewichtung.
- **Interessens-Onboarding** (`profile_interest_genres/persons/venues`,
  siehe `20260722000001_profile_interests.sql`): Nutzer:innen wählen beim
  Onboarding und im Profil explizite Interessen — die Grundlage für
  Cold-Start (Abschnitt 6) ist also schon da.
- **Verhaltensdaten, die schon getrackt werden**: `favorites`,
  `event_views` (nur Zeitpunkt, keine Verweildauer), `search_history`. Was
  **fehlt**: Ticketklick-Tracking und Verweildauer — siehe Abschnitt 9.
- **Embeddings + Vektorsuche** (`20260819000009_embeddings.sql`):
  `events.embedding vector(768)` (Gemini text-embedding-004) mit
  HNSW-Index und einer fertigen `find_similar_events_by_embedding()`-RPC.
  **Das ist die wichtigste unterschätzte Ressource für diesen Entwurf** —
  echte inhaltliche Ähnlichkeit ("weil du dieses Konzert angesehen hast,
  interessiert dich vielleicht...") ist technisch schon lauffähig, keine
  ML-Zukunftsmusik. Aktuell nirgends im Home-Feed genutzt.
- **`regions`-Tabelle** (`20260819000005_regions.sql`): hierarchisch
  (country → state → city), mit `is_active`-Flag. Genau der Hook, den
  Abschnitt 7 (Skalierung) braucht — existiert schon, wird nur noch nicht
  vom Home-Feed genutzt (der ist aktuell hart auf München verdrahtet, z.B.
  der Home-Screen-Titel "München" in `home_screen.dart`).

## 1. Leitidee: Kulturmagazin statt Eventliste

Der Feed erzählt jeden Tag eine kurze redaktionelle Geschichte statt eine
Liste abzuspulen:

> "Heute Abend: 3 Konzerte in deiner Nähe · Diese Woche entdecken:
> Ensemble X spielt zum ersten Mal in München · Dein Lieblingsort
> Isarphilharmonie hat 2 neue Termine · Bald ausverkauft: Mahler mit dem
> BRSO"

Konkret heißt das:

- Jedes Modul hat einen **redaktionellen Titel mit Begründung**, nicht nur
  eine Kategorie: "Weil du Bach hörst" statt "Empfehlungen", "Isarphilharmonie
  hat Neuigkeiten" statt "Neue Veranstaltungen an deinem Lieblingsort".
- Der Hero-Bereich ist eine **einzelne, redaktionell starke Auswahl**, kein
  reiner Zufallstreffer — siehe Scoring in Abschnitt 4.
- Modul-Reihenfolge und -Auswahl variieren **pro Nutzer:in und pro Tag**
  (Abschnitt 2), damit der Feed sich nicht wie eine statische Seite anfühlt.

## 2. Architektur: Pipeline statt einer großen Abfrage

Der aktuelle Ansatz (eine SQL-Funktion pro Modul) skaliert nicht auf
mehrere Module mit unterschiedlicher Gewichtung, Diversitätsregeln und
später ML-Ranking. Vorschlag: eine klar getrennte Pipeline, bei der jede
Stufe unabhängig austauschbar ist.

```
1. Candidate Generation   — pro Modul: hole einen groben Kandidatenpool
                             (z.B. "alle Events in den nächsten 14 Tagen
                             in der aktiven Region", "alle Events mit
                             Ähnlichkeits-Embedding zu zuletzt
                             angesehenen Events")
2. Feature Enrichment      — reichere Kandidaten mit den Signalen aus
                             Abschnitt 4 an (Interesse, Popularität,
                             Distanz, Aktualität, Embedding-Ähnlichkeit)
3. Scoring                 — pro Modul eigene Gewichtung derselben
                             Signale (Abschnitt 4)
4. Diversification/Dedup   — Anti-Monotonie-Regeln (Abschnitt 5),
                             modulübergreifend: ein Event erscheint pro
                             Feed-Aufruf nur in EINEM Modul
5. Module Assembly         — Reihenfolge der Module festlegen
                             (Abschnitt 2), redaktionelle Titel generieren
6. Editorial Overlay       — Modul-Titel/Begründungstexte, saisonale
                             Sonderplatzierungen (Abschnitt 4.4)
```

**Wo läuft was, jetzt vs. später:**

| Stufe | Jetzt (Postgres) | Später (bei Bedarf) |
|---|---|---|
| Candidate Generation | SQL, `region_id`-gefiltert | unverändert |
| Feature Enrichment | SQL-Subqueries (wie heute) | Materialized View pro Nutzer:in (Batch-Refresh) bei mehr Last |
| Scoring | eine parametrisierte SQL-Funktion pro Modul-Typ (Abschnitt 4) | gelernte Ranking-Funktion (Abschnitt 8) |
| Diversification | Client-seitig beim Zusammensetzen der Module (Dart) oder eine finale SQL-Stufe | unverändert, nur mit mehr Modulen |
| Module Assembly | `home_providers.dart`, ein Provider pro Modul + ein Orchestrator | unverändert |

Wichtig: **kein Wechsel auf eine externe Recommendation-Engine nötig**,
solange der Katalog im vierstelligen Event-Bereich bleibt (aktuell ~280
Events, siehe [[project_performance_hardening_deferred]] zur selben
Einschätzung bei anderen Systemen dieser App). Postgres mit den
vorhandenen Indizes reicht für Jahre.

## 3. Modul-Reihenfolge

Fixe Regeln, aber die tatsächliche Modul-*Auswahl* pro Tag ist dynamisch
(ein Modul mit leerem/schwachem Kandidatenpool wird übersprungen statt
leer angezeigt):

1. **Hero** — die eine stärkste Empfehlung des Tages (höchster
   personalisierter Score, siehe 4.1), immer vorhanden.
2. **Heute/Morgen in [Stadt]** — reine zeitliche Dringlichkeit, ungefiltert
   nach Geschmack (auch für Cold-Start sofort nützlich).
3. **Für dich** (bzw. "Weil du X hörst") — das personalisierte
   Kern-Modul, Scoring wie in 4.1, nur bei ausreichend Signal (siehe
   Cold-Start-Stufen in Abschnitt 6) — sonst übersprungen zugunsten von
   Modul 4.
4. **Entdecken** (Discovery/Serendipity) — bewusst NICHT nach Geschmack
   gefiltert, siehe 4.3. Direkt nach "Für dich", damit der Feed nicht nur
   das Bekannte verstärkt.
5. **Dein Ort/Ensemble hat Neuigkeiten** — kontextuelle Module, die aus
   `profile_interest_venues`/`_persons` + neu gefundenen Events derselben
   Entität gespeist werden ("Isarphilharmonie hat 2 neue Termine").
   Nur wenn es tatsächlich Neues gibt seit dem letzten Feed-Aufruf.
6. **Bald ausverkauft** — Dringlichkeit/FOMO, wie heute.
7. **Saisonal/Festival** — nur wenn ein aktives Festival/Saison-Fenster
   existiert (Abschnitt 4.4), sonst übersprungen.
8. **Kostenlose Konzerte** — wie heute, niedrige Priorität (Nische statt
   Kernangebot).
9. **Beliebt gerade in [Stadt]** — reine Popularität als Fallback/Füller,
   ans Ende, weil am wenigsten personalisiert.

Für **wiederkehrende Nutzer:innen am selben Tag** (App zweimal geöffnet):
Hero und "Für dich" bleiben stabil (kein Nachladen bei jedem App-Start
nötig — vermeidet ein "flackerndes" Gefühl), aber ein Leichtgewichts-Refresh
für "Heute" und "Bald ausverkauft" (echte Dringlichkeit ändert sich
untertägig).

## 4. Scoring-Modell

### 4.1 Basissignale (gemeinsame Formel-Bausteine)

| Signal | Quelle (existiert/neu) | Gewicht-Vorschlag | Bemerkung |
|---|---|---|---|
| Genre-Interesse | `profile_interest_genres` (existiert) | 5 | wie heute |
| Venue-Interesse / besucht | `profile_interest_venues`, `event_views` (existiert) | 3 | wie heute |
| Komponist/Mitwirkende-Interesse | `profile_interest_persons`, `event_participants` (existiert) | 4 | wie heute |
| **Ensemble-Interesse** | `profile_interest_venues`-Pendant für Ensembles — **fehlt**, siehe 9 | 4 | aktuell nur Personen abgedeckt, nicht Ensembles/Chöre separat |
| Popularität | `favorites`-Anzahl (existiert) | 0.5 pro Favorit, **log-skaliert** (siehe unten) | heute linear — bei wachsendem Katalog sollte das log(1+n) sein, sonst dominieren wenige virale Events alles |
| Ticketklick-Signal | **fehlt**, siehe 9 | 2 (stärker als reine Ansicht) | ein Klick auf "Tickets" ist ein stärkeres Intent-Signal als ein Seitenaufruf |
| Verweildauer auf Event-Detail | **fehlt**, siehe 9 | 0–2, gestaffelt | >15s = echtes Interesse, <3s = wahrscheinlich Fehlklick |
| Geografische Nähe | `venues.location` (existiert, PostGIS) | −0.3 pro km über 5 km | nur wenn Standortfreigabe vorliegt, sonst neutral (kein Malus) |
| Zeitliche Abwertung | wie heute | −(Tage bis Event)/30 | unverändert gut |
| **Embeddings-Ähnlichkeit** zu zuletzt gesehenen/favorisierten Events | `find_similar_events_by_embedding()` (existiert!) | eigenes Modul (4.3), nicht Teil der additiven Summe | siehe unten — verdient ein eigenes Modul statt nur ein Summand zu sein |

**Log-Skalierung der Popularität:** `0.5 * ln(1 + favorite_count)` statt
`0.5 * favorite_count` — verhindert, dass ein einzelnes virales Event
(z.B. eine Promi-Ankündigung) alle anderen Signale in der Summe erschlägt.
Bei aktuell kleinem Katalog kaum spürbar, wird aber wichtig, sobald die
App wächst — lieber jetzt einbauen als später migrieren.

### 4.2 Pro-Modul-Gewichtung (dasselbe Signal-Set, andere Gewichte)

Der Fehler, den man hier vermeiden will: **ein** globaler Score für alle
Module macht jedes Modul zur selben Liste in anderer Verpackung. Jedes
Modul bekommt eine eigene Gewichts-Konfiguration über dieselben Signale:

- **"Für dich"**: volle Gewichtung aller Interessens-Signale, Popularität
  niedrig gewichtet (0.2× statt 0.5×) — es geht um *diese* Person, nicht
  um den allgemeinen Trend.
- **"Beliebt gerade in München"**: fast nur Popularität + Aktualität,
  Interessens-Signale komplett aus.
- **"Bald ausverkauft"**: `remaining_tickets_status` als harter Filter,
  danach dieselbe Sortierung wie "Für dich".
- **Hero**: wie "Für dich", aber zusätzlich ein Bonus für Events mit Bild
  (`image_urls` nicht leer — ein Hero ohne echtes Bild wirkt unfertig) und
  einen kleinen Malus, falls dasselbe Event/derselbe Ort in den letzten 3
  Tagen schon Hero war (siehe Anti-Monotonie, Abschnitt 5).

Technisch: **eine** parametrisierte SQL-Funktion
`score_events(p_user_id, p_weights jsonb, p_candidate_ids uuid[])` statt
einer Kopie pro Modul — die Gewichte kommen als JSONB-Parameter rein,
die Modul-Definitionen (Gewichte + Kandidatenquelle) leben in einer
kleinen Konfigurationstabelle (Abschnitt 9), nicht hartkodiert im SQL.
Das ist der Hebel, der "modular und skalierbar" tatsächlich einlöst: neue
Module = neue Zeile in der Konfigurationstabelle, kein Code-Deploy.

### 4.3 Discovery/Serendipity als eigenes Modul

Bewusst **kein** Summand in der normalen Score-Formel, sondern ein
eigener Kandidaten-Pool mit eigener Logik:

- Ausgangspunkt: die letzten 3–5 favorisierten/lange angesehenen Events
  der Person.
- `find_similar_events_by_embedding()` auf jedes davon anwenden →
  Kandidaten sammeln.
- **Explizit herausfiltern**, was zu ähnlich zu den *bereits bekannten*
  Interessen ist (z.B. schon favorisierte Komponisten/Venues) — das Ziel
  ist NEUES, nicht eine Bestätigung des Bekannten. Konkret: Kandidaten
  ausschließen, bei denen Komponist UND Venue UND Ensemble bereits alle
  drei in den expliziten Interessen stehen.
- Ergebnis: "Weil du [Werk/Komponist] gehört hast, könnte dich das hier
  interessieren" — mit einem neuen Ensemble/Veranstalter/Genre, das die
  Person noch nicht kennt.

Das ist der Abschnitt, der am direktesten von der schon vorhandenen
Embeddings-Infrastruktur profitiert — technisch heute schon baubar.

### 4.4 Saisonale Ereignisse & Festivals

`festivals`-Tabelle (existiert) bekommt ein aktives Zeitfenster
(`start_date`/`end_date` — aktuell nicht vorhanden, siehe 9). Ein Cron/
Scheduled-Check aktiviert ein "Festival"-Modul automatisch, sobald
`now()` in diesem Fenster liegt, ohne manuelles redaktionelles Eingreifen.
Für wiederkehrende saisonale Muster ohne eigene Festival-Entität (z.B.
"Adventskonzerte" im Dezember) reicht vorerst ein einfacher, im Code
gepflegter Kalender fester Zeiträume — kein Over-Engineering für ein
Feature, das vielleicht 4–5× im Jahr greift.

## 5. Anti-Monotonie / Diversitätsregeln

1. **Kein Event doppelt im selben Feed-Aufruf** — ein Event, das schon in
   einem höher priorisierten Modul gezeigt wurde, wird aus den
   Kandidatenpools aller nachfolgenden Module entfernt (Set-Differenz
   nach Modul-Reihenfolge aus Abschnitt 3).
2. **Max. 2 Events desselben Venues pro Modul** (außer das Modul ist
   explizit venue-bezogen wie "Dein Ort hat Neuigkeiten") — verhindert,
   dass z.B. das Prinzregententheater (aktuell mit Abstand die meisten
   Events, siehe Datenqualitäts-Recherche) ganze Module dominiert.
3. **Max. 1 Event desselben Komponisten pro Modul**, außer bei einem
   explizit komponisten-zentrierten Modul.
4. **Sliding-Window gegen Tag-zu-Tag-Wiederholung**: ein `shown_impressions`-
   Log (Abschnitt 9) hält fest, was einer Person in den letzten N Tagen
   bereits im Hero/"Für dich"-Modul gezeigt wurde — dieselbe Auswahl darf
   dort 7 Tage lang nicht wiederholt werden (in "Bald ausverkauft" schon,
   weil sich der Dringlichkeitsgrund ändert).
5. **Re-Ranking statt reinem Sortieren** für Module mit >1 Kandidat pro
   "Slot"-Typ: ein einfaches Greedy-MMR-Verfahren (Maximal Marginal
   Relevance) — wähle das nächste Element nicht nur nach Score, sondern
   nach `score − λ × Ähnlichkeit_zum_bereits_Gewählten` (Ähnlichkeit über
   Embeddings oder einfach "gleiches Genre/Venue"). Verhindert, dass ein
   Modul aus 6 fast identischen Kirchenmusik-Terminen besteht, nur weil
   die alle hoch scoren.

## 6. Cold-Start-Strategie

Gestaffelt nach vorhandenem Signal, keine Alles-oder-nichts-Schwelle:

| Stufe | Bedingung | Strategie |
|---|---|---|
| **0 — Anonym/vor Onboarding** | kein Account | Reihenfolge aus Abschnitt 3 ohne "Für dich"/Discovery-Personalisierung — nur Heute, Beliebt, Ausverkauft, Kostenlos, Neu (genau der heutige Zustand als Fallback, nicht als Ziel) |
| **1 — Nach Onboarding, keine Historie** | `profile_interest_*` gefüllt, aber `event_views`/`favorites` leer | "Für dich" läuft NUR mit den expliziten Interessen (Gewichte aus 4.1, aber ohne Popularitäts-/Verhaltens-Anteil) — sofort relevant, ohne auf Verhalten warten zu müssen |
| **2 — Erste Sitzungen** | 1–4 `event_views` oder 1. Favorit | Verhaltenssignale beginnen einzufließen, aber mit reduziertem Gewicht (z.B. ×0.3) gegenüber expliziten Interessen — ein einzelner zufälliger Klick soll das Profil nicht überproportional prägen |
| **3 — Etabliert** | ≥5 Interaktionen (Views/Favoriten/Ticketklicks kombiniert) | volle Gewichtung wie in 4.1/4.2 |

Zusätzlich: das **Onboarding selbst** (Interessens-Picker, existiert
schon) ist der wichtigste Cold-Start-Hebel und sollte einen
geografischen Schritt bekommen, falls noch nicht vorhanden ("Wo bist du
meistens unterwegs?") — nötig, sobald Abschnitt 7 mehr als eine Stadt
umfasst, aber auch innerhalb Münchens nützlich für den Distanz-Malus in
4.1.

Für Stufe 0/1 gilt: Discovery-Modul (4.3) braucht mindestens ein
"Anker-Event" (angesehen oder favorisiert) — ohne das wird es einfach
durch "Beliebt" ersetzt, kein Sonderfall im Code nötig.

## 7. Architektur für geografische Erweiterung

Die `regions`-Tabelle ist der zentrale Hook — der Home-Feed sollte von
Anfang an `region_id`-parametrisiert sein, auch während er faktisch nur
für München (`is_active = true`) läuft:

- **Candidate Generation** (Abschnitt 2, Stufe 1) filtert immer zuerst
  nach `venues.region_id = p_region_id` (`venues` braucht dafür ein
  `region_id`-Fremdschlüsselfeld — aktuell nicht vorhanden, siehe 9,
  da `venues.address_city` bisher als String geführt wird statt über
  `regions` verknüpft).
- **Auswahl der aktiven Region pro Nutzer:in**: aus dem Profil-Standort
  (falls Standortfreigabe vorliegt) oder explizit gewählt (Städte-Auswahl
  in den Einstellungen, wie bei vielen Ticketing-Apps) — Fallback auf die
  einzige `is_active = true`-Region, solange es nur München gibt.
- **Kein Code-Wechsel bei einer zweiten Stadt** — nur: neue `regions`-Zeile
  mit `is_active = true`, neue Venues/Sources mit passender `region_id`,
  fertig. Die gesamte Pipeline (Abschnitt 2) bleibt unverändert, weil sie
  von Anfang an regionsparametrisiert ist.
- **Länderübergreifend** (z.B. Expansion nach Österreich/Schweiz):
  `regions.type = 'country'` existiert schon als Konzept — `locale` und
  `timezone` pro Region sind ebenfalls schon im Schema vorgesehen. Der
  einzige zusätzliche Aufwand ist die deutschsprachige Konsistenz der
  KI-Extraktion (bereits deutschsprachig ausgelegt) für andere
  Länder/Sprachen — das betrifft die Ingestion-Pipeline, nicht den
  Home-Feed-Algorithmus selbst.

## 8. Machine-Learning-Personalisierung: Ausblick

Kein Grund, jetzt ein ML-Team aufzubauen — bei ~280 Events und einer noch
kleinen Nutzerbasis liefert das regelbasierte Scoring (Abschnitt 4) einen
Großteil des Werts, den ein gelerntes Modell liefern würde, ohne dessen
Kosten (Trainingsdaten, Infrastruktur, Erklärbarkeit). Trotzdem lohnt sich
ein Phasenplan, damit die Datenerhebung (Abschnitt 9) schon JETZT so
passiert, dass sie später ein Modell trainieren kann:

1. **Phase 0 (jetzt)**: regelbasiertes Scoring (Abschnitt 4) +
   Embeddings-basierte Ähnlichkeit (existiert schon) für das
   Discovery-Modul. Kein ML-Training nötig, nur die Nutzung bestehender
   Infrastruktur.
2. **Phase 1 (sobald genug Interaktionsdaten vorliegen, grobe Faustregel:
   einige zehntausend Events aus Abschnitt 9 protokolliert)**: ein
   einfaches gelerntes Ranking-Modell (Logistic Regression oder Gradient
   Boosting, z.B. LightGBM) ersetzt die *Gewichte* aus 4.1/4.2 — die
   Features bleiben dieselben, nur die Kombination wird gelernt statt von
   Hand festgelegt. Läuft off-App als Batch-Job (z.B. täglich neu
   trainiert), das Ergebnis ist weiterhin nur eine Gewichtungstabelle, die
   `score_events()` konsumiert — kein Realtime-Inferenz-Server nötig.
3. **Phase 2**: Collaborative Filtering ("Nutzer:innen mit ähnlichem
   Geschmack mochten auch...") — braucht eine kritische Masse an
   Nutzer:innen mit überlappenden Interaktionen, für eine Nischen-App wie
   diese realistisch erst nach deutlichem Wachstum (mehrere tausend aktive
   Profile) sinnvoll. Bis dahin: nicht bauen (gleiche Logik wie die
   bewusst zurückgestellte Performance-Härtung, siehe
   [[project_performance_hardening_deferred]]).
4. **Phase 3**: Embeddings nicht nur für Ähnlichkeit, sondern als
   Feature in einem gelernten Modell (z.B. Cosine-Similarity zum
   Nutzer:innen-"Interessens-Embedding", gebildet als Durchschnitt der
   Embeddings favorisierter Events) — eine elegante Erweiterung, sobald
   Phase 1 etabliert ist, aber kein Blocker davor.

## 9. Nötige Datenmodell-Ergänzungen

Neu anzulegen (in etwa dieser Priorität):

```sql
-- Ticketklicks — fehlt komplett, aber explizit vom Nutzer gewünschtes Signal
create table ticket_clicks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  event_id uuid references events(id) not null,
  clicked_at timestamptz not null default now()
);

-- Verweildauer — event_views existiert, aber ohne Dauer
alter table event_views add column duration_seconds int;

-- Ensemble-Interesse — Personen sind abgedeckt, Ensembles/Chöre nicht separat
create table profile_interest_ensembles (
  user_id uuid references auth.users(id) not null,
  ensemble_id uuid references ensembles(id) not null,
  primary key (user_id, ensemble_id)
);

-- Impression-Log gegen Tag-zu-Tag-Wiederholung (Abschnitt 5.4)
create table home_feed_impressions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) not null,
  event_id uuid references events(id) not null,
  module_key text not null,
  shown_at timestamptz not null default now()
);

-- Modul-Konfiguration statt hartkodierter Gewichte (Abschnitt 4.2)
create table home_feed_modules (
  key text primary key,
  weights jsonb not null,
  candidate_source text not null, -- z.B. 'interest_scored', 'embedding_similarity', 'popularity'
  min_candidates int not null default 3, -- darunter: Modul wird übersprungen
  sort_order int not null,
  is_active boolean not null default true
);

-- Venues an regions anbinden statt nur als String (Abschnitt 7)
alter table venues add column region_id uuid references regions(id);

-- Festival-Zeitfenster für automatische Modul-Aktivierung (Abschnitt 4.4)
alter table festivals add column start_date date;
alter table festivals add column end_date date;
```

`ticket_clicks`/`event_views.duration_seconds` brauchen ein Tracking im
Client (`app/lib/core/events/` bzw. wo Ticket-Links aktuell geöffnet
werden) — aktuell öffnet der Ticket-Button vermutlich direkt per
`url_launcher` ohne Zwischen-Logging, das müsste ergänzt werden.

## 10. Umsetzungsplan (Phasen)

**Phase A — ohne neue Infrastruktur, größter Sofort-Nutzen:**
- Modul-Reihenfolge nach Abschnitt 3 umsetzen (reine Client-/SQL-Änderung)
- Log-Skalierung der Popularität (Ein-Zeilen-Änderung in
  `recommended_events()`)
- Diversitätsregeln 1–3 aus Abschnitt 5 (Set-Differenz + Venue/Komponist-
  Obergrenze — reine SQL/Dart-Logik, kein neues Schema)
- Discovery-Modul (4.3) auf Basis der schon vorhandenen
  `find_similar_events_by_embedding()`-RPC — das ist der höchste
  Wert-pro-Aufwand-Posten in diesem ganzen Dokument, weil die Infrastruktur
  schon da ist und nur noch nicht im Home-Feed verwendet wird

**Phase B — braucht die neuen Tabellen aus Abschnitt 9:**
- Ticketklick- und Verweildauer-Tracking im Client + Backend
- `home_feed_modules`-Konfigurationstabelle (macht neue Module
  deploy-frei)
- Impression-Log + Sliding-Window-Regel (5.4)
- `venues.region_id` + Cold-Start-Stufe 1 mit Standort-Frage im Onboarding

**Phase C — erst bei belastbarer Datenmenge:**
- Gelerntes Ranking-Modell (Abschnitt 8, Phase 1)
- Zweite Stadt/Region live schalten (Abschnitt 7 ist dann schon bereit)

Bewusst NICHT in diesem Plan: Collaborative Filtering, ein eigener
Recommendation-Microservice, Realtime-Feature-Store — all das wäre bei
der aktuellen Größe der App (~280 Events, Nischenpublikum in einer Stadt)
Aufwand ohne proportionalen Nutzen, im selben Sinne wie die bereits
zurückgestellte Performance-Härtung und der Playwright-Crawler (siehe
[[project_performance_hardening_deferred]], [[project_playwright_crawler_deferred]]).
