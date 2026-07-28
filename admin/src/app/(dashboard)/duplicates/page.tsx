import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolveDuplicateAsDistinct, resolveDuplicateAsMerged } from "./actions";

export const dynamic = "force-dynamic";

interface CandidateEvent {
  id: string;
  title: string;
  start_datetime: string;
  venues: { name: string } | null;
}

interface CandidateRow {
  id: string;
  similarity_score: number;
  created_at: string;
  event_a: CandidateEvent | null;
  event_b: CandidateEvent | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

export default async function DuplicatesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("duplicate_candidates")
    .select(
      `id, similarity_score, created_at,
       event_a:events!duplicate_candidates_event_a_id_fkey(id, title, start_datetime, venues(name)),
       event_b:events!duplicate_candidates_event_b_id_fkey(id, title, start_datetime, venues(name))`,
    )
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .returns<CandidateRow[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Duplikate-Review</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Kandidaten aus dem Fuzzy-Matching der Ingestion-Pipeline bestätigen oder verwerfen.
      </p>
      <p className="mt-2 text-sm">
        <Link href="/duplicates/persons" className="text-neutral-500 underline hover:text-neutral-900">
          Personen-Duplikate
        </Link>{" "}
        ·{" "}
        <Link href="/duplicates/works" className="text-neutral-500 underline hover:text-neutral-900">
          Werk-Duplikate →
        </Link>
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Duplikate nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((candidate) => (
              <div key={candidate.id} className="rounded-lg border border-neutral-200 bg-white p-4">
                <div className="flex items-center justify-between gap-4">
                  <span className="text-xs text-neutral-400">
                    Gefunden {formatDate(candidate.created_at)} · Ähnlichkeit {(candidate.similarity_score * 100).toFixed(0)}%
                  </span>
                </div>
                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <EventCard
                    label="Bereits vorhanden"
                    event={candidate.event_a}
                    keepAction={
                      candidate.event_a && candidate.event_b
                        ? resolveDuplicateAsMerged.bind(null, candidate.id, candidate.event_a.id)
                        : undefined
                    }
                  />
                  <EventCard
                    label="Neu von der Ingestion"
                    event={candidate.event_b}
                    keepAction={
                      candidate.event_a && candidate.event_b
                        ? resolveDuplicateAsMerged.bind(null, candidate.id, candidate.event_b.id)
                        : undefined
                    }
                  />
                </div>
                <p className="mt-2 text-xs text-neutral-400">
                  „Diese Version behalten“ löscht das jeweils andere Event, alle Verknüpfungen (Programm, Favoriten,
                  Tags, Tickets) wandern auf die behaltene Version.
                </p>
                <div className="mt-3 flex items-center justify-end gap-4">
                  <ConfirmButton
                    action={resolveDuplicateAsDistinct.bind(null, candidate.id)}
                    confirmMessage="Diese beiden Veranstaltungen als unterschiedlich markieren? Beide bleiben erhalten."
                    label="Als unterschiedlich markieren"
                    pendingLabel="Speichere…"
                    className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  />
                </div>
              </div>
            ))
          ) : (
            <div className="rounded-lg border border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine offenen Duplikate-Kandidaten.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function EventCard({
  label,
  event,
  keepAction,
}: {
  label: string;
  event: CandidateEvent | null;
  keepAction?: () => Promise<void>;
}) {
  if (!event) {
    return (
      <div className="rounded-md border border-neutral-100 bg-neutral-50 p-3 text-sm text-neutral-400">
        {label}: Event nicht mehr vorhanden.
      </div>
    );
  }

  return (
    <div className="flex flex-col rounded-md border border-neutral-100 bg-neutral-50 p-3">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">{label}</p>
      <p className="mt-1 text-sm font-medium text-neutral-900">{event.title}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {event.venues?.name ?? "Ort unbekannt"} · {formatDate(event.start_datetime)}
      </p>
      {keepAction && (
        <ConfirmButton
          action={keepAction}
          confirmMessage={`„${event.title}“ behalten? Das jeweils andere Event wird gelöscht.`}
          label="Diese Version behalten"
          pendingLabel="Führe zusammen…"
          className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
        />
      )}
    </div>
  );
}
