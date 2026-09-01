import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

// Aggregiert nur die bereits vorhandenen Zählungen der einzelnen
// Review-/Meldungs-Seiten (review-queue/page.tsx, content-reports/
// report-list.tsx, reports/page.tsx) zu EINER "was ist gerade wichtig"-
// Übersicht ganz oben in der Navigation — keine neue Datenlogik, keine
// neue Optik: gleiche Zusammenfassungs-Karte wie in review-queue/page.tsx
// (rounded-xl border shadow-sm), nur mit mehr Karten und ohne die
// Detailtabelle darunter, die auf den Zielseiten schon existiert.
const REVIEW_STATUSES_TO_SHOW = ["needs_review", "needs_quick_check"] as const;

export default async function WichtigPage() {
  const supabase = await createClient();

  const [
    { count: entityCandidateCount },
    { count: duplicateCount },
    { count: cancellationCount },
    { count: lowConfidenceCount },
    { count: contentReportCount },
    { count: errorReportCount },
    { count: workCount },
    { count: graphLinkCount },
  ] = await Promise.all([
    supabase.from("entity_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("cancellation_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("events").select("id", { count: "exact", head: true }).in("review_status", REVIEW_STATUSES_TO_SHOW),
    supabase.from("content_reports").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("error_reports").select("id", { count: "exact", head: true }),
    supabase.from("works").select("id", { count: "exact", head: true }),
    supabase.from("event_works").select("event_id", { count: "exact", head: true }),
  ]);

  const summaryCards = [
    { href: "/review-queue", label: "Events mit niedrigem Confidence-Score", count: lowConfidenceCount ?? 0 },
    { href: "/entity-candidates", label: "Entity-Kandidaten", count: entityCandidateCount ?? 0 },
    { href: "/duplicates", label: "Duplikate", count: duplicateCount ?? 0 },
    { href: "/cancellations", label: "Absage-Kandidaten", count: cancellationCount ?? 0 },
    { href: "/content-reports", label: "Meldungen & Fehler", count: contentReportCount ?? 0 },
    { href: "/reports", label: "Fehlerberichte", count: errorReportCount ?? 0 },
  ];

  const totalOpen = summaryCards.reduce((sum, card) => sum + card.count, 0);

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Wichtig</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        {totalOpen > 0
          ? `${totalOpen} offene Punkte über alle Bereiche hinweg — Klick auf eine Kachel führt direkt zur jeweiligen Bearbeitungsansicht.`
          : "Aktuell nichts Dringendes offen."}
      </p>

      <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {summaryCards.map((card) => (
          <Link
            key={card.href}
            href={card.href}
            className="rounded-xl border border-black/[0.06] bg-white p-5 shadow-sm transition-colors hover:bg-black/[0.02]"
          >
            <p className="text-2xl font-semibold">{card.count}</p>
            <p className="type-label mt-1 !text-inherit opacity-70">{card.label}</p>
          </Link>
        ))}
      </div>

      <Link href="/knowledge-graph" className="group mt-8 grid overflow-hidden rounded-2xl bg-[#f1ede5] p-6 transition hover:bg-[#eee8dc] sm:grid-cols-[1fr_auto] sm:items-end sm:p-7">
        <div><p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8b2635]">Klangradar Datenbank</p><h2 className="mt-2 max-w-xl text-2xl font-semibold tracking-[-0.04em] text-[#1d1d1f]">Den Knowledge Graph pflegen und erkunden</h2><p className="mt-2 max-w-2xl text-sm leading-6 text-[#6f6a63]">{(workCount ?? 0).toLocaleString("de-DE")} Werke sind über {(graphLinkCount ?? 0).toLocaleString("de-DE")} Programme mit Aufführungen, Personen, Ensembles und Orten verbunden.</p></div>
        <span className="mt-5 text-sm font-semibold text-[#8b2635] transition-transform group-hover:translate-x-1 sm:mt-0">Graph öffnen →</span>
      </Link>
    </div>
  );
}
