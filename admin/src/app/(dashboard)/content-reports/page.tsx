import { ContentReportsList } from "./report-list";

export const dynamic = "force-dynamic";

export default function ContentReportsPage() {
  return (
    <ContentReportsList
      platform="flutter"
      title="Nutzer-Meldungen (Flutter)"
      description="Offene Datenfehler aus der Flutter-App prüfen, automatisch reparieren oder redaktionell abschließen."
    />
  );
}
