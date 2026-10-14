# Preise für Veranstalter und Klangradar Plus

_Entwurf, erstellt von Claude Code am 14.10.2026. Alle Beträge sind Vorschläge zur Entscheidung durch Jakob._

## 1. Preisliste für Veranstalter (Push & Promote)

Grundsätze:
- **Pro Konzert, bis zum Konzerttag.** Die Laufzeit beginnt mit der Zahlung und endet am Konzerttag. Wer früher bucht, bekommt mehr Tage. Das ist einfach zu erklären und deckt sich mit dem, was das Portal heute schon anzeigt.
- **Bruttopreise für Endkunden-Kommunikation, netto im Portal.** Solange Jakob Kleinunternehmer nach § 19 UStG ist, sind die Preise Endpreise. Mit USt-Pflicht kommen 19 % hinzu, Rechnungen weisen das automatisch aus (`invoice_settings`).
- **Standard ohne Redaktionsprüfung**, alle anderen Platzierungen mit Freigabe. Das ist schon umgesetzt.

| Platzierung | Wo in der App | Preis pro Konzert | Hinweis |
|---|---|---|---|
| Standard | vorn in Listen und im Kalender des Konzerttags | **29 €** | sofort zahlbar |
| Local Spotlight | erste Karte in „Für dich“ | **59 €** | Stadt des Konzerts |
| Featured | erste Karte in „Konzerte entdecken“ (Suche) | **79 €** | |
| Homepage-Feature | großes Titelbild oben auf Home | **149 €** | max. 3 gleichzeitig pro Stadt, täglich rotierend |
| Push-Benachrichtigung | Mitteilung an Interessierte (Genre, gefolgte Künstler, Stadt) | **199 €** | einmalig, Redaktion versendet, max. 1 pro Woche und Nutzer |

Pakete (Rabatt gegenüber Einzelbuchung):
- **Saisonstart** (5 Standard + 2 Featured): 249 € statt 303 €
- **Premiere** (Homepage-Feature + Push + Featured): 349 € statt 427 €

Später möglich, nicht Teil dieses Entwurfs: **Portal Pro** als Abo für Veranstalter mit vielen Terminen (z. B. 49 €/Monat: monatliches Kontingent an Standard-Platzierungen, erweiterte Statistik, bevorzugte Prüfung).

**Umsetzung:** Die Preise liegen als Stripe-Preise vor (`PRICE_ID_BY_PLACEMENT` in `admin/src/lib/promotion-payment.ts`). Neue Beträge bedeuten neue Preise in Stripe und neue IDs in dieser Datei. Pakete brauchen zusätzlich eine kleine Erweiterung im Portal.

## 2. Klangradar Plus (Abo für Nutzer)

### Angebot

| | Kostenlos | Klangradar Plus |
|---|---|---|
| Konzerte finden, Karte, Kalender, Favoriten, Widget, Live Activity | ✓ | ✓ |
| Klangradar KI | 5 Fragen pro Woche | unbegrenzt |
| Eigene Listen | 3 Listen | unbegrenzt |
| Vorverkaufs-Alarm (sofortige Mitteilung bei neuen Terminen gefolgter Künstler und Ensembles) | täglich gesammelt | sofort |
| Konzerttagebuch mit Jahresrückblick und Statistiken | Grundansicht | vollständig |
| Kalender-Abo der gemerkten Konzerte | ✓ | ✓ |

Preise (Vorschlag):
- **Monatlich 3,99 €**
- **Jährlich 29,99 €** (≈ 2,50 €/Monat, als „beliebt“ hervorgehoben)
- **7 Tage kostenlos testen** für Neukunden (Einführungsangebot in App Store Connect)

Kern bleibt kostenlos: Die App soll die beste Konzertübersicht sein, Plus verkauft Komfort und KI, nicht den Zugang.

### Bezahlprozess

- Digitale Abos in iOS-Apps müssen über **Apples In-App-Kauf** laufen (StoreKit 2), nicht über Stripe.
- Apple behält **15 %** ein: Small Business Program bis 1 Mio. $ Jahresumsatz, gilt auch für Abos ab dem zweiten Jahr. Dafür übernimmt Apple Abrechnung, Mehrwertsteuer in allen Ländern, Kündigung und Rückerstattung.
- **Produkte:**
  - Abo-Gruppe „Klangradar Plus“
  - `de.klangradar.plus.monthly`
  - `de.klangradar.plus.yearly`
- **Ablauf in der App:**
  1. Paywall zeigt beide Pakete mit lokalem Preis (von Apple geliefert).
  2. Kauf über `Product.purchase()`.
  3. Apple bestätigt mit Face ID.
  4. Die App prüft die signierte Transaktion (`Transaction.currentEntitlements`) und schaltet sofort frei.
- **Wiederherstellen:** Button „Käufe wiederherstellen“ (`AppStore.sync()`), Pflicht laut App-Review.
- **Verwalten/Kündigen:** Systemdialog `manageSubscriptionsSheet`.
- **Server (zweiter Schritt):** App Store Server Notifications V2 an eine Edge Function, die `plus_entitlements` pflegt. Damit gilt Plus später auch im Web und für serverseitige Grenzen (KI-Kontingent). Bis dahin prüft die App lokal.

### Voraussetzungen in App Store Connect (Jakob)

1. **Verträge, Steuern und Bankverbindung:** Vertrag „Kostenpflichtige Apps“ abschließen, Bankkonto und Steuerformulare hinterlegen. Ohne das kann Apple keine Abos verkaufen.
2. Abo-Gruppe und die zwei Produkte anlegen, Preise und Einführungsangebot setzen. Das kann Claude Code über den angemeldeten Browser oder die API übernehmen.
3. Optional dem **Small Business Program** beitreten (15 % statt 30 %).
4. Für die Prüfung Datenschutzerklärung und Nutzungsbedingungen (EULA) verlinken; die Paywall zeigt beides an.

### Design (iOS)

- Gebaut aus vorhandenen Bausteinen: `KlangradarBackground`, `LiquidGlassSurface`, `KlangradarTheme.accent`, `Haptics`.
- Aufbau:
  - Kopf mit Symbol und Titel „Klangradar Plus“
  - Vorteile als Liste mit SF-Symbolen
  - zwei Paket-Karten (Jahr hervorgehoben)
  - Hauptbutton „7 Tage kostenlos testen“ bzw. „Weiter“
  - darunter klein: Preis nach Testphase, automatische Verlängerung, Links zu Nutzungsbedingungen und Datenschutz, „Käufe wiederherstellen“
- **Einstiege:**
  - Profil → „Klangradar Plus“
  - beim Erreichen eines Limits (KI-Kontingent, 4. Liste) mit Erklärung
- Für Plus-Mitglieder: Status-Zeile „Plus aktiv bis …“ und „Abo verwalten“.
