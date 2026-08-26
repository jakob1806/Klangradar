# Rechtlicher Status vor Veröffentlichung

Dieses Dokument fasst den Stand der rechtlichen Prüfung zusammen (Stand: 2026-08-25).
Es ersetzt keine anwaltliche Beratung — die mit **[ANWALT]** markierten Punkte sind
vor einem öffentlichen Launch von einer auf IT-/Medienrecht spezialisierten Kanzlei
zu prüfen bzw. abzuschließen.

## 1. Scrape-Quellen — rechtlicher Prüfstatus

`docs/06-mvp-plan.md` und `docs/07-roadmap.md` sahen Web-Scraping ursprünglich erst
"nach rechtlicher Einzelprüfung je Quelle" vor. Der generische Scrape-Connector
(`backend/supabase/functions/ingest-source/parsers/scrape.ts`) wurde davon abweichend
bereits produktiv geschaltet und läuft per `pg_cron` täglich automatisiert
(`20260817000005_daily_ingestion_cron.sql`).

**Entscheidung (2026-08-25):** Quellen bleiben aktiv, werden aber hiermit explizit als
rechtlich ungeprüft dokumentiert. Das Risiko (Datenbankschutzrecht §87a-e UrhG,
ToS-Verstöße der Quellseiten, UWG bei Textübernahmen) wird bewusst bis zur
Einzelprüfung in Kauf genommen.

| Quelle | Migration | Übernimmt Bilder? | Rechtlich geprüft? |
|---|---|---|---|
| Gasteig | `20260804000001_gasteig_scrape_source.sql` | **Ja** (`imageSelector` gesetzt) | **[ANWALT]** Nein — zusätzlich Bildrechte (Urheber + KUG §22) klären |
| mphil | `20260806000001_mphil_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| Herkulessaal | `20260807000001_herkulessaal_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| Allerheiligen-Hofkirche | `20260808000001_allerheiligen_hofkirche_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| St. Michael | `20260809000001_st_michael_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| Prinzregententheater | `20260810000001_prinzregententheater_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| Frauenkirche | `20260814000001_frauenkirche_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| Münchener Biennale | `20260817000008_muenchener_biennale_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| Hörtnagel | `20260817000009_hoertnagel_scrape_source.sql` | Nein | **[ANWALT]** Nein |
| Töltzer Knabenchor | `20260830000001_toelzer_knabenchor_scrape_config.sql` | Nein | **[ANWALT]** Nein |

Technische Sorgfaltsmaßnahmen, die bereits umgesetzt sind (siehe `_shared/robots.ts`,
`parsers/scrape.ts`): robots.txt-Prüfung vor jedem Fetch, identifizierender
User-Agent, Crawl-Delay-Beachtung, nur ein Request pro Lauf. Das ersetzt keine
rechtliche Einzelprüfung, reduziert aber das technische Missbrauchsrisiko.

**Besonders dringend:** Gasteig-Bilder — hier kommt zum Datenbankschutzrecht noch
Urheberrecht am Foto und ggf. Recht am eigenen Bild (§22 KUG) der abgebildeten
Personen hinzu. **[ANWALT]** Bis zur Klärung entweder Lizenz einholen oder
`imageSelector` aus der Gasteig-Config entfernen.

## 2. AVV / Auftragsverarbeitung — offene Verträge

**[ANWALT/GESCHÄFTSFÜHRUNG]** Vor Launch abzuschließen, nicht durch Code lösbar:

- **Supabase** (Postgres-Hosting, Auth, Storage): AVV mit Supabase Inc. prüfen/abschließen.
  Region des Supabase-Projekts (EU vs. US) für die Datenschutzerklärung dokumentieren.
- **Firebase Cloud Messaging / Google**: AVV bzw. Data Processing Terms mit Google
  abschließen (Teil der Firebase-Nutzungsbedingungen, muss aktiv akzeptiert/dokumentiert
  werden). Drittlandtransfer USA → Standardvertragsklauseln (SCCs) prüfen.
- **Sign in with Apple / Google** (vorbereitet, noch nicht aktiv): sobald aktiviert,
  jeweilige Datenverarbeitung in der Datenschutzerklärung ergänzen.

Bis diese AVVs vorliegen, ist die in `docs/legal/datenschutzerklaerung.md` verlinkte
Auftragsverarbeiter-Liste als **Entwurf** zu behandeln.

## 3. Nutzerseitige Rechtstexte

Datenschutzerklärung, AGB und Impressum wurden als **Entwürfe** unter `docs/legal/`
angelegt und im Onboarding (`app/lib/features/onboarding/presentation/onboarding_screen.dart`)
verlinkt (vorher zeigten die Checkboxen auf nichts). **[ANWALT]** Alle drei Dokumente
müssen vor Launch anwaltlich geprüft und mit den tatsächlichen Unternehmensdaten
(Anbieter, Anschrift, Vertretungsberechtigte, USt-ID etc.) vervollständigt werden —
aktuell sind Platzhalter wie `[FIRMENNAME]` enthalten.
