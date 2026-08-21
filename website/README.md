# klangradar.com – Website

Minimale statische Seite (kein Framework nötig) mit Impressum und einem
Platzhalter für die Datenschutzerklärung, gedacht als Ziel für die Domain
`klangradar.com`.

- `index.html` – Startseite (Platzhalter)
- `impressum.html` – vollständiger Impressum-Text
- `datenschutz.html` – Platzhalter, noch **kein** echter Datenschutztext
  (siehe unten)

## Was noch fehlt (kann ich von hier aus nicht erledigen)

Ich habe keinen Zugriff auf ein Vercel-Konto oder den Domain-Registrar, bei
dem `klangradar.com` gekauft wurde — beides sind externe Logins, die ich
hier nicht habe. Zwei Schritte bleiben bei dir:

1. **Hosten**: z. B. dieses `website/`-Verzeichnis als eigenes Vercel-Projekt
   anlegen (Root Directory `website`, kein Build-Command nötig, "Other"/
   statisches Projekt) — genau wie `admin/` bereits als eigenes
   Vercel-Projekt läuft.
2. **DNS**: bei deinem Domain-Registrar (wo du `klangradar.com` gekauft
   hast) einen `A`/`CNAME`-Eintrag auf Vercel setzen — Vercel zeigt dir die
   genauen Werte, sobald du die Domain im Projekt unter "Domains"
   hinzufügst.

Danach kann ich in der App die Links von `klangradar.app` auf
`klangradar.com` umstellen (aktuell in `ios-native/KlangradarNative/Features/Profile/ProfileView.swift`,
`SignUpStepView.swift` und im Flutter-Onboarding, falls dort ergänzt).

## Datenschutzerklärung

`datenschutz.html` ist bewusst nur ein Platzhalter. Eine echte
Datenschutzerklärung muss korrekt beschreiben, welche Daten die App über
Supabase (Auth, Profile, Standort bei der Onboarding-Standortfreigabe,
Push-Benachrichtigungen) tatsächlich verarbeitet — das sollte nicht
frei erfunden werden. Sag Bescheid, wenn ich einen Entwurf auf Basis der
tatsächlich verarbeiteten Daten vorbereiten soll (zur eigenen Prüfung,
nicht als Rechtsberatung).
