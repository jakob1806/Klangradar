# klangradar.com – Website

Minimale statische Seite (kein Framework nötig) mit Impressum und einem
Platzhalter für die Datenschutzerklärung, gedacht als Ziel für die Domain
`klangradar.com`.

- `index.html` – Startseite (Platzhalter)
- `impressum.html` – vollständiger Impressum-Text
- `datenschutz.html` – Datenschutzerklärung, siehe Hinweis unten

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

`datenschutz.html` ist ein Entwurf, den ich anhand einer Durchsicht des
tatsächlichen Codes erstellt habe (Supabase-Auth, `profiles`-Tabelle,
Standort/`home_location`, Favoriten/Follows/Interessen, Firebase Cloud
Messaging für Push, Resend für E-Mail-Versand, Supabase/Vercel-Hosting).
**Das ist keine Rechtsberatung** — bitte vor Veröffentlichung von einer
Person mit rechtlicher Qualifikation prüfen lassen, insbesondere:

- die genaue Supabase-Projekt-Region (EU/US) ist nicht im Code hinterlegt
  und sollte im Supabase-Dashboard nachgeprüft und ggf. ergänzt werden,
- ob Sign in with Apple/Google in Produktion aktiv sind (im Repo aktuell
  standardmäßig deaktiviert) — falls ja, ergänzt sich Punkt 2,
- ob mit Firebase/Google und Resend bereits Auftragsverarbeitungsverträge
  (AVV) abgeschlossen wurden.
