import { createClient } from "@/lib/supabase/server";
import { ResolveWithAiButton } from "./resolve-with-ai-button";
import { CandidateList, type UiCandidate } from "./candidate-list";

export const dynamic = "force-dynamic";

const ENTITY_TYPE_LABEL: Record<string, string> = {
  person: "Person",
  ensemble: "Ensemble",
  organizer: "Institution",
};

const HIGH_CONFIDENCE_THRESHOLD = 60;

// Vollständig aussehender Name: mindestens zwei durch Leerzeichen getrennte,
// groß beginnende Wortteile (z. B. "Anna-Maria Schmidt", "Jean-Paul Fitoussi"),
// keine Ziffern — grobe Heuristik gegen Institutions-/Ensemble-artige Namen
// oder unvollständige Fragmente, kein Anspruch auf sprachliche Korrektheit.
const LOOKS_LIKE_FULL_NAME = /^[A-ZÀ-Ý][\wÀ-ÿ'-]*(\s+[A-ZÀ-Ý][\wÀ-ÿ'-]*)+$/;

interface CandidateRow {
  id: string;
  entity_type: string;
  name: string;
  suggested_event_title: string | null;
  suggested_event_start_datetime: string | null;
  source_url: string | null;
  created_at: string;
  venue: { name: string } | null;
  discovery_context: {
    tavily?: { bioSnippet: string | null; websiteUrl: string | null };
    possible_match?: { id: string; name: string; similarity: number };
  } | null;
}

// Grober Konfidenz-Score dafür, wie sicher ein NEUER (kein Zusammenführen-)
// Kandidat tatsächlich eine echte, in München relevante Person/ein echtes
// Ensemble ist — Nutzeranfrage: "score einfügen, bei dem alle mit über 60%
// in eine eigene Kategorie gesetzt werden, die man direkt sammelt
// genehmigen kann". Es gibt keinen gespeicherten Score in der DB, daher
// hier aus den bereits vorhandenen Anreicherungs-Signalen abgeleitet:
// KI-Websuche (Tavily) hat eine Kurzbiografie bzw. eine offizielle Website
// gefunden (starkes Signal: die Person/das Ensemble existiert nachweislich)
// plus ob der Name wie ein vollständiger Name aussieht (schwaches Signal).
function candidateScore(row: CandidateRow): number {
  let score = 0;
  if (row.discovery_context?.tavily?.bioSnippet) score += 40;
  if (row.discovery_context?.tavily?.websiteUrl) score += 30;
  if (LOOKS_LIKE_FULL_NAME.test(row.name.trim())) score += 30;
  return score;
}

function toUiCandidate(row: CandidateRow): UiCandidate {
  return {
    id: row.id,
    entityType: row.entity_type,
    name: row.name,
    suggestedEventTitle: row.suggested_event_title,
    suggestedEventStart: row.suggested_event_start_datetime,
    venueName: row.venue?.name ?? null,
    sourceUrl: row.source_url,
    createdAt: row.created_at,
    bioSnippet: row.discovery_context?.tavily?.bioSnippet ?? null,
    websiteUrl: row.discovery_context?.tavily?.websiteUrl ?? null,
    possibleMatch: row.discovery_context?.possible_match ?? null,
    score: candidateScore(row),
  };
}

export default async function EntityCandidatesPage() {
  const supabase = await createClient();
  const [{ data, error }, { count: aiApprovedCount }] = await Promise.all([
    supabase
      .from("entity_candidates")
      .select(
        `id, entity_type, name, suggested_event_title, suggested_event_start_datetime, source_url, created_at,
         discovery_context, venue:venues(name)`,
      )
      .eq("status", "pending")
      .order("created_at", { ascending: false })
      .returns<CandidateRow[]>(),
    supabase.from("system_logs").select("id", { count: "exact", head: true }).eq("action", "ai_auto_approved"),
  ]);

  const pendingByType = (data ?? []).reduce<Record<string, number>>((acc, c) => {
    acc[c.entity_type] = (acc[c.entity_type] ?? 0) + 1;
    return acc;
  }, {});

  return (
    <div className="p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Entity-Kandidaten</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Bisher unbekannte Personen/Ensembles/Institutionen aus der Ingestion — vor dem Anlegen in den Stammdaten
            hier prüfen und freigeben. Neue Personen/Ensembles-Kandidaten werden automatisch von der KI entschieden,
            wenn sie eindeutig sind; der Button unten holt das für schon länger wartende Kandidaten nach.
          </p>
          <p className="mt-2 text-xs text-neutral-500">
            {data?.length ?? 0} insgesamt offen (
            {Object.entries(pendingByType)
              .map(([type, count]) => `${count} ${ENTITY_TYPE_LABEL[type] ?? type}`)
              .join(", ") || "keine"}
            ) · {aiApprovedCount ?? 0} bisher von der KI automatisch angelegt
          </p>
        </div>
        <ResolveWithAiButton />
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Kandidaten nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6">
          <CandidateList
            mergeCandidates={(data ?? []).filter((c) => c.discovery_context?.possible_match).map(toUiCandidate)}
            highConfidence={(data ?? [])
              .filter((c) => !c.discovery_context?.possible_match && candidateScore(c) >= HIGH_CONFIDENCE_THRESHOLD)
              .map(toUiCandidate)}
            lowConfidence={(data ?? [])
              .filter((c) => !c.discovery_context?.possible_match && candidateScore(c) < HIGH_CONFIDENCE_THRESHOLD)
              .map(toUiCandidate)}
          />
        </div>
      )}
    </div>
  );
}
