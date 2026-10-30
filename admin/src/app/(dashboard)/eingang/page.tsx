import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

// Eingang (Nutzerwunsch 30.10.2026): EINE Liste für alles, was auf eine
// Entscheidung der Redaktion wartet — vorher auf sieben Menüpunkte verteilt.
// Zählt nur bestehende Warteschlangen; bearbeitet wird auf den Zielseiten.
type Queue = { href: string; label: string; hint: string; kind: string; count: number };

export default async function EingangPage({ searchParams }: { searchParams: Promise<{ art?: string }> }) {
  const { art } = await searchParams;
  const supabase = await createClient();
  const head = { count: "exact" as const, head: true };
  const [review, cancellations, reports, requests, claims, edits, duplicates, candidates] = await Promise.all([
    supabase.from("events").select("id", head).in("review_status", ["needs_review", "needs_quick_check"]),
    supabase.from("cancellation_candidates").select("id", head).eq("status", "pending"),
    supabase.from("content_reports").select("id", head).eq("status", "pending"),
    supabase.from("entity_requests").select("id", head).eq("status", "pending"),
    supabase.from("entity_claims").select("id", head).eq("status", "pending"),
    supabase.from("entity_edit_suggestions").select("id", head).eq("status", "pending"),
    supabase.from("duplicate_candidates").select("id", head).eq("status", "pending"),
    supabase.from("entity_candidates").select("id", head).eq("status", "pending"),
  ]);

  const queues: Queue[] = [
    { href: "/review-queue", label: "Termine prüfen", hint: "Niedrige Import-Sicherheit", kind: "Programm", count: review.count ?? 0 },
    { href: "/cancellations", label: "Mögliche Absagen", hint: "Von Quellen gemeldet", kind: "Programm", count: cancellations.count ?? 0 },
    { href: "/content-reports", label: "Meldungen & Fehler", hint: "Aus der App gemeldet", kind: "Nutzer", count: reports.count ?? 0 },
    { href: "/entity-requests", label: "Nutzeranfragen", hint: "Fehlende Personen, Ensembles, Orte", kind: "Nutzer", count: requests.count ?? 0 },
    { href: "/entity-claims", label: "Veranstalter-Claims", hint: "Profil beansprucht", kind: "Vertrauen", count: claims.count ?? 0 },
    { href: "/entity-edit-suggestions", label: "Profiländerungen", hint: "Vorschläge zu Profilen", kind: "Vertrauen", count: edits.count ?? 0 },
    { href: "/duplicates", label: "Duplikate", hint: "Mögliche Doppelungen", kind: "Daten", count: duplicates.count ?? 0 },
    { href: "/entity-candidates", label: "Entity-Kandidaten", hint: "Neue Namen aus Importen", kind: "Daten", count: candidates.count ?? 0 },
  ];
  const kinds = [...new Set(queues.map((q) => q.kind))];
  const shown = queues.filter((q) => !art || q.kind === art).sort((a, b) => Number(b.count > 0) - Number(a.count > 0) || b.count - a.count);
  const total = queues.reduce((sum, q) => sum + q.count, 0);

  return (
    <div className="p-8">
      <h1 className="text-2xl font-semibold tracking-tight text-neutral-900">Eingang</h1>
      <p className="mt-1 text-sm text-neutral-500">
        {total > 0 ? `${total.toLocaleString("de-DE")} offene Punkte in allen Warteschlangen.` : "Alles erledigt."}
      </p>
      <div className="mt-5 flex flex-wrap gap-1.5">
        {[undefined, ...kinds].map((kind) => (
          <Link
            key={kind ?? "alle"}
            href={kind ? `/eingang?art=${encodeURIComponent(kind)}` : "/eingang"}
            className={`rounded-full border px-3 py-1 text-[13px] ${art === kind ? "border-[#2D2A6E] bg-[#2D2A6E] text-white" : "border-neutral-200 text-neutral-700 hover:border-neutral-400"}`}
          >
            {kind ?? "Alle"}
          </Link>
        ))}
      </div>
      <ul className="mt-5 divide-y divide-neutral-100 overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
        {shown.map((queue) => (
          <li key={queue.href}>
            <Link href={queue.href} className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-neutral-50">
              <span className="min-w-0">
                <span className="block text-sm font-medium text-neutral-900">{queue.label}</span>
                <span className="block text-xs text-neutral-500">
                  {queue.kind} · {queue.hint}
                </span>
              </span>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-sm font-semibold tabular-nums ${queue.count > 0 ? "bg-[#2D2A6E]/10 text-[#2D2A6E]" : "text-neutral-400"}`}
              >
                {queue.count.toLocaleString("de-DE")}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
