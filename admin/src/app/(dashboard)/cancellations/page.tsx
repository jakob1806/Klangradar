import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { confirmCancellation, dismissCancellation } from "./actions";

export const dynamic = "force-dynamic";

interface CandidateEvent {
  id: string;
  title: string;
  start_datetime: string;
  venues: { name: string } | null;
}

interface CandidateRow {
  id: string;
  reason: string;
  created_at: string;
  event: CandidateEvent | null;
  source: { name: string } | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

export default async function CancellationsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("cancellation_candidates")
    .select(
      `id, reason, created_at,
       event:events(id, title, start_datetime, venues(name)),
       source:sources(name)`,
    )
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .returns<CandidateRow[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Absage-Review</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Veranstaltungen, die im letzten Ingestion-Lauf ihrer Quelle plötzlich fehlten — z.B. weil sie abgesagt
        wurden. Bestätigen setzt die Veranstaltung auf &quot;Abgesagt&quot;, Ablehnen lässt sie unverändert
        (falsch positiv, z.B. bei einer unvollständigen Quelle).
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Absage-Kandidaten nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((candidate) => (
              <div key={candidate.id} className="border-2 border-[#171717] bg-white p-4">
                <div className="flex items-center justify-between gap-4">
                  <span className="text-xs text-neutral-400">
                    Gefunden {formatDate(candidate.created_at)} · Quelle: {candidate.source?.name ?? "unbekannt"}
                  </span>
                </div>
                <div className="mt-3">
                  <EventCard event={candidate.event} />
                </div>
                <div className="mt-4 flex items-center justify-end gap-4">
                  <ConfirmButton
                    action={dismissCancellation.bind(null, candidate.id)}
                    confirmMessage="Als falsch positiv ablehnen? Die Veranstaltung bleibt unverändert bestehen."
                    label="Ablehnen"
                    pendingLabel="Speichere…"
                    className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  />
                  <ConfirmButton
                    action={confirmCancellation.bind(null, candidate.id)}
                    confirmMessage="Als abgesagt bestätigen? Die Veranstaltung wird für Nutzer:innen als 'Abgesagt' markiert."
                    label="Als abgesagt bestätigen"
                    pendingLabel="Speichere…"
                    className="text-sm font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
                  />
                </div>
              </div>
            ))
          ) : (
            <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine offenen Absage-Kandidaten.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function EventCard({ event }: { event: CandidateEvent | null }) {
  if (!event) {
    return (
      <div className="border border-neutral-300 bg-neutral-50 p-3 text-sm text-neutral-400">
        Event nicht mehr vorhanden.
      </div>
    );
  }

  return (
    <div className="border border-neutral-300 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{event.title}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {event.venues?.name ?? "Ort unbekannt"} · {formatDate(event.start_datetime)}
      </p>
    </div>
  );
}
