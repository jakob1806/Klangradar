import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolveVenueDuplicateAsDistinct, resolveVenueDuplicateAsMerged } from "./actions";

export const dynamic = "force-dynamic";

interface CandidateVenue {
  id: string;
  name: string;
  address_street: string;
  address_zip: string;
  address_city: string;
}

interface CandidateRow {
  id: string;
  similarity_score: number | null;
  match_reason: "proximity" | "name_similarity";
  created_at: string;
  venue_a: CandidateVenue | null;
  venue_b: CandidateVenue | null;
}

const MATCH_REASON_LABEL: Record<CandidateRow["match_reason"], string> = {
  proximity: "Räumliche Nähe",
  name_similarity: "Namensähnlichkeit",
};

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

export default async function VenueDuplicatesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("venue_duplicate_candidates")
    .select(
      `id, similarity_score, match_reason, created_at,
       venue_a:venues!venue_duplicate_candidates_venue_a_id_fkey(id, name, address_street, address_zip, address_city),
       venue_b:venues!venue_duplicate_candidates_venue_b_id_fkey(id, name, address_street, address_zip, address_city)`,
    )
    .eq("status", "pending")
    .order("similarity_score", { ascending: false })
    .returns<CandidateRow[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Venue-Duplikate-Review</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Kandidaten aus räumlicher Nähe (dieselbe Adresse/derselbe Gebäudekomplex) oder Namensähnlichkeit —
        wöchentlich automatisch erkannt (detect_venue_duplicate_candidates). Viele Treffer sind absichtlich
        verschiedene Säle desselben Gebäudes (z.&nbsp;B. mehrere Säle im Gasteig HP8) — kein automatischer
        Merge, jeder Fall braucht redaktionelle Bestätigung.
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
        <Link href="/duplicates/ensembles" className="text-neutral-500 underline hover:text-neutral-900">
          Ensemble-Duplikate →
        </Link>
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Venue-Duplikate nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((candidate) => (
              <div key={candidate.id} className="rounded-lg border border-neutral-200 bg-white p-4">
                <span className="text-xs text-neutral-400">
                  Gefunden {formatDate(candidate.created_at)} · {MATCH_REASON_LABEL[candidate.match_reason]}
                  {candidate.similarity_score != null ? ` (${(candidate.similarity_score * 100).toFixed(0)}%)` : ""}
                </span>
                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <VenueCard
                    venue={candidate.venue_a}
                    keepAction={
                      candidate.venue_a && candidate.venue_b
                        ? resolveVenueDuplicateAsMerged.bind(null, candidate.id, candidate.venue_a.id)
                        : undefined
                    }
                  />
                  <VenueCard
                    venue={candidate.venue_b}
                    keepAction={
                      candidate.venue_a && candidate.venue_b
                        ? resolveVenueDuplicateAsMerged.bind(null, candidate.id, candidate.venue_b.id)
                        : undefined
                    }
                  />
                </div>
                <p className="mt-2 text-xs text-neutral-400">
                  „Diese Version behalten&ldquo; löscht die jeweils andere Venue, alle Verknüpfungen (Events, Ensembles,
                  Favoriten, Bilder) wandern auf die behaltene Version.
                </p>
                <div className="mt-3 flex items-center justify-end gap-4">
                  <ConfirmButton
                    action={resolveVenueDuplicateAsDistinct.bind(null, candidate.id)}
                    confirmMessage="Diese beiden Venues als unterschiedlich markieren? Beide bleiben erhalten."
                    label="Als unterschiedlich markieren"
                    pendingLabel="Speichere…"
                    className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  />
                </div>
              </div>
            ))
          ) : (
            <div className="rounded-lg border border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine offenen Venue-Duplikate-Kandidaten.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function VenueCard({
  venue,
  keepAction,
}: {
  venue: CandidateVenue | null;
  keepAction?: () => Promise<void>;
}) {
  if (!venue) {
    return (
      <div className="rounded-md border border-neutral-100 bg-neutral-50 p-3 text-sm text-neutral-400">
        Venue nicht mehr vorhanden.
      </div>
    );
  }

  return (
    <div className="flex flex-col rounded-md border border-neutral-100 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{venue.name}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {venue.address_street}, {venue.address_zip} {venue.address_city}
      </p>
      {keepAction && (
        <ConfirmButton
          action={keepAction}
          confirmMessage={`„${venue.name}" behalten? Die jeweils andere Venue wird gelöscht.`}
          label="Diese Version behalten"
          pendingLabel="Führe zusammen…"
          className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
        />
      )}
    </div>
  );
}
