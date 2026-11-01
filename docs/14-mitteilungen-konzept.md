# Mitteilungen – Konzept

*Erstellt von Claude Code am 01.11.2026. Anlass war Jakobs Rückmeldung: „Mitteilungen sind aktuell chaotisch und zu viel, bzw. sinnfrei.“*

## 1. Befund

Grundlage sind die Live-Daten vom 01.11.2026 und der Code.

**Sieben Versandwege, die nichts voneinander wissen:**

| Weg | Was | Budget? |
|---|---|---|
| `push-dispatcher` (alle 15 Min.) | Neues von Gefolgten, fast ausverkauft, Konzerttag, „Wie war's?“, Wochentipp, Re-Engagement | 1/Tag, 3/Woche – **außer Plus „sofort“** |
| `notify-changes` (alle 15 Min.) | Preisänderung, fast ausverkauft (doppelt zum Dispatcher), Absage/Verschiebung | nein |
| `notify-social` (sofort) | 15 Arten: Freundschaft, Pläne, Applaus, Kommentar, „X geht auch hin“, Tickets … | nein |
| `notify-followed-entity-events`, `notify-reminders`, `notify-reengagement` | Altbausteine, teils doppelt zum Dispatcher | einzeln |
| Lokal (iOS) | „In 5 Minuten losgehen“, Standort „Bist du im Konzert?“, Abo-Vorabend (neu) | nein |
| E-Mail | Konzertwoche, Neues von Gefolgten, Änderungen, Vortag, Newsletter | – |

**Was dabei herauskommt:**

- **Am 01.11. gingen 54 Pushes raus, 52 davon an einen einzigen Nutzer, zwischen 7:00 und 19:45.** Fast alle hießen „Neu von Nationaltheater München“.
  - Ursache: Plus-Mitteilungen „sofort und außerhalb des Budgets“. Der Dispatcher läuft alle 15 Minuten und schickt pro Lauf eine, also bis zu 52 am Tag.
- **„Neu“ ist oft nicht neu.**
  - Gemeldet wird, was *importiert* wurde, nicht was *angekündigt* wurde. Eine reaktivierte Quelle oder ein Spielplan-Import löst eine Push-Welle aus, zum Beispiel für Termine im Mai und Juli 2027.
  - 9 der 54 Termine waren Dubletten und sind inzwischen zusammengeführt.
- **Unsaubere Texte:** „TANNHÄUSER“, „C A R P A T H I A“, „dirigiert<br/>Debussy“, zwei Gefolgte in einer überlangen Titelzeile.
- **Keine Wirkung:** 0 von 71 Pushes der letzten 14 Tage wurden geöffnet.
- **Doppelte Anlässe:**
  - Fast ausverkauft kommt aus zwei Systemen.
  - Ein Konzert, das gemerkt *und* Teil des Abos ist, kann am Vorabend zwei Erinnerungen auslösen.
- **Einstellungen in Technik-Sprache:**
  - Fünf Push-Schalter, von denen einer etwas anderes steuert, als er sagt: „Neue passende Veranstaltungen“ schaltet das Re-Engagement.
  - Folgen heißt immer auch Pushen. Wer dem Nationaltheater folgt, um es auf der Karte zu sehen, bekommt jede Premiere als Mitteilung.

## 2. Grundsätze

1. **Nur mit eigenem Anlass.** Eine Mitteilung braucht etwas, das der Nutzer selbst gesetzt hat: gemerkt, geplant, Abo, gefolgt, Freund. Oder sie ist zeitkritisch. „Es gibt Neues“ allein ist kein Grund.
2. **Ein Konzert, eine Mitteilung pro Anlass.** Egal, über wie viele Wege der Anlass entsteht: gemerkt, Abo, geplant.
3. **Bündeln statt tröpfeln.** Neuankündigungen kommen gesammelt: „3 neue Termine: Nationaltheater, Simon Rattle“.
4. **Harte Obergrenzen für alles außer Wichtigem:**
   - höchstens 2 Pushes pro Tag und 6 pro Woche,
   - Ruhezeit 21–8 Uhr.
5. **Lieber in der App als auf dem Sperrbildschirm.** Alles landet in einer Mitteilungszentrale. Gepusht wird nur die Spitze.

## 3. Drei Klassen

### A – Wichtig: sofort, ohne Budget

- Absage, Verschiebung, Zeit- oder Ortsänderung eines Konzerts, das ich gemerkt, geplant oder im Abo habe.
- Freunde, nur direkte Aktionen an mich:
  - Freundschaftsanfrage,
  - Einladung zu einem Konzertplan,
  - mir angebotenes Ticket.

### B – Planung: zeitgebunden, genau eine pro Konzert

- **Vorabend, 18 Uhr:** eine einzige Erinnerung für gemerkt, geplant oder Abo. Die Abo-Erinnerung (lokal) und die Favoriten-Erinnerung (Server) werden zusammengeführt.
- **Konzerttag:** „Losgehen“, lokal, wie heute.
- **„Wie war's?“** am Folgetag um 10 Uhr, nur bei sehr wahrscheinlichem Besuch und höchstens einmal pro Woche.

### C – Entdecken: gebündelt, im Budget

- **Neu angekündigt** von Gefolgten:
  - ein Sammel-Push pro Tag zur Wunschzeit,
  - mit Plus bis zu zweimal täglich (Mittag und Abend), aber ebenfalls gesammelt.
- **Fast ausverkauft:** nur für gemerkte Konzerte ohne eigenes Ticket, einmal pro Konzert.
- **Wochentipp** am Donnerstag: wahlweise als Push oder als E-Mail („Deine Konzertwoche“), nicht beides.

### Leise, nur in der App

- Applaus, Kommentare, „X geht auch hin“, Vielleicht- oder Absage-Antworten auf Pläne.
- Diese kommen in die Mitteilungszentrale und höchstens als ein Sammel-Push pro Tag („Neues von Freunden“).

### Streichen

- **Re-Engagement-Push:** 0 % Öffnungen. Er wirkt wie Werbung und wird durch den Wochentipp ersetzt.
- **Preisänderung als Push:** wird zum Hinweis auf der Konzertseite.
- **Altfunktionen:** `notify-followed-entity-events`, `notify-reminders`, `notify-reengagement`.

## 4. Qualitätsregeln für „Neu angekündigt“

Ein Termin zählt nur, wenn alle folgenden Bedingungen zutreffen:

- Er ist seit höchstens 48 Stunden bekannt, aber mindestens 60 Minuten alt. Bis dahin ist ein Durchlauf der Dublettenprüfung erfolgt.
- Er ist keine Dublette (`duplicate_of is null`), ist veröffentlicht und beginnt frühestens in 2 Tagen.
- Er stammt nicht aus einem **Massenimport**. Liefert eine Quelle für dieselbe Spielstätte, Person oder dasselbe Ensemble mehr als 8 neue Termine an einem Tag, wird daraus *eine* Mitteilung: „Neuer Spielplan: 34 Termine im Nationaltheater“. Das gilt auch für eine frisch angebundene oder reaktivierte Quelle.

Für den Text gilt:

- Titel werden bereinigt: kein HTML, keine Versalien, keine Sperrschrift.
- Pro Push höchstens 3 Termine und höchstens 2 Namen in der Überschrift.

## 5. Einstellungen (iOS und Flutter)

Statt sieben technischer Schalter gibt es fünf in Alltagssprache:

| Schalter | Optionen |
|---|---|
| Änderungen & Absagen meiner Konzerte | an / aus |
| Erinnerungen an meine Konzerte (Vorabend, Konzerttag) | an / aus |
| Neue Konzerte von allem, dem ich folge | täglich gesammelt · wöchentlich · aus (Plus: „zweimal täglich“) |
| Freunde | direkt · einmal täglich gesammelt · aus |
| Wochentipp | Push · E-Mail · aus |

Dazu kommt eine **Glocke je gefolgter Person, je Ensemble und je Ort**. Folgen ohne Mitteilung ist dann möglich, zum Beispiel für große Häuser.

## 6. Umsetzung in drei Schritten

**Schritt 1 – sofort, klein:**

- Plus „sofort“ wird zu „gebündelt, höchstens alle 3 Stunden, höchstens 3 pro Tag“.
- Qualitätsregeln aus Abschnitt 4 in `push_candidates`.
- Titel bereinigen.
- Abo-Vorabend und Favoriten-Vortag zusammenführen.
- Ergebnis: Ein Tag wie der 01.11. hätte 2 statt 52 Mitteilungen erzeugt.

**Schritt 2 – ein Versandweg:**

- `notify-changes` und `notify-social` liefern nur noch Kandidaten an den Dispatcher: Klasse A sofort, die anderen nach Budget.
- Altfunktionen entfernen.
- Neue Einstellungen und Glocke je Gefolgtem.

**Schritt 3 – Mitteilungszentrale und Messen:**

- Glocke in der App mit allen Ereignissen.
- Auswertung je Art: Öffnungsrate, Abschaltungen.
- Automatisches Drosseln von Arten, die nicht geöffnet werden. Das gibt es heute schon im Ansatz.

**Zielwerte:**

- Durchschnittlich höchstens 4 Pushes pro Woche und Nutzer.
- Öffnungsrate über 15 %.
- Weniger als 2 % Push-Abmeldungen pro Monat.
