import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolveWorkDuplicateAsDistinct, resolveWorkDuplicateAsMerged } from "./actions";

export const dynamic = "force-dynamic";

interface CandidateWork {
  id: string;
  title: string;
  catalog_number: string | null;
  key_signature: string | null;
  composer: { full_name: string } | null;
}

interface CandidateRow {
  id: string;
  similarity_score: number;
  created_at: string;
  work_a: CandidateWork | null;
  work_b: CandidateWork | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export default async function WorkDuplicatesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("work_duplicate_candidates")
    .select(
      `id, similarity_score, created_at,
       work_a:works!work_duplicate_candidates_work_a_id_fkey(id, title, catalog_number, key_signature, composer:persons(full_name)),
       work_b:works!work_duplicate_candidates_work_b_id_fkey(id, title, catalog_number, key_signature, composer:persons(full_name))`,
    )
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .returns<CandidateRow[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Werk-Duplikate-Review</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Kandidaten aus dem Fuzzy-Matching in enrich-event-references bestätigen oder verwerfen — Werke mit ähnlichem,
        aber nicht identischem Titel (z.&nbsp;B. mit/ohne Beiname), bei denen eine automatische Zusammenlegung zu
        riskant war.
      </p>
      <p className="mt-2 text-sm">
        <Link href="/duplicates" className="text-neutral-500 underline hover:text-neutral-900">
          ← Event-Duplikate
        </Link>{" "}
        ·{" "}
        <Link href="/duplicates/persons" className="text-neutral-500 underline hover:text-neutral-900">
          Personen-Duplikate
        </Link>{" "}
        ·{" "}
        <Link href="/duplicates/venues" className="text-neutral-500 underline hover:text-neutral-900">
          Venue-Duplikate
        </Link>{" "}
        ·{" "}
        <Link href="/duplicates/ensembles" className="text-neutral-500 underline hover:text-neutral-900">
          Ensemble-Duplikate →
        </Link>
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Werk-Duplikate nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((candidate) => (
              <div key={candidate.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <div className="flex items-center justify-between gap-4">
                  <span className="text-xs text-neutral-400">
                    Gefunden {formatDate(candidate.created_at)} · Ähnlichkeit{" "}
                    {(candidate.similarity_score * 100).toFixed(0)}%
                  </span>
                </div>
                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <WorkCard
                    label="Bereits vorhanden"
                    work={candidate.work_a}
                    keepAction={
                      candidate.work_a && candidate.work_b
                        ? resolveWorkDuplicateAsMerged.bind(null, candidate.id, candidate.work_a.id)
                        : undefined
                    }
                  />
                  <WorkCard
                    label="Neu angelegt"
                    work={candidate.work_b}
                    keepAction={
                      candidate.work_a && candidate.work_b
                        ? resolveWorkDuplicateAsMerged.bind(null, candidate.id, candidate.work_b.id)
                        : undefined
                    }
                  />
                </div>
                <p className="mt-2 text-xs text-neutral-400">
                  „Diese Version behalten“ löscht das jeweils andere Werk, alle Verlinkungen (Events, Programme,
                  Provenienz) wandern auf die behaltene Version.
                </p>
                <div className="mt-3 flex items-center justify-end gap-4">
                  <ConfirmButton
                    action={resolveWorkDuplicateAsDistinct.bind(null, candidate.id)}
                    confirmMessage="Diese beiden Werke als unterschiedlich markieren? Beide bleiben erhalten."
                    label="Als unterschiedlich markieren"
                    pendingLabel="Speichere…"
                    className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  />
                </div>
              </div>
            ))
          ) : (
            <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine offenen Werk-Duplikate-Kandidaten.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function WorkCard({
  label,
  work,
  keepAction,
}: {
  label: string;
  work: CandidateWork | null;
  keepAction?: () => Promise<void>;
}) {
  if (!work) {
    return (
      <div className="border border-neutral-300 bg-neutral-50 p-3 text-sm text-neutral-400">
        {label}: Werk nicht mehr vorhanden.
      </div>
    );
  }

  return (
    <div className="flex flex-col border border-neutral-300 bg-neutral-50 p-3">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">{label}</p>
      <p className="mt-1 text-sm font-medium text-neutral-900">{work.title}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {work.composer?.full_name ?? "Komponist unbekannt"}
        {work.catalog_number ? ` · ${work.catalog_number}` : ""}
        {work.key_signature ? ` · ${work.key_signature}` : ""}
      </p>
      {keepAction && (
        <ConfirmButton
          action={keepAction}
          confirmMessage={`„${work.title}“ behalten? Das jeweils andere Werk wird gelöscht.`}
          label="Diese Version behalten"
          pendingLabel="Führe zusammen…"
          className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
        />
      )}
    </div>
  );
}
