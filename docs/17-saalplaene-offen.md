# Saalpläne – offene Punkte (Stand 08.11.2026)

Saalpläne werden je Spielstätte in `venues.seating_plan_url` gepflegt
(Admin: Spielstätte bearbeiten → „Saalplan“, Übersicht unter `/saalplaene`).
In der App erscheinen sie unten auf der Spielstättenseite und im Ticket-Blatt
(„Mein Platz im Saalplan“). Bilder (JPG/PNG/WebP) öffnen in der App mit Zoom,
PDFs und Webseiten im Browser.

## Bisher eingetragen (Migration 162, nur Links, ungeprüft)

| Spielstätte | Quelle | Problem |
|---|---|---|
| Isarphilharmonie | Saalplan-Seite der Münchner Philharmoniker (Webseite) | kein Bild, öffnet im Browser |
| Nationaltheater | Saalplan-Übersicht der Staatsoper (Webseite) | kein Bild, Seite blockt automatische Abrufe (403) |
| Prinzregententheater | Staatsoper-PDF Spielzeit 2021/22 | veraltet (Preise, ggf. Aufteilung) |
| Cuvilliés-Theater | Staatsoper-PDF Spielzeit 2021/22 | veraltet |

## Fehlt noch (bitte als Bild hochladen)

- Isarphilharmonie – aktueller Plan als Bild
- Nationaltheater – aktueller Plan als Bild
- Prinzregententheater, Cuvilliés-Theater – aktuelle Pläne (2025/26)
- Allerheiligen-Hofkirche
- Herkulessaal der Residenz (vermutlich über BRSO / München Ticket)
- Staatstheater am Gärtnerplatz
- Gasteig HP8 Saal X
- Deutsches Theater München
- Hubertussaal Schloss Nymphenburg
- Max-Joseph-Saal der Residenz
- BR Funkhaus Studio 1
- Kleiner Konzertsaal / Carl-Orff-Saal (falls weiter bespielt)

## Warum nicht automatisch

Die Webseiten der Häuser blockieren automatische Abrufe aus der Cloud
(z. B. staatsoper.de mit HTTP 403); Links ließen sich nicht prüfen.
Verlässlich ist: Plan einmal als Bild sichern (z. B. Screenshot aus dem
Ticketshop des Hauses) und im Admin hochladen. Nur Bilder erlauben später
auch die Markierung des eigenen Platzes im Plan.
