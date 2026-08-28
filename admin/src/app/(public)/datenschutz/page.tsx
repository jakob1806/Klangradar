import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Datenschutz — Klangradar",
};

// Hinweis aus website/README.md (dort stand dieser Disclaimer bisher nur im
// README, nicht auf der Seite selbst — beim Portieren bewusst als interner
// Kommentar erhalten, nicht als neuer öffentlicher Text): Dieser Text ist
// ein KI-Entwurf anhand einer Durchsicht des tatsächlichen Codes
// (Supabase-Auth, profiles-Tabelle, Standort/home_location,
// Favoriten/Follows/Interessen, Firebase Cloud Messaging für Push, Resend
// für E-Mail-Versand, Supabase/Vercel-Hosting) — KEINE Rechtsberatung, vor
// Veröffentlichung von einer Person mit rechtlicher Qualifikation prüfen
// lassen, insbesondere: die genaue Supabase-Projekt-Region (EU/US, nicht im
// Code hinterlegt), ob Sign in with Apple/Google in Produktion aktiv sind
// (im Repo aktuell standardmäßig deaktiviert), und ob mit Firebase/Google
// und Resend bereits Auftragsverarbeitungsverträge (AVV) abgeschlossen
// wurden.
export default function DatenschutzPage() {
  return (
    <div className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="type-heading text-3xl text-[#1d1d1f]">Datenschutzerklärung</h1>
      <p className="mt-2 mb-10 text-sm text-[#86868b]">Stand: August 2026</p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">1. Verantwortlicher</h2>
      <p className="whitespace-pre-line text-sm leading-relaxed text-[#3a3a3c]">
        {"Jakob Liess\nGabelsbergerstraße 6\n80333 München\nDeutschland"}
      </p>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        E-Mail: <a href="mailto:jakob@klangradar.com" className="text-[#0071e3] hover:underline">jakob@klangradar.com</a>
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">2. Registrierung und Anmeldung</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Für die Nutzung von Klangradar kannst du ein Konto mit E-Mail-Adresse und Passwort anlegen. Bei
        der Registrierung senden wir dir zur Bestätigung deiner E-Mail-Adresse einen Code an diese
        Adresse; derselbe Mechanismus wird verwendet, falls du dein Passwort zurücksetzen möchtest. Ohne
        Konto kannst du die App auch anonym nutzen (z. B. zum Durchsuchen von Veranstaltungen); in
        diesem Fall wird lediglich eine technische, nicht auf deine Person zurückführbare
        Sitzungskennung angelegt.
      </p>
      <p className="mt-2 text-sm leading-relaxed text-[#3a3a3c]">
        Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO (Erfüllung eines Vertrags bzw. vorvertragliche
        Maßnahmen).
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">3. Profildaten und Personalisierung</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Wenn du ein Konto erstellst, kannst du einen Anzeigenamen und ein Profilbild hinterlegen.
        Optional kannst du einen &bdquo;Heimatort&ldquo; festlegen (z. B. um dir Veranstaltungen in
        deiner Nähe zu zeigen); dieser wird entweder aus einer von dir erteilten Standortfreigabe deines
        Geräts oder aus einer manuellen Auswahl abgeleitet und als Ort gespeichert, nicht als
        fortlaufender Bewegungsverlauf.
      </p>
      <p className="mt-2 text-sm leading-relaxed text-[#3a3a3c]">
        Zusätzlich speichern wir, welche Interessen (Genres), Personen, Ensembles und Orte du auswählst
        oder abonnierst, welche Veranstaltungen du favorisierst oder in eigene Listen einordnest, sowie
        — zur Verbesserung der für dich angezeigten Empfehlungen — welche Veranstaltungen du dir ansiehst
        und wonach du in der App suchst.
      </p>
      <p className="mt-2 text-sm leading-relaxed text-[#3a3a3c]">
        Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung) sowie, soweit es um die
        Personalisierung von Empfehlungen geht, Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an
        einer relevanten, nutzbaren App).
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">4. Standortzugriff auf deinem Gerät</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Die App kann dich um Zugriff auf den Standort deines Geräts bitten, etwa um dir Veranstaltungen
        in deiner Nähe zu zeigen oder eine Karte zu befüllen. Diese Freigabe erteilst du über die
        Berechtigungen deines Betriebssystems und kannst sie dort jederzeit widerrufen. Der
        Live-Standort wird nicht dauerhaft auf unseren Servern gespeichert; lediglich der von dir
        bestätigte &bdquo;Heimatort&ldquo; (siehe Punkt 3) bleibt in deinem Profil hinterlegt.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">5. Push-Benachrichtigungen</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Wenn du Push-Benachrichtigungen aktivierst, wird ein Gerätetoken über den Dienst Firebase Cloud
        Messaging (Google Ireland Limited bzw. Google LLC, USA) erzeugt und bei uns gespeichert, um dir
        Benachrichtigungen zu neuen Veranstaltungen, Preisänderungen oder Erinnerungen zusenden zu
        können. Welche Arten von Benachrichtigungen du erhältst, kannst du in den Einstellungen der App
        granular festlegen. Beim Abmelden wird dein Gerätetoken gelöscht.
      </p>
      <p className="mt-2 text-sm leading-relaxed text-[#3a3a3c]">
        Da Google Cloud-Infrastruktur auch außerhalb der EU betreiben kann, kann es hierbei zu einer
        Datenübermittlung in Drittländer (insb. die USA) kommen; Google hat sich zur Einhaltung der
        EU-Standardvertragsklauseln verpflichtet. Rechtsgrundlage ist deine Einwilligung (Art. 6 Abs. 1
        lit. a DSGVO), die du jederzeit über die Geräte- bzw. App-Einstellungen widerrufen kannst.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">6. Übermittlung von E-Mails</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Bestätigungscodes, Passwort-Resets und ähnliche Transaktions-E-Mails versenden wir über den
        E-Mail-Dienstleister Resend. Hierbei werden deine E-Mail-Adresse sowie der E-Mail-Inhalt an
        Resend übermittelt, damit die Zustellung erfolgen kann. Rechtsgrundlage ist Art. 6 Abs. 1 lit. b
        DSGVO.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">7. Hosting</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Konto-, Profil- und Veranstaltungsdaten werden über Supabase gehostet und verarbeitet. Die
        Verwaltungsoberfläche für redaktionelle Inhalte wird über Vercel bereitgestellt. Mit beiden
        Anbietern bestehen bzw. werden, soweit erforderlich, Auftragsverarbeitungsverträge nach Art. 28
        DSGVO geschlossen.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">8. Cookies</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Die mobile App selbst verwendet keine Cookies. Für den Login-Bereich der redaktionellen
        Weboberfläche wird ein technisch notwendiges Session-Cookie gesetzt, das für die Anmeldung
        erforderlich ist.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">9. Speicherdauer</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Wir speichern deine Daten, solange dein Konto besteht. Nach Löschung deines Kontos (siehe Punkt
        11) werden deine personenbezogenen Daten gelöscht, soweit keine gesetzlichen
        Aufbewahrungspflichten entgegenstehen.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">10. Deine Rechte</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Du hast das Recht auf Auskunft (Art. 15 DSGVO), Berichtigung (Art. 16 DSGVO), Löschung (Art. 17
        DSGVO), Einschränkung der Verarbeitung (Art. 18 DSGVO), Datenübertragbarkeit (Art. 20 DSGVO)
        sowie Widerspruch gegen die Verarbeitung (Art. 21 DSGVO). Wende dich hierzu einfach an die oben
        genannte Kontaktadresse.
      </p>
      <p className="mt-2 text-sm leading-relaxed text-[#3a3a3c]">
        Außerdem hast du das Recht, dich bei einer Datenschutzaufsichtsbehörde zu beschweren, zum
        Beispiel beim Bayerischen Landesamt für Datenschutzaufsicht.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">11. Kontokündigung und Löschung</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Du kannst jederzeit die Löschung deines Kontos und der damit verbundenen personenbezogenen Daten
        verlangen, indem du uns über die oben genannte E-Mail-Adresse kontaktierst.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">12. Minderjährige</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Klangradar richtet sich nicht gezielt an Kinder. Personen unter 16 Jahren sollten die App nur mit
        Zustimmung eines Erziehungsberechtigten nutzen.
      </p>
    </div>
  );
}
