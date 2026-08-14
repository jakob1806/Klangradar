import { ContentReportsList } from "../content-reports/report-list";

export const dynamic = "force-dynamic";

export default function ContentReportsNativePage() {
  return (
    <ContentReportsList
      platform="native"
      title="Nutzer-Meldungen (Native)"
      description="Offene Datenfehler aus der nativen iOS-App prüfen, automatisch reparieren oder redaktionell abschließen."
    />
  );
}
