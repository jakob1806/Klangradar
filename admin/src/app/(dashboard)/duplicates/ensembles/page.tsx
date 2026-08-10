import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolveEnsembleDuplicateAsDistinct, resolveEnsembleDuplicateAsMerged } from "./actions";

export const dynamic = "force-dynamic";

interface CandidateEnsemble {
  id: string;
  name: string;
  type: string;
  founded_year: number | null;
  description_de: string | null;
}

interface CandidateRow {
  id: string;
  similarity_score: number | null;
  created_at: string;
  ensemble_a: CandidateEnsemble | null;
  ensemble_b: CandidateEnsemble | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export default async function EnsembleDuplicatesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ensemble_duplicate_candidates")
    .select(
      `id, similarity_score, created_at,
       ensemble_a:ensembles!ensemble_duplicate_candidates_ensemble_a_id_fkey(id, name, type, founded_year, description_de),
       ensemble_b:ensembles!ensemble_duplicate_candidates_ensemble_b_id_fkey(id, name, type, founded_year, description_de)`,
    )
    .eq("status", "pending")
    .order("similarity_score", { ascending: false })
    .returns<CandidateRow[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Ensemble-Duplikate-Review</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Kandidaten aus Namensähnlichkeit — wöchentlich automatisch erkannt
        (detect_ensemble_duplicate_candidates). Ähnliche Namen bedeuten nicht zwangsläufig dasselbe Ensemble
        (z.&nbsp;B. „Bayerische Staatsoper&ldquo; vs. „Bayerisches Staatsorchester&ldquo; sind unterschiedliche
        Institutionen) — kein automatischer Merge.
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
        <Link href="/duplicates/works" className="text-neutral-500 underline hover:text-neutral-900">
          Werk-Duplikate
        </Link>{" "}
        ·{" "}
        <Link href="/duplicates/venues" className="text-neutral-500 underline hover:text-neutral-900">
          Venue-Duplikate
        </Link>
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Ensemble-Duplikate nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((candidate) => (
              <div key={candidate.id} className="rounded-lg border border-neutral-200 bg-white p-4">
                <span className="text-xs text-neutral-400">
                  Gefunden {formatDate(candidate.created_at)}
                  {candidate.similarity_score != null ? ` · Ähnlichkeit ${(candidate.similarity_score * 100).toFixed(0)}%` : ""}
                </span>
                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <EnsembleCard
                    ensemble={candidate.ensemble_a}
                    keepAction={
                      candidate.ensemble_a && candidate.ensemble_b
                        ? resolveEnsembleDuplicateAsMerged.bind(null, candidate.id, candidate.ensemble_a.id)
                        : undefined
                    }
                  />
                  <EnsembleCard
                    ensemble={candidate.ensemble_b}
                    keepAction={
                      candidate.ensemble_a && candidate.ensemble_b
                        ? resolveEnsembleDuplicateAsMerged.bind(null, candidate.id, candidate.ensemble_b.id)
                        : undefined
                    }
                  />
                </div>
                <p className="mt-2 text-xs text-neutral-400">
                  „Diese Version behalten&ldquo; löscht das jeweils andere Ensemble, alle Verknüpfungen (Mitwirkungen,
                  Favoriten, Bilder) wandern auf die behaltene Version.
                </p>
                <div className="mt-3 flex items-center justify-end gap-4">
                  <ConfirmButton
                    action={resolveEnsembleDuplicateAsDistinct.bind(null, candidate.id)}
                    confirmMessage="Diese beiden Ensembles als unterschiedlich markieren? Beide bleiben erhalten."
                    label="Als unterschiedlich markieren"
                    pendingLabel="Speichere…"
                    className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  />
                </div>
              </div>
            ))
          ) : (
            <div className="rounded-lg border border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine offenen Ensemble-Duplikate-Kandidaten.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function EnsembleCard({
  ensemble,
  keepAction,
}: {
  ensemble: CandidateEnsemble | null;
  keepAction?: () => Promise<void>;
}) {
  if (!ensemble) {
    return (
      <div className="rounded-md border border-neutral-100 bg-neutral-50 p-3 text-sm text-neutral-400">
        Ensemble nicht mehr vorhanden.
      </div>
    );
  }

  return (
    <div className="flex flex-col rounded-md border border-neutral-100 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{ensemble.name}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {ensemble.type}
        {ensemble.founded_year ? ` · gegründet ${ensemble.founded_year}` : ""}
      </p>
      {ensemble.description_de && <p className="mt-2 text-xs text-neutral-600">{ensemble.description_de}</p>}
      {keepAction && (
        <ConfirmButton
          action={keepAction}
          confirmMessage={`„${ensemble.name}" behalten? Das jeweils andere Ensemble wird gelöscht.`}
          label="Diese Version behalten"
          pendingLabel="Führe zusammen…"
          className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
        />
      )}
    </div>
  );
}
