import { ContentReportsList } from "../content-reports/report-list";

export const dynamic = "force-dynamic";

export default function ContentReportsNativePage() {
  return (
    <ContentReportsList
      platform="native"
      title="Nutzer-Meldungen (Native)"
      description='Von Nutzer:innen in der nativen iOS-App gemeldete Datenprobleme (falsches Bild, falsche Zeit, defekter Ticketlink etc.). Gleicher Ablauf wie bei den Flutter-Meldungen — eigene Kategorie, weil beide Apps unabhängig voneinander getestet/veröffentlicht werden und die Redaktion wissen soll, aus welcher App eine Meldung stammt.'
    />
  );
}
