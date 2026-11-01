# Bildabdeckung – Konzept

*Erstellt von Claude Code am 01.11.2026 auf Nutzerwunsch: „Konzept zur Erweiterung und Verbesserung der Bildabdeckung“. Alle Zahlen stammen aus den Live-Daten vom 01.11.2026 und beziehen sich auf kommende, veröffentlichte Konzerte ohne Dubletten.*

## 1. Ausgangslage

### Was Nutzer:innen sehen

| Stadt | Konzerte | eigenes Bild | nur Mitwirkenden-Bild | nur Bild der Spielstätte | gar kein Bild |
|---|---|---|---|---|---|
| München | 814 | 375 (46 %) | 185 | 233 | 21 (3 %) |
| Frankfurt | 663 | 338 (51 %) | 87 | 194 | 44 (7 %) |
| Wien | 533 | 136 (26 %) | 136 | 75 | **186 (35 %)** |
| Hamburg | 279 | 84 (30 %) | 82 | 81 | 32 (11 %) |
| Berlin | 207 | 54 (26 %) | 91 | 51 | 11 (5 %) |
| **Gesamt** | **2.496** | **987 (40 %)** | 581 | 634 | **294 (12 %)** |

Fehlt ein eigenes Bild, zeigt die App ersatzweise Fotos von Mitwirkenden oder von der Spielstätte. Ein Saalfoto bei jedem dritten Konzert wirkt allerdings austauschbar.

### Bilder hinter den Konzerten

| Bereich | gesamt | mit Bild |
|---|---|---|
| Personen in kommenden Konzerten | 2.752 | 868 (32 %) |
| davon in 3 oder mehr Konzerten | 776 | 241 (31 %) |
| Ensembles in kommenden Konzerten | 104 | 54 (52 %) |
| Spielstätten mit kommenden Konzerten | 87 | 62 (71 %) |

### Ursachen

1. **Stau bei der Freigabe:**
   - 505 gefundene Porträts warten in `/media` auf Lizenzprüfung, darunter 198 aus Wikipedia und 170 von offiziellen Websites.
   - 297 davon betreffen Personen mit kommenden Konzerten.
   - 163 Konzerte ohne eigenes und ohne Mitwirkenden-Bild hätten danach eins.
2. **Wenige Spielstätten mit vielen Terminen haben kein Foto:**
   - Musikverein Großer Saal (173 Konzerte), MUK Wien (109), mdw Wien (72), HfMDK Frankfurt (35), Cuvilliés-Theater (24), Deutsche Oper Berlin (21), Hamburgische Staatsoper (17).
   - Acht Orte stehen für rund 460 Konzerte.
3. **Die Suche ist ausgeschöpft:** Bei 2.064 Personen fanden Wikipedia, Wikidata und die Websuche nichts eindeutiges. Weitere Läufe mit denselben Quellen bringen nichts mehr.
4. **Keine Priorität nach Relevanz:**
   - Die Warteschlange arbeitet nach „am längsten nicht geprüft“. Eine Solistin mit fünf Konzerten nächste Woche wartet genauso lang wie ein Chormitglied ohne Termin.
   - 106 Personen mit zwei oder mehr kommenden Konzerten wurden noch nie gesucht.
5. **Fremd verlinkte Bilder:**
   - 728 Personenfotos werden direkt von fremden Servern geladen (staatsoper.de, volksoper.at, cloudfront …), nur 267 liegen im eigenen Speicher.
   - Risiken: Bilder verschwinden beim Relaunch einer Website, laden langsam, und die Abrufe verraten den fremden Servern die IP-Adressen der Nutzer:innen.
6. **Ungenutzter Ersatz:** 145 Konzerte ohne eigenes und ohne Mitwirkenden-Bild spielen Werke, deren Komponist ein Porträt hat. Gemeinfreie Komponistenbilder wären ein besserer Ersatz als das Saalfoto.

## 2. Ziele bis Ende der Saisonhälfte (Februar 2027)

| Kennzahl | heute | Ziel |
|---|---|---|
| Konzerte mit eigenem oder Mitwirkenden-Bild | 63 % | **85 %** |
| Konzerte ganz ohne Bild | 12 % | **unter 2 %** |
| Wien ganz ohne Bild | 35 % | **unter 5 %** |
| Personen mit 3 oder mehr Konzerten mit Foto | 31 % | **70 %** |
| Bilder im eigenen Speicher (statt fremd verlinkt) | 27 % | **95 %** |

## 3. Maßnahmen

### A. Schnelle Hebel (eine Woche)

1. **Schnellfreigabe in `/media`:**
   - Eine Prüfansicht zeigt den Kandidaten groß, daneben Name, Rolle, nächstes Konzert und Quelle mit Lizenz. Bedienung per Tastatur: J = übernehmen, N = verwerfen, Pfeil = weiter.
   - Sortiert nach Wirkung: zuerst Personen mit den meisten kommenden Konzerten.
   - Ziel: 300 Freigaben in rund einer Stunde Redaktionszeit.
2. **Automatische Freigabe erweitern** (nur wo die Rechtslage eindeutig ist):
   - Wikimedia-Bilder mit maschinenlesbarer freier Lizenz (CC0, CC BY, CC BY-SA, gemeinfrei) samt Urheber werden automatisch übernommen, mit Credit-Zeile.
   - Pressefotos aus offiziellen Pressebereichen von Veranstaltern und Agenturen werden als `official_press_image` mit Credit übernommen.
   - Alles andere bleibt in der Prüfung.
3. **Fotos für die Spielstätten mit den meisten Terminen:**
   - Die 25 Orte mit kommenden Konzerten ohne Foto bekommen gezielt Bilder aus Wikimedia Commons oder Pressebereichen.
   - Damit sind die 186 Wiener Konzerte ohne Bild größtenteils versorgt.
   - Große Häuser bekommen ein Foto pro Saal („Großer Saal“, „Gläserner Saal“).
4. **Neue Reihenfolge der Ersatzbilder:**
   - Wenn ein Konzert kein eigenes Bild hat: Hauptsolist:in, dann Dirigent:in, dann Ensemble, dann **Komponist:in des Hauptwerks**, dann Spielstätte.
   - Wirkung: 145 Konzerte bekommen sofort ein passenderes Bild.

### B. Neue Quellen (zwei bis drei Wochen)

5. **Priorisierte Warteschlange:**
   - Neue Punktzahl je Person und Ensemble: Zahl der kommenden Konzerte, Rolle (Solo und Dirigat vor Orchestermitglied), Nähe des nächsten Termins, Stadt.
   - Wer keine kommenden Konzerte hat, wird nur noch nachrangig gesucht.
6. **Künstleragenturen:**
   - Die großen Agenturen (u. a. Askonas Holt, IMG Artists, HarrisonParrott, KD Schmid, Hazard Chase, Konzertdirektion Hörtnagel) haben Künstlerseiten mit Pressefotos und Credit.
   - Abgleich über Namen und Instrument, Übernahme als Pressefoto mit Credit.
   - robots.txt und Nutzungsbedingungen werden je Agentur geprüft. Wo eine Agentur das nicht erlaubt, fragen wir an.
7. **Musiker:innen-Seiten der Orchester:** BRSO, Münchner Philharmoniker, Wiener Philharmoniker, DSO und andere zeigen Porträts aller Mitglieder. Das hilft bei Kammermusik und solistischen Auftritten von Orchestermitgliedern.
8. **Bilder vom Veranstalter direkt am Termin:**
   - Viele Häuser haben pro Produktion ein Szenenfoto (Oper, Ballett).
   - Die vorhandene Erkennung (og:image, schema.org) bekommt einen Filter gegen Logos, Platzhalter und Textbanner: Seitenverhältnis, Text- und Flächenanteil, wiederkehrender Bild-Hash innerhalb einer Quelle.
9. **Gesamtquellen nutzen:**
   - Wenn Dubletten zusammengeführt werden, wird das beste Bild aller beteiligten Quellen übernommen, nicht das erste.
   - Die Zusammenführung aus der Staatsoper-Gesamtquelle füllt Bildlücken schon heute.

### C. Qualität und Betrieb

10. **In den eigenen Speicher spiegeln:**
    - Alle fremd verlinkten Bilder mit geklärter Lizenz laufen durch die vorhandene Pipeline: WebP, Vorschaubild, Duplikaterkennung, Speicher.
    - Das ist schneller und robuster, und Nutzer:innen bleiben gegenüber fremden Servern anonym.
11. **Bildausschnitt:**
    - Gesichtserkennung auf dem Gerät beim Import (Vision bzw. ein kleiner Serverschritt) legt einen Fokuspunkt fest.
    - Porträts im Querformat schneiden dann nicht mehr den Kopf ab. Bisher ist der Ausschnitt fest oben verankert.
12. **Falsche Bilder erkennen:**
    - Dasselbe Foto bei zwei verschiedenen Personen kommt in die Prüfung.
    - Name und Bildunterschrift müssen zusammenpassen; den Baustein „imageNearName“ gibt es schon.
    - In der App: „Falsches Bild melden“ an jedem Porträt.
13. **Gestaltete Programm-Cover statt leerer Flächen:**
    - Für den Rest ohne jedes Bild ein typografisches Cover aus Komponistennamen, Werktitel und einer Farbe je Genre.
    - Ehrlich gestaltet statt eines falschen Fotos, und damit 100 % visuelle Abdeckung.
14. **Selbst hochladen:**
    - Künstler:innen, Agenturen und Veranstalter laden Fotos mit Credit selbst hoch: im Veranstalterportal und später über einen verifizierten Künstlerzugang.
    - Mit Nutzungsbestätigung als Lizenznachweis.

### D. Messen

15. **Admin-Seite „Bildabdeckung“:**
    - Die Tabelle aus Abschnitt 1 live, je Stadt und Quelle, mit Wochenverlauf.
    - Dazu Listen „größte Wirkung“: Personen und Orte ohne Bild, sortiert nach Zahl der kommenden Konzerte.
    - Auch der Freigabe-Stau wird angezeigt.

## 4. Reihenfolge und erwartete Wirkung

| Schritt | Aufwand | Wirkung (Konzerte ohne eigenes oder Mitwirkenden-Bild: heute 928) |
|---|---|---|
| A1 + A2 Freigabe-Stau | klein (plus rund 1 Stunde Redaktion) | −163 |
| A4 Komponist als Ersatz | klein | −145 |
| A3 Top-Spielstätten | klein | „gar kein Bild“ von 294 auf rund 60 |
| B5 Priorität | klein | mehr Treffer pro Lauf |
| B6–B8 neue Quellen | mittel | geschätzt −200 bis −300 |
| C10 Spiegeln | mittel | Stabilität, Datenschutz |
| C13 Programm-Cover | klein | „gar kein Bild“ unter 2 % |
| C11, C12, C14, D15 | mittel | Qualität, Dauerbetrieb |

**Empfehlung:** Zuerst A1–A4 und B5 als ein Paket. Das bringt die größte Wirkung bei kleinem Aufwand. Danach B6–B8 und C10, die neuen Quellen also gleich mit Spiegelung in den eigenen Speicher.

## 5. Rechtliches

- Es werden nur Bilder mit dokumentierter Herkunft und Lizenz übernommen: freie Lizenz, offizielles Pressefoto mit Credit oder Freigabe durch Rechteinhaber.
- Credits erscheinen wie bisher in der App.
- Keine Umgehung von Bot-Sperren. Quellen, die automatischen Abruf ausschließen, fragen wir an oder lassen sie weg.
- Pressefotos sind für die Berichterstattung über die konkrete Veranstaltung gedacht. Sie werden nur für Personen mit kommenden Konzerten verwendet und bei Widerspruch sofort entfernt.
