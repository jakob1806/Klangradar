# Datenschutzerklärung

> **ENTWURF — nicht rechtsverbindlich.** Vor Veröffentlichung von einer Kanzlei
> prüfen und vervollständigen. Siehe auch `docs/10-legal-status.md` für offene
> AVV-Abschlüsse, ohne die diese Erklärung nicht final ist.

## 1. Verantwortlicher
[FIRMENNAME], [ANSCHRIFT], [KONTAKT-E-MAIL] (siehe Impressum).

## 2. Welche Daten wir verarbeiten

| Datenkategorie | Zweck | Rechtsgrundlage (DSGVO) |
|---|---|---|
| E-Mail-Adresse, Passwort-Hash | Konto/Login (E-Mail-Code-Login) | Art. 6 Abs. 1 lit. b |
| Standortdaten (bei Erlaubnis) | Kartenansicht, Umkreissuche | Art. 6 Abs. 1 lit. a (Einwilligung) |
| Push-Token (Firebase Cloud Messaging) | Benachrichtigungen zu Events | Art. 6 Abs. 1 lit. a |
| Suchhistorie (eingeloggte Nutzer:innen) | Persönliche Suchhistorie, Empfehlungen | Art. 6 Abs. 1 lit. b/f |
| Interessen/Präferenzen | Personalisierte Empfehlungen | Art. 6 Abs. 1 lit. a |
| Nutzungsdaten (technisch, z. B. IP bei Requests) | Betrieb, Sicherheit | Art. 6 Abs. 1 lit. f |

[ANWALT: Tabelle gegen tatsächliche Datenbank-Spalten in
`docs/02-database-schema.md` und Supabase-Migrationen abgleichen und vervollständigen.]

## 3. Empfänger / Auftragsverarbeiter

- **Supabase** (Datenbank-, Auth- und Storage-Hosting). [ANWALT: AVV-Status und
  Serverregion (EU/US) ergänzen, siehe `docs/10-legal-status.md`.]
- **Google / Firebase Cloud Messaging** (Push-Benachrichtigungen). Datenverarbeitung
  kann in die USA erfolgen; [ANWALT: Standardvertragsklauseln/Angemessenheitsbeschluss
  benennen, sobald AVV vorliegt].
- Bei aktivierter Anmeldung mit Apple/Google: der jeweilige OAuth-Anbieter.
  [ANWALT: Passage ergänzen, sobald diese Login-Methoden live geschaltet werden.]

## 4. Kartendarstellung
Die Kartenansicht nutzt OpenStreetMap-Kartenmaterial (flutter_map). [ANWALT: prüfen,
ob und welche Daten dabei an den Tile-Server/Hoster übertragen werden, und
entsprechenden Passus ergänzen — abhängig vom verwendeten Tile-Provider.]

## 5. Speicherdauer
[ANWALT/PRODUKT: konkrete Löschfristen je Datenkategorie festlegen, z. B. Konto-
löschung auf Nutzerwunsch, automatische Löschung inaktiver Konten nach X Monaten.]

## 6. Betroffenenrechte
Nutzer:innen haben das Recht auf Auskunft (Art. 15 DSGVO), Berichtigung (Art. 16),
Löschung (Art. 17), Einschränkung der Verarbeitung (Art. 18), Datenübertragbarkeit
(Art. 20) und Widerspruch (Art. 21) sowie das Recht auf Beschwerde bei einer
Aufsichtsbehörde. Anfragen an: [KONTAKT-E-MAIL].

## 7. Widerruf von Einwilligungen
Standortfreigabe und Push-Benachrichtigungen können jederzeit in den Geräte- bzw.
App-Einstellungen widerrufen werden. Marketing-E-Mails können über den Abmeldelink
bzw. in den Profileinstellungen abbestellt werden.

## 8. Änderungen dieser Erklärung
Wir passen diese Datenschutzerklärung bei Bedarf an geänderte Rechtslage oder
Funktionsänderungen der App an.

Stand: [DATUM DER LETZTEN AKTUALISIERUNG]
