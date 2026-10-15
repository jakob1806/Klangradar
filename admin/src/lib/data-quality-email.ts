import { portalEmail, type PortalEmail } from "@/lib/portal-email";

type SourceRow = { source: string; events: number; without_image: number; without_link: number; without_participants: number; without_program: number };
export type DataQualityReport = {
  upcoming_events: number;
  sources: SourceRow[];
  stale_sources: { name: string; last_run_at: string | null }[];
  pending_person_duplicates: number;
  pending_entity_candidates: number;
  pending_claims: number;
  persons_without_photo: number;
};

const pct = (part: number, total: number) => (total ? `${Math.round((part / total) * 100)} %` : "–");

/** Täglicher Datenqualitäts-Bericht an die Redaktion. */
export function dataQualityEmail(report: DataQualityReport): PortalEmail {
  const totals = report.sources.reduce(
    (acc, row) => ({ img: acc.img + row.without_image, link: acc.link + row.without_link, part: acc.part + row.without_participants, prog: acc.prog + row.without_program }),
    { img: 0, link: 0, part: 0, prog: 0 },
  );
  // Die Quellen mit den meisten Lücken zuerst.
  const worst = [...report.sources]
    .sort((a, b) => (b.without_image + b.without_participants + b.without_program) - (a.without_image + a.without_participants + a.without_program))
    .slice(0, 12);
  return portalEmail({
    subject: `Datenqualität: ${report.upcoming_events.toLocaleString("de-DE")} kommende Konzerte, ${totals.img} ohne Bild`,
    eyebrow: "Redaktion · Täglicher Bericht",
    title: "Datenqualität heute",
    paragraphs: [
      `${report.upcoming_events.toLocaleString("de-DE")} kommende Konzerte. Ohne Bild: ${totals.img} (${pct(totals.img, report.upcoming_events)}), ohne Mitwirkende: ${totals.part} (${pct(totals.part, report.upcoming_events)}), ohne Programm: ${totals.prog} (${pct(totals.prog, report.upcoming_events)}), ganz ohne Link: ${totals.link}.`,
      ...(report.stale_sources.length
        ? [`${report.stale_sources.length} aktive Quelle(n) seit über 2 Tagen nicht gelaufen: ${report.stale_sources.slice(0, 8).map((s) => s.name).join(", ")}${report.stale_sources.length > 8 ? " …" : ""}.`]
        : ["Alle aktiven Quellen sind in den letzten 2 Tagen gelaufen."]),
    ],
    facts: [
      ["Offene Personen-Duplikate", String(report.pending_person_duplicates)],
      ["Offene Entity-Kandidaten", String(report.pending_entity_candidates)],
      ["Offene Claims", String(report.pending_claims)],
      ["Personen ohne Foto", String(report.persons_without_photo)],
    ],
    table: [["Quelle", "Konzerte", "ohne Bild", "ohne Mitw.", "ohne Progr."], ...worst.map((r) => [r.source, String(r.events), String(r.without_image), String(r.without_participants), String(r.without_program)])],
    cta: { label: "Zur Datenqualität", href: "/data-quality" },
    footer: "Interne Benachrichtigung der Klangradar-Redaktion. Kommt täglich um 07:00 UTC.",
  });
}
