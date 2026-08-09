import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolvePersonDuplicateAsDistinct, resolvePersonDuplicateAsMerged } from "./actions";

export const dynamic = "force-dynamic";

interface CandidatePerson {
  id: string;
  full_name: string;
  birth_date: string | null;
  death_date: string | null;
  biography_de: string | null;
}

interface CandidateRow {
  id: string;
  created_at: string;
  ai_recommends_merge: boolean | null;
  ai_reasoning: string | null;
  person_a: CandidatePerson | null;
  person_b: CandidatePerson | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

export default async function PersonDuplicatesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("person_duplicate_candidates")
    .select(
      `id, created_at, ai_recommends_merge, ai_reasoning,
       person_a:persons!person_duplicate_candidates_person_a_id_fkey(id, full_name, birth_date, death_date, biography_de),
       person_b:persons!person_duplicate_candidates_person_b_id_fkey(id, full_name, birth_date, death_date, biography_de)`,
    )
    .eq("status", "pending")
    // KI-empfohlene Fälle zuerst — schnelle, eindeutige Bestätigungen sollen
    // nicht in unsicheren älteren Fällen untergehen.
    .order("ai_recommends_merge", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false })
    .returns<CandidateRow[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Personen-Duplikate-Review</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Kandidaten aus der Namensvarianten-Heuristik (resolve-person-duplicates) — alle landen hier zur redaktionellen
        Entscheidung, auch eindeutige Fälle (z.&nbsp;B. „J.S. Bach“ → „Johann Sebastian Bach“) werden nicht mehr
        automatisch zusammengeführt. Diese sind unten mit der KI-Einschätzung markiert und vorsortiert, sodass sie
        sich weiterhin schnell bestätigen lassen.
      </p>
      <p className="mt-2 text-sm">
        <Link href="/duplicates" className="text-neutral-500 underline hover:text-neutral-900">
          ← Event-Duplikate
        </Link>{" "}
        ·{" "}
        <Link href="/duplicates/works" className="text-neutral-500 underline hover:text-neutral-900">
          Werk-Duplikate
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

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Personen-Duplikate nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((candidate) => (
              <div key={candidate.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <span className="text-xs text-neutral-400">Gefunden {formatDate(candidate.created_at)}</span>
                {candidate.ai_recommends_merge && (
                  <p className="mt-2 rounded bg-emerald-50 px-2 py-1 text-xs text-emerald-800">
                    ✓ KI empfiehlt Zusammenführen
                    {candidate.ai_reasoning ? `: ${candidate.ai_reasoning}` : ""}
                  </p>
                )}
                {candidate.ai_recommends_merge === false && candidate.ai_reasoning && (
                  <p className="mt-2 rounded bg-neutral-50 px-2 py-1 text-xs text-neutral-500">
                    KI ist sich nicht sicher: {candidate.ai_reasoning}
                  </p>
                )}
                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <PersonCard
                    person={candidate.person_a}
                    keepAction={
                      candidate.person_a && candidate.person_b
                        ? resolvePersonDuplicateAsMerged.bind(null, candidate.id, candidate.person_a.id)
                        : undefined
                    }
                  />
                  <PersonCard
                    person={candidate.person_b}
                    keepAction={
                      candidate.person_a && candidate.person_b
                        ? resolvePersonDuplicateAsMerged.bind(null, candidate.id, candidate.person_b.id)
                        : undefined
                    }
                  />
                </div>
                <p className="mt-2 text-xs text-neutral-400">
                  „Diese Version behalten“ löscht die jeweils andere Person, alle Verknüpfungen (Werke, Mitwirkungen,
                  Favoriten) wandern auf die behaltene Version; der verworfene Name wird als Alias gespeichert.
                </p>
                <div className="mt-3 flex items-center justify-end gap-4">
                  <ConfirmButton
                    action={resolvePersonDuplicateAsDistinct.bind(null, candidate.id)}
                    confirmMessage="Diese beiden Personen als unterschiedlich markieren? Beide bleiben erhalten."
                    label="Als unterschiedlich markieren"
                    pendingLabel="Speichere…"
                    className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  />
                </div>
              </div>
            ))
          ) : (
            <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine offenen Personen-Duplikate-Kandidaten.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function PersonCard({
  person,
  keepAction,
}: {
  person: CandidatePerson | null;
  keepAction?: () => Promise<void>;
}) {
  if (!person) {
    return (
      <div className="border border-neutral-300 bg-neutral-50 p-3 text-sm text-neutral-400">
        Person nicht mehr vorhanden.
      </div>
    );
  }

  return (
    <div className="flex flex-col border border-neutral-300 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{person.full_name}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {person.birth_date ? `* ${person.birth_date}` : "Geburtsdatum unbekannt"}
        {person.death_date ? ` · † ${person.death_date}` : ""}
      </p>
      {person.biography_de && <p className="mt-2 text-xs text-neutral-600">{person.biography_de}</p>}
      {keepAction && (
        <ConfirmButton
          action={keepAction}
          confirmMessage={`„${person.full_name}“ behalten? Die jeweils andere Person wird gelöscht.`}
          label="Diese Version behalten"
          pendingLabel="Führe zusammen…"
          className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
        />
      )}
    </div>
  );
}
