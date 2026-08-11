import { ContentReportsList } from "./report-list";

export const dynamic = "force-dynamic";

export default function ContentReportsPage() {
  return (
    <ContentReportsList
      platform="flutter"
      title="Nutzer-Meldungen (Flutter)"
      description='Von Nutzer:innen in der Flutter-App gemeldete Datenprobleme (falsches Bild, falsche Zeit, defekter Ticketlink etc.). Der ursprüngliche redaktionelle Fluss ändert nie automatisch Daten — "Automatisch fixen" ist ein separater, vorsichtig geprüfter Weg (Feld-Allowlist, Beleg-Zitat aus der echten Quellseite nötig, bei fehlender Quell-URL zusätzlich eigene Websuche), der bei Erfolg direkt speichert und immer einen Diagnose-Bericht hinterlässt. Läuft zusätzlich alle 30 Minuten automatisch für noch nie versuchte Meldungen.'
    />
  );
}
