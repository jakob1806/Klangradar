import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { LowConfidenceTable } from "./low-confidence-table";

export const dynamic = "force-dynamic";

// Architektur-Dokument Abschnitt 7: EINE Review-Queue statt vier getrennter
// Seiten, die man einzeln kennen/anklicken muss. Verlinkt weiterhin auf die
// bestehenden spezialisierten Seiten (entity-candidates/duplicates/
// cancellations behalten ihre eigenen Freigabe-Aktionen — die hier nur zu
// duplizieren würde vier Codepfade für dieselbe Sache schaffen), zeigt aber
// zusätzlich Events mit niedrigem import_confidence-Score, für die es bisher
// GAR KEINE eigene Ansicht gab (der Score wurde bisher nur berechnet und
// gespeichert, siehe 20260819000004_events_import_confidence.sql, aber
// nirgends redaktionell sichtbar gemacht). Filtert über review_status statt
// eines global fixen Scores — die Triage-Schwellwerte sind pro Quelle
// kalibriert (sources.confidence_thresholds, siehe ingest-source/write.ts
// reviewStatusForScore()), ein globaler Cutoff hier würde das wieder blind
// dafür machen.
const REVIEW_STATUSES_TO_SHOW = ["needs_review", "needs_quick_check"] as const;

interface LowConfidenceEventRow {
  id: string;
  title: string;
  start_datetime: string;
  status: string;
  import_confidence: number;
  venue: { name: string } | null;
}

export default async function ReviewQueuePage() {
  const supabase = await createClient();

  const [
    { count: entityCandidateCount },
    { count: duplicateCount },
    { count: cancellationCount },
    { data: lowConfidenceEvents, error: lowConfidenceError },
  ] = await Promise.all([
    supabase.from("entity_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("cancellation_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase
      .from("events")
      .select("id, title, start_datetime, status, import_confidence, venue:venues(name)")
      .in("review_status", REVIEW_STATUSES_TO_SHOW)
      .order("import_confidence", { ascending: true })
      .limit(30)
      .returns<LowConfidenceEventRow[]>(),
  ]);

  const summaryCards = [
    { href: "/entity-candidates", label: "Entity-Kandidaten", count: entityCandidateCount ?? 0 },
    { href: "/duplicates", label: "Duplikate", count: duplicateCount ?? 0 },
    { href: "/cancellations", label: "Absage-Kandidaten", count: cancellationCount ?? 0 },
  ];

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Review-Queue</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Alle offenen redaktionellen Prüfpunkte an einem Ort.
      </p>

      <div className="mt-6 grid grid-cols-3 gap-4">
        {summaryCards.map((card) => (
          <Link
            key={card.href}
            href={card.href}
            className="border-2 border-[#171717] bg-white p-5 hover:bg-[#171717] hover:text-white"
          >
            <p className="text-2xl font-semibold">{card.count}</p>
            <p className="type-label mt-1 !text-inherit opacity-70">{card.label}</p>
          </Link>
        ))}
      </div>

      <h2 className="type-label mt-10">
        Events mit niedrigem Confidence-Score (quellenspezifisch kalibriert)
      </h2>

      {lowConfidenceError && (
        <p className="mt-4 text-sm text-amber-700">Konnte Events nicht laden: {lowConfidenceError.message}</p>
      )}

      {!lowConfidenceError && (
        <div className="mt-4">
          <LowConfidenceTable
            events={(lowConfidenceEvents ?? []).map((e) => ({
              id: e.id,
              title: e.title,
              start_datetime: e.start_datetime,
              status: e.status,
              import_confidence: e.import_confidence,
              venueName: e.venue?.name ?? null,
            }))}
          />
        </div>
      )}
    </div>
  );
}
