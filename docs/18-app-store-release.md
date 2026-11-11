# App-Store-Release – Paket zum Kopieren (Stand 11.11.2026)

Alles, was in App Store Connect einzutragen ist. Erstellt von Claude Code.
Was nur in App Store Connect / Supabase / auf dem iPhone geht, ist mit
☐ markiert; im Repo bereits erledigt ist mit ✅ markiert.

## 0. Bereits im Code erledigt ✅

- Exportbestimmungen: `ITSAppUsesNonExemptEncryption = NO` (generate_project.rb) – die Verschlüsselungsfrage erscheint nicht mehr.
- Konto löschen in der App (Profil → Einstellungen → Konto löschen), inkl. Fotos.
- Melden und Blockieren im Chat und bei Profilen; „Problem melden“ in den Einstellungen.
- Datenschutzerklärung, Nutzungsbedingungen, Impressum in der App und unter klangradar.com.
- Mindestalter 16 bei der Registrierung.
- Anmeldung mit E-Mail + Passwort (für das Prüfer-Konto), Apple, Google.
- Plus-Kaufseite mit „Käufe wiederherstellen“ und Links zu Nutzungsbedingungen/Datenschutz.

## 1. Prüfer-Konto (Demo) ☐

1. Supabase → Authentication → Users → **Add user** → „Create new user“:
   E-Mail `appreview@klangradar.com`, ein sicheres Passwort, **Auto Confirm User** an.
2. Supabase → SQL Editor:

```sql
-- Plus dauerhaft für das Prüfer-Konto, Onboarding als erledigt markieren
insert into plus_entitlements (user_id, source, code, expires_at)
select id, 'code', 'APPREVIEW', null from auth.users where email = 'appreview@klangradar.com'
on conflict (user_id) do update set expires_at = null, updated_at = now();
update profiles set onboarding_completed = true, display_name = coalesce(display_name, 'App Review')
where id = (select id from auth.users where email = 'appreview@klangradar.com');
```

3. Mit dem Konto in TestFlight einmal anmelden, ein Konzert merken, ein Ticket hinzufügen
   (beliebiger QR-Code), einen Chat mit deinem eigenen Konto anlegen – dann hat Apple Inhalte.
4. Zugang unten bei „Anmeldeinformationen“ eintragen.

## 2. App-Informationen ☐

| Feld | Wert |
|---|---|
| Name | Klangradar |
| Untertitel (30) | Klassik-Konzerte entdecken |
| Kategorie | Musik · Zweitkategorie: Unterhaltung |
| Datenschutz-URL | https://klangradar.com/datenschutz |
| Nutzungsbedingungen (EULA) | https://klangradar.com/nutzungsbedingungen |
| Support-URL | https://klangradar.com/impressum |
| Marketing-URL | https://klangradar.com |
| Altersfreigabe | Fragebogen: „Nutzergenerierte Inhalte“ **Ja**, „Nachrichten/Chat“ **Ja**, alles andere Nein → mit Mindestalter **16+** wählen |

## 3. App-Datenschutzangaben (Privacy Labels) ☐

„Daten, die mit dir verknüpft sind“ – Tracking: **Nein** bei allem.

| Datentyp | Zweck |
|---|---|
| Kontaktinfo: Name, E-Mail-Adresse, Telefonnummer (optional) | App-Funktionalität |
| Kontakte (nur gehasht, Freundesuche) | App-Funktionalität |
| Standort: genau, ungefähr | App-Funktionalität |
| Nutzerinhalte: Fotos, andere Nutzerinhalte (Chat, Tagebuch) | App-Funktionalität |
| Nutzerinhalte: E-Mails oder Textnachrichten (Chat) | App-Funktionalität |
| Käufe | App-Funktionalität |
| Suchverlauf | App-Funktionalität, Personalisierung |
| Nutzungsdaten: Produktinteraktion | Analysen, Personalisierung |
| Diagnose: Absturzdaten, Leistungsdaten | App-Funktionalität |
| Andere Daten: Musikbibliothek/Hörverlauf (Musikgeschmack) | Personalisierung |
| Kennungen: Nutzer-ID | App-Funktionalität |

## 4. Store-Texte

### Deutsch

**Werbetext (170):** Konzerte, Oper und Chormusik in deiner Stadt – mit Programm, Besetzung, Saalplan, Wallet-Ticket und Empfehlungen nach deinem Geschmack.

**Beschreibung:**
Klangradar zeigt dir alle Konzerte der klassischen Musik in deiner Stadt – Orchester, Oper, Kammermusik, Chor und Kirchenmusik an einem Ort.

• Entdecken: Programme, Besetzungen und Werkeinführungen zu jedem Konzert
• Folgen: Künstler:innen, Ensembles und Spielstätten – und erfahren, wenn sie spielen
• Musikgeschmack: Apple Music oder Last.fm verknüpfen und passende Konzerte, Werke und Ensembles entdecken
• Ticket & Platz: Ticket hinzufügen, Platz wird erkannt, Code scharf am Einlass, eigene Wallet-Karte mit Konzertbild
• Konzerttag: Einlass, Anreise, Wetter und Live-Aktivität auf dem Sperrbildschirm
• Freunde: gemeinsam planen, Konzerte teilen, chatten
• Konzerttagebuch: Erlebtes festhalten, dein Konzertjahr im Rückblick
• Klangradar KI: Fragen zu Werken, Künstler:innen und Abenden

Klangradar Plus (optional, Abo): Sofort-Alarm bei neuen Konzerten, Konzertjahr, Partner-Vorteile und mehr. Preis und Laufzeit werden vor dem Kauf angezeigt; Verlängerung automatisch, kündbar in den Einstellungen deiner Apple-ID.

Nutzungsbedingungen: https://klangradar.com/nutzungsbedingungen · Datenschutz: https://klangradar.com/datenschutz

**Keywords (100):** klassik,konzert,oper,orchester,chor,philharmonie,tickets,münchen,kammermusik,spielplan,musik

### English

**Promotional text:** Classical concerts, opera and choral music in your city – programmes, casts, seating plans, Wallet tickets and recommendations based on your taste.

**Description:** Klangradar brings every classical concert in your city together – orchestras, opera, chamber music, choirs and sacred music. Follow artists, ensembles and venues, connect Apple Music or Last.fm for personal recommendations, keep your ticket and seat with a Wallet pass, plan with friends and keep a concert diary. Klangradar Plus is an optional auto-renewing subscription; price and period are shown before purchase and it can be cancelled in your Apple ID settings. Terms: https://klangradar.com/nutzungsbedingungen · Privacy: https://klangradar.com/datenschutz

**Keywords:** classical,concert,opera,orchestra,choir,philharmonic,tickets,munich,chamber music,music

## 5. Notizen für die App-Prüfung (Review Notes) – Englisch

```
Demo account (Plus enabled): appreview@klangradar.com / <password>
Sign in: Profile → "Anmelden" → "Mit E-Mail und Passwort".

Key features to review:
• Account deletion: Profile → Einstellungen (settings) → "Konto löschen".
• User-generated content (chat, comments): long-press a message or open a
  profile → "Melden" (report) / "Blockieren" (block). Reports are reviewed
  within 24 hours; contact: jakob@klangradar.com or Settings → "Problem melden".
• Klangradar Plus (auto-renewable subscription): Profile → Klangradar Plus.
  "Käufe wiederherstellen" (restore purchases) is on the same screen; terms
  and privacy links are shown there.
• Music taste: Profile → "Musikgeschmack" → Apple Music (MusicKit, reads the
  library on device after permission) or Last.fm (username only). Spotify is
  not required and hidden in this build.
• Tickets/Wallet: open any concert → "Ticket hinzufügen"; the app creates an
  Apple Wallet pass. It never sells tickets; purchases happen on the
  organiser's website.
• Location is only used for the map, nearby concerts and visit check-in.
A screen recording of these flows is attached.
```

## 6. Bildschirmaufnahme – Drehbuch (ca. 2 Min.) ☐

iPhone: Kontrollzentrum → Bildschirmaufnahme (Mikrofon aus). Mit dem Demo-Konto, ohne Schnitt:

1. App öffnen → Startseite kurz scrollen (5 s)
2. Konzert öffnen → „Ticket hinzufügen“ → Foto/PDF wählen → Platz erscheint → „Zu Apple Wallet“ (20 s)
3. Freunde → Chat öffnen → Nachricht lange drücken → „Melden“ zeigen, abbrechen; Profil → „Blockieren“ zeigen (20 s)
4. Profil → Klangradar Plus → Kaufseite, „Käufe wiederherstellen“ und Links zeigen, schließen (15 s)
5. Profil → Musikgeschmack → Apple Music verknüpfen → Ergebnis (20 s)
6. Profil → Einstellungen → „Konto löschen“ antippen → Dialog zeigen → **Abbrechen** (10 s)

Video in App Store Connect hochladen: Version → App-Prüfung → „Anhang“ bzw. in der Antwort auf die Ablehnung.

## 7. Screenshots ☐

Pflicht: iPhone 6,9″ (1320 × 2868) – 3 bis 10 Stück; iPad 13″ (2064 × 2752), da die App auf dem iPad läuft.
Vorschlag: Startseite · Konzertseite mit Programm · Wallet-Karte · Musikgeschmack · Karte · Konzerttagebuch.
Im Simulator: iPhone 17 Pro Max / iPad Pro 13″, Cmd+S speichert in Originalgröße.

## 8. Vor dem Einreichen ☐

- [ ] Migrationen 167–170 freigegeben, Edge Functions deployt
- [ ] Supabase unter dem Kontingent oder Pro-Plan (sonst Ausfall während der Prüfung)
- [ ] Abo-Produkte `de.klangradar.plus.monthly` / `.yearly` „Bereit zur Einreichung“, mit Review-Screenshot, der Version zugeordnet
- [ ] MusicKit im Developer-Portal aktiv ✅ (laut Jakob erledigt)
- [ ] Neuesten TestFlight-Build unter „Build“ auswählen → Zur Prüfung einreichen
