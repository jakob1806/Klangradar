import Link from "next/link";
import { DuplicateBulkSelection, DuplicateSelectCheckbox } from "@/components/duplicate-bulk-selection";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { resolveDuplicateAsDistinct, resolveDuplicateAsMerged, resolveDuplicatesAsDistinct } from "./actions";
import {
  mergeConfidentPersonDuplicates,
  resolvePersonDuplicateAsDistinct,
  resolvePersonDuplicateAsMerged,
  resolvePersonDuplicatesAsDistinct,
} from "./persons/actions";
import { ComparePair, type PairSide, type Signal } from "./compare-pair";
import { DuplicateKeyboard } from "./duplicate-keyboard";
import {
  resolveEnsembleDuplicateAsDistinct,
  resolveEnsembleDuplicateAsMerged,
  resolveEnsembleDuplicatesAsDistinct,
} from "./ensembles/actions";
import {
  resolveVenueDuplicateAsDistinct,
  resolveVenueDuplicateAsMerged,
  resolveVenueDuplicatesAsDistinct,
} from "./venues/actions";
import {
  resolveWorkDuplicateAsDistinct,
  resolveWorkDuplicateAsMerged,
  resolveWorkDuplicatesAsDistinct,
} from "./works/actions";
import {
  approveEntityCandidate,
  rejectEntityCandidate,
  sendEntityCandidateToDuplicateReview,
} from "../entity-candidates/actions";
import { InstantButton } from "@/components/instant-button";

export const dynamic = "force-dynamic";

type DuplicateType = "work" | "person" | "ensemble" | "venue" | "event";

const TABS: { type: DuplicateType; label: string }[] = [
  { type: "work", label: "Werk" },
  { type: "person", label: "Personen" },
  { type: "ensemble", label: "Ensemble" },
  { type: "venue", label: "Venue" },
  { type: "event", label: "Veranstaltungen" },
];

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export default async function DuplicatesPage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string }>;
}) {
  const params = await searchParams;
  const activeType: DuplicateType = TABS.some((t) => t.type === params.type) ? (params.type as DuplicateType) : "work";

  const supabase = await createClient();
  const [
    { count: workCount },
    { count: personCount },
    { count: ensembleCount },
    { count: venueCount },
    { count: eventCount },
    { count: personMergeCount },
    { count: ensembleMergeCount },
  ] = await Promise.all([
    supabase.from("work_duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("person_duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("ensemble_duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("venue_duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("entity_candidates").select("id", { count: "exact", head: true }).eq("status", "pending").eq("entity_type", "person").not("discovery_context->possible_match", "is", null),
    supabase.from("entity_candidates").select("id", { count: "exact", head: true }).eq("status", "pending").eq("entity_type", "ensemble").not("discovery_context->possible_match", "is", null),
  ]);

  const counts: Record<DuplicateType, number> = {
    work: workCount ?? 0,
    person: (personCount ?? 0) + (personMergeCount ?? 0),
    ensemble: (ensembleCount ?? 0) + (ensembleMergeCount ?? 0),
    venue: venueCount ?? 0,
    event: eventCount ?? 0,
  };

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Duplikate</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Werk-, Personen-, Ensemble-, Venue- und Veranstaltungs-Duplikate an einem Ort — jeder Reiter zeigt nur die
        Kandidaten dieses Typs, mehrere lassen sich auswählen und auf einmal als unterschiedlich markieren.
        Zusammenführen bleibt pro Paar einzeln, weil dabei entschieden werden muss, welche Version bleibt.
      </p>

      <div className="mt-6 flex gap-1 border-b border-black/[0.06]">
        {TABS.map((tab) => (
          <Link
            key={tab.type}
            href={`/duplicates?type=${tab.type}`}
            className={`px-3 py-2 text-sm font-medium ${
              tab.type === activeType
                ? "border-b-2 border-[#2D2A6E] text-[#2D2A6E]"
                : "text-neutral-500 hover:text-neutral-800"
            }`}
          >
            {tab.label} {counts[tab.type] > 0 && <span className="ml-1 text-xs text-neutral-400">({counts[tab.type]})</span>}
          </Link>
        ))}
      </div>

      <div className="mt-6">
        {activeType === "work" && <WorkTab supabase={supabase} />}
        {activeType === "person" && <PersonTab supabase={supabase} />}
        {activeType === "ensemble" && <EnsembleTab supabase={supabase} />}
        {activeType === "venue" && <VenueTab supabase={supabase} />}
        {activeType === "event" && <EventTab supabase={supabase} />}
      </div>
    </div>
  );
}

type Supa = Awaited<ReturnType<typeof createClient>>;

// ---------------------------------------------------------------------------
// Werk
// ---------------------------------------------------------------------------

// Erweiterung (Claude Code, 29.10.2026): Prüfansicht aus
// admin_work_duplicate_review() — Paare mit Gegenbeweis (andere Opuszahl,
// Nummer, Tonart, Satz, Besetzung, Komponist) werden gar nicht erst
// vorgeschlagen.
type WorkSideData = {
  id: string; title: string; catalog_number: string | null; key_signature: string | null; composer: string | null;
  introduction: string | null; events: number; upcoming: number;
};
interface WorkReviewRow {
  candidate_id: string; confidence: number; similarity: number | null; created_at: string;
  a: WorkSideData; b: WorkSideData; same_catalog: boolean; same_composer: boolean;
}

function workSide(work: WorkSideData): PairSide {
  return {
    id: work.id,
    name: work.title,
    wikidata_id: null,
    showWikidata: false,
    facts: [work.composer ?? "Komponist:in unbekannt", work.catalog_number, work.key_signature].filter((value): value is string => Boolean(value)),
    stats: [
      { label: "Termine", value: work.events },
      { label: "kommend", value: work.upcoming },
    ],
    description: work.introduction,
    href: `/works/${work.id}`,
  };
}

function workSignals(row: WorkReviewRow): Signal[] {
  const signals: Signal[] = [];
  if (row.same_catalog) signals.push({ label: "gleiche Werkverzeichnisnummer", tone: "good" });
  if (row.same_composer) signals.push({ label: "gleiche:r Komponist:in", tone: "good" });
  else if (row.a.composer && row.b.composer) signals.push({ label: "andere:r Komponist:in", tone: "bad" });
  if (row.similarity != null) signals.push({ label: `Titel ${Math.round(row.similarity * 100)} % ähnlich`, tone: "neutral" });
  return signals;
}

async function WorkTab({ supabase }: { supabase: Supa }) {
  const { data: reviewData, error } = await supabase.rpc("admin_work_duplicate_review");
  const data = (reviewData ?? []) as WorkReviewRow[];

  if (error) return <ErrorNote message={error.message} />;
  if (!data.length) return <EmptyNote label="Werk-Duplikate" />;

  return (
    <>
      <div className="mb-3"><DuplicateKeyboard /></div>
      <DuplicateBulkSelection ids={data.map((c) => c.candidate_id)} onDismissMany={resolveWorkDuplicatesAsDistinct}>
        <div className="flex flex-col gap-2">
          {data.map((row) => (
            <ComparePair
              key={row.candidate_id}
              id={row.candidate_id}
              confidence={row.confidence}
              signals={workSignals(row)}
              a={workSide(row.a)}
              b={workSide(row.b)}
              keepA={resolveWorkDuplicateAsMerged.bind(null, row.candidate_id, row.a.id)}
              keepB={resolveWorkDuplicateAsMerged.bind(null, row.candidate_id, row.b.id)}
              distinct={resolveWorkDuplicateAsDistinct.bind(null, row.candidate_id)}
            />
          ))}
        </div>
      </DuplicateBulkSelection>
    </>
  );
}

// ---------------------------------------------------------------------------
// Personen (inkl. Namensvetter-Kandidaten aus entity_candidates)
// ---------------------------------------------------------------------------

interface MergeCandidateRow {
  id: string;
  name: string;
  created_at: string;
  discovery_context: { possible_match?: { id: string; name: string; similarity: number } } | null;
}

// Erweiterung (Claude Code, 29.10.2026): Prüfansicht aus
// admin_person_duplicate_review() — sortiert nach Konfidenz, mit Signalen.
type PersonSideData = {
  id: string; name: string; photo_url: string | null; birth_date: string | null; death_date: string | null;
  wikidata_id: string | null; instrument: string | null; roles: string[] | null; biography: string | null;
  events: number; upcoming: number; works: number; followers: number;
};
interface PersonReviewRow {
  candidate_id: string; reason: string | null; confidence: number; ai_recommends_merge: boolean | null; ai_reasoning: string | null;
  created_at: string; a: PersonSideData; b: PersonSideData; shared_events: number; shared_ensembles: number;
}

const PERSON_REASON: Record<string, string> = {
  same_wikidata: "gleiche Wikidata-ID",
  exact_name: "gleicher Name",
  extra_names: "zusätzliche Vornamen",
  similar_name: "Schreibvariante",
  surname_only: "nur Nachname",
};

const year = (date: string | null) => (date ? date.slice(0, 4) : null);

function personSide(person: PersonSideData): PairSide {
  const life = person.birth_date || person.death_date ? `${year(person.birth_date) ?? "?"}–${year(person.death_date) ?? ""}` : null;
  return {
    id: person.id,
    name: person.name,
    photo_url: person.photo_url,
    wikidata_id: person.wikidata_id,
    facts: [life, person.instrument ?? person.roles?.join(", ") ?? null].filter((value): value is string => Boolean(value)),
    stats: [
      { label: "Termine", value: person.events },
      { label: "kommend", value: person.upcoming },
      ...(person.works > 0 ? [{ label: "Werke", value: person.works }] : []),
      { label: "Follower", value: person.followers },
    ],
    description: person.biography,
    href: `/persons/${person.id}`,
  };
}

function personSignals(row: PersonReviewRow): Signal[] {
  const signals: Signal[] = [];
  if (row.reason && PERSON_REASON[row.reason]) signals.push({ label: PERSON_REASON[row.reason], tone: row.reason === "same_wikidata" || row.reason === "exact_name" ? "good" : "neutral" });
  if (row.a.wikidata_id && row.b.wikidata_id && row.a.wikidata_id === row.b.wikidata_id && row.reason !== "same_wikidata") signals.push({ label: "gleiche Wikidata-ID", tone: "good" });
  if (row.a.birth_date && row.b.birth_date) {
    signals.push(year(row.a.birth_date) === year(row.b.birth_date) ? { label: "Geburtsjahr gleich", tone: "good" } : { label: "Geburtsjahr abweichend", tone: "bad" });
  }
  if (row.shared_events > 0) signals.push({ label: `${row.shared_events}× im selben Konzert`, tone: "bad" });
  if (row.shared_ensembles > 0) signals.push({ label: "gleiche Ensembles", tone: "good" });
  if (row.ai_recommends_merge) signals.push({ label: "KI: zusammenführen", tone: "good" });
  return signals;
}

async function PersonTab({ supabase }: { supabase: Supa }) {
  const [{ data: reviewData, error }, { data: mergeCandidates }] = await Promise.all([
    supabase.rpc("admin_person_duplicate_review"),
    supabase
      .from("entity_candidates")
      .select("id, name, created_at, discovery_context")
      .eq("status", "pending")
      .eq("entity_type", "person")
      .not("discovery_context->possible_match", "is", null)
      .order("created_at", { ascending: false })
      .returns<MergeCandidateRow[]>(),
  ]);
  const data = (reviewData ?? []) as PersonReviewRow[];
  const confident = data.filter((row) => row.confidence >= 90).length;

  if (error) return <ErrorNote message={error.message} />;

  return (
    <div className="flex flex-col gap-8">
      {mergeCandidates && mergeCandidates.length > 0 && (
        <section>
          <h2 className="text-sm font-semibold text-neutral-700">Neu entdeckt, möglicherweise schon vorhanden</h2>
          <div className="mt-3 flex flex-col gap-3">
            {mergeCandidates.map((c) => (
              <MergeCandidateCard key={c.id} candidate={c} entityTypeLabel="Person" />
            ))}
          </div>
        </section>
      )}

      <section>
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="text-sm font-semibold text-neutral-700">Bestehende Personen-Duplikate</h2>
            <p className="text-xs text-neutral-500">
              Paare mit unterschiedlicher Wikidata-ID oder abweichenden Lebensdaten werden nicht mehr vorgeschlagen. Sortiert nach Konfidenz.
            </p>
          </div>
          {confident > 0 && (
            <InstantButton action={mergeConfidentPersonDuplicates} pendingLabel="Führe zusammen…" className="rounded-lg bg-[#2D2A6E] px-3 py-2 text-sm font-medium text-white hover:bg-[#38358a] disabled:opacity-50">
              Eindeutige zusammenführen ({confident})
            </InstantButton>
          )}
        </div>
        {!data.length ? (
          <div className="mt-3"><EmptyNote label="Personen-Duplikate" /></div>
        ) : (
          <div className="mt-3">
            <div className="mb-3"><DuplicateKeyboard /></div>
            <DuplicateBulkSelection ids={data.map((c) => c.candidate_id)} onDismissMany={resolvePersonDuplicatesAsDistinct}>
              <div className="flex flex-col gap-2">
                {data.map((row) => (
                  <ComparePair
                    key={row.candidate_id}
                    id={row.candidate_id}
                    confidence={row.confidence}
                    signals={personSignals(row)}
                    note={row.ai_reasoning}
                    a={personSide(row.a)}
                    b={personSide(row.b)}
                    keepA={resolvePersonDuplicateAsMerged.bind(null, row.candidate_id, row.a.id)}
                    keepB={resolvePersonDuplicateAsMerged.bind(null, row.candidate_id, row.b.id)}
                    distinct={resolvePersonDuplicateAsDistinct.bind(null, row.candidate_id)}
                  />
                ))}
              </div>
            </DuplicateBulkSelection>
          </div>
        )}
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Ensemble (inkl. Namensvetter-Kandidaten aus entity_candidates)
// ---------------------------------------------------------------------------

// Erweiterung (Claude Code, 29.10.2026): Prüfansicht aus
// admin_ensemble_duplicate_review().
type EnsembleSideData = {
  id: string; name: string; type: string | null; photo_url: string | null; founded_year: number | null;
  wikidata_id: string | null; description: string | null; kind: string; events: number; upcoming: number; followers: number;
};
interface EnsembleReviewRow {
  candidate_id: string; confidence: number; same_kind: boolean; created_at: string; a: EnsembleSideData; b: EnsembleSideData;
}

function ensembleSide(ensemble: EnsembleSideData): PairSide {
  return {
    id: ensemble.id,
    name: ensemble.name,
    photo_url: ensemble.photo_url,
    wikidata_id: ensemble.wikidata_id,
    facts: [ensemble.type, ensemble.founded_year ? `gegr. ${ensemble.founded_year}` : null].filter((value): value is string => Boolean(value)),
    stats: [
      { label: "Termine", value: ensemble.events },
      { label: "kommend", value: ensemble.upcoming },
      { label: "Follower", value: ensemble.followers },
    ],
    description: ensemble.description,
    href: `/ensembles/${ensemble.id}`,
  };
}

function ensembleSignals(row: EnsembleReviewRow): Signal[] {
  const signals: Signal[] = [];
  if (row.a.wikidata_id && row.a.wikidata_id === row.b.wikidata_id) signals.push({ label: "gleiche Wikidata-ID", tone: "good" });
  if (row.a.name.toLocaleLowerCase("de") === row.b.name.toLocaleLowerCase("de")) signals.push({ label: "gleicher Name", tone: "good" });
  signals.push(row.same_kind ? { label: row.a.kind ? `beide ${row.a.kind.replace(/,/g, " / ")}` : "gleiche Art", tone: "neutral" } : { label: "unterschiedliche Art", tone: "bad" });
  if (row.a.founded_year && row.b.founded_year && row.a.founded_year === row.b.founded_year) signals.push({ label: "gleiches Gründungsjahr", tone: "good" });
  return signals;
}

async function EnsembleTab({ supabase }: { supabase: Supa }) {
  const [{ data: reviewData, error }, { data: mergeCandidates }] = await Promise.all([
    supabase.rpc("admin_ensemble_duplicate_review"),
    supabase
      .from("entity_candidates")
      .select("id, name, created_at, discovery_context")
      .eq("status", "pending")
      .eq("entity_type", "ensemble")
      .not("discovery_context->possible_match", "is", null)
      .order("created_at", { ascending: false })
      .returns<MergeCandidateRow[]>(),
  ]);
  const data = (reviewData ?? []) as EnsembleReviewRow[];

  if (error) return <ErrorNote message={error.message} />;

  return (
    <div className="flex flex-col gap-8">
      {mergeCandidates && mergeCandidates.length > 0 && (
        <section>
          <h2 className="text-sm font-semibold text-neutral-700">Neu entdeckt, möglicherweise schon vorhanden</h2>
          <div className="mt-3 flex flex-col gap-3">
            {mergeCandidates.map((c) => (
              <MergeCandidateCard key={c.id} candidate={c} entityTypeLabel="Ensemble" />
            ))}
          </div>
        </section>
      )}

      <section>
        <h2 className="text-sm font-semibold text-neutral-700">Bestehende Ensemble-Duplikate</h2>
        <p className="text-xs text-neutral-500">Vorgeschlagen werden nur Ensembles derselben Art (Orchester, Chor, Ballett …) mit fast gleichem Namen oder gleicher Wikidata-ID.</p>
        {!data.length ? (
          <div className="mt-3"><EmptyNote label="Ensemble-Duplikate" /></div>
        ) : (
          <div className="mt-3">
            <div className="mb-3"><DuplicateKeyboard /></div>
            <DuplicateBulkSelection ids={data.map((c) => c.candidate_id)} onDismissMany={resolveEnsembleDuplicatesAsDistinct}>
              <div className="flex flex-col gap-2">
                {data.map((row) => (
                  <ComparePair
                    key={row.candidate_id}
                    id={row.candidate_id}
                    confidence={row.confidence}
                    signals={ensembleSignals(row)}
                    a={ensembleSide(row.a)}
                    b={ensembleSide(row.b)}
                    keepA={resolveEnsembleDuplicateAsMerged.bind(null, row.candidate_id, row.a.id)}
                    keepB={resolveEnsembleDuplicateAsMerged.bind(null, row.candidate_id, row.b.id)}
                    distinct={resolveEnsembleDuplicateAsDistinct.bind(null, row.candidate_id)}
                  />
                ))}
              </div>
            </DuplicateBulkSelection>
          </div>
        )}
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Namensvetter-Karte, gemeinsam für Personen/Ensemble
// ---------------------------------------------------------------------------

function MergeCandidateCard({ candidate, entityTypeLabel }: { candidate: MergeCandidateRow; entityTypeLabel: string }) {
  const match = candidate.discovery_context?.possible_match;
  if (!match) return null;
  return (
    <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
      <span className="text-xs text-neutral-400">Gefunden {formatDate(candidate.created_at)} · {entityTypeLabel}</span>
      <p className="mt-1 text-sm font-medium text-neutral-900">{candidate.name}</p>
      <p className="mt-2 rounded bg-amber-50 px-2 py-1 text-xs text-amber-800">
        Möglicherweise identisch mit „{match.name}“ ({Math.round(match.similarity * 100)}% Namens-Ähnlichkeit) — bereits
        vorhanden. „Zur Duplikat-Prüfung schicken“ legt „{candidate.name}“ als echten Datensatz an und stellt beide
        oben unter „Bestehende {entityTypeLabel}-Duplikate“ zur Auswahl, welche Version bleibt.
      </p>
      <div className="mt-4 flex items-center justify-end gap-4">
        <InstantButton action={rejectEntityCandidate.bind(null, candidate.id)} className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50">
          Ablehnen
        </InstantButton>
        <InstantButton action={sendEntityCandidateToDuplicateReview.bind(null, candidate.id, match.id)} className="text-sm font-medium text-amber-700 hover:text-amber-900 disabled:opacity-50" pendingLabel="Sende…">
          Zur Duplikat-Prüfung schicken
        </InstantButton>
        <InstantButton action={approveEntityCandidate.bind(null, candidate.id)} className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50">
          Trotzdem als neu anlegen
        </InstantButton>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Venue
// ---------------------------------------------------------------------------

interface CandidateVenue {
  id: string;
  name: string;
  address_street: string;
  address_zip: string;
  address_city: string;
}
interface VenueCandidateRow {
  id: string;
  similarity_score: number | null;
  match_reason: "proximity" | "name_similarity";
  created_at: string;
  venue_a: CandidateVenue | null;
  venue_b: CandidateVenue | null;
}
const MATCH_REASON_LABEL: Record<VenueCandidateRow["match_reason"], string> = {
  proximity: "Räumliche Nähe",
  name_similarity: "Namensähnlichkeit",
};

async function VenueTab({ supabase }: { supabase: Supa }) {
  const { data, error } = await supabase
    .from("venue_duplicate_candidates")
    .select(
      `id, similarity_score, match_reason, created_at,
       venue_a:venues!venue_duplicate_candidates_venue_a_id_fkey(id, name, address_street, address_zip, address_city),
       venue_b:venues!venue_duplicate_candidates_venue_b_id_fkey(id, name, address_street, address_zip, address_city)`,
    )
    .eq("status", "pending")
    .order("similarity_score", { ascending: false })
    .returns<VenueCandidateRow[]>();

  if (error) return <ErrorNote message={error.message} />;
  if (!data?.length) return <EmptyNote label="Venue-Duplikate" />;

  return (
    <DuplicateBulkSelection ids={data.map((c) => c.id)} onDismissMany={resolveVenueDuplicatesAsDistinct}>
      <div className="flex flex-col gap-3">
        {data.map((candidate) => (
          <div key={candidate.id} className="rounded-lg border border-neutral-200 bg-white p-4">
            <div className="flex items-center justify-between gap-4">
              <span className="text-xs text-neutral-400">
                Gefunden {formatDate(candidate.created_at)} · {MATCH_REASON_LABEL[candidate.match_reason]}
                {candidate.similarity_score != null ? ` (${(candidate.similarity_score * 100).toFixed(0)}%)` : ""}
              </span>
              <DuplicateSelectCheckbox id={candidate.id} label={candidate.venue_a?.name ?? "Venue-Duplikat"} />
            </div>
            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <VenueCard venue={candidate.venue_a} keepAction={candidate.venue_a && candidate.venue_b ? resolveVenueDuplicateAsMerged.bind(null, candidate.id, candidate.venue_a.id) : undefined} />
              <VenueCard venue={candidate.venue_b} keepAction={candidate.venue_a && candidate.venue_b ? resolveVenueDuplicateAsMerged.bind(null, candidate.id, candidate.venue_b.id) : undefined} />
            </div>
            <p className="mt-2 text-xs text-neutral-400">
              „Diese Version behalten“ löscht die jeweils andere Venue, Verknüpfungen wandern auf die behaltene Version.
            </p>
            <div className="mt-3 flex items-center justify-end gap-4">
              <InstantButton action={resolveVenueDuplicateAsDistinct.bind(null, candidate.id)} pendingLabel="Speichere…" className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50">
                Als unterschiedlich markieren
              </InstantButton>
            </div>
          </div>
        ))}
      </div>
    </DuplicateBulkSelection>
  );
}

function VenueCard({ venue, keepAction }: { venue: CandidateVenue | null; keepAction?: () => Promise<void> }) {
  if (!venue) return <div className="rounded-md border border-neutral-100 bg-neutral-50 p-3 text-sm text-neutral-400">Venue nicht mehr vorhanden.</div>;
  return (
    <div className="flex flex-col rounded-md border border-neutral-100 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{venue.name}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {venue.address_street}, {venue.address_zip} {venue.address_city}
      </p>
      {keepAction && (
        <InstantButton action={keepAction} pendingLabel="Führe zusammen…" className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50">
          Diese Version behalten
        </InstantButton>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Veranstaltungen
// ---------------------------------------------------------------------------

interface CandidateEvent {
  id: string;
  title: string;
  start_datetime: string;
  venues: { name: string } | null;
}
interface EventCandidateRow {
  id: string;
  similarity_score: number;
  created_at: string;
  event_a: CandidateEvent | null;
  event_b: CandidateEvent | null;
}

async function EventTab({ supabase }: { supabase: Supa }) {
  const { data, error } = await supabase
    .from("duplicate_candidates")
    .select(
      `id, similarity_score, created_at,
       event_a:events!duplicate_candidates_event_a_id_fkey(id, title, start_datetime, venues(name)),
       event_b:events!duplicate_candidates_event_b_id_fkey(id, title, start_datetime, venues(name))`,
    )
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .returns<EventCandidateRow[]>();

  if (error) return <ErrorNote message={error.message} />;
  if (!data?.length) return <EmptyNote label="Veranstaltungs-Duplikate" />;

  return (
    <DuplicateBulkSelection ids={data.map((c) => c.id)} onDismissMany={resolveDuplicatesAsDistinct}>
      <div className="flex flex-col gap-3">
        {data.map((candidate) => (
          <div key={candidate.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
            <div className="flex items-center justify-between gap-4">
              <span className="text-xs text-neutral-400">
                Gefunden {formatMunichDateTime(candidate.created_at)} · Ähnlichkeit {(candidate.similarity_score * 100).toFixed(0)}%
              </span>
              <DuplicateSelectCheckbox id={candidate.id} label={candidate.event_a?.title ?? "Veranstaltungs-Duplikat"} />
            </div>
            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <EventCard label="Bereits vorhanden" event={candidate.event_a} keepAction={candidate.event_a && candidate.event_b ? resolveDuplicateAsMerged.bind(null, candidate.id, candidate.event_a.id) : undefined} />
              <EventCard label="Neu von der Ingestion" event={candidate.event_b} keepAction={candidate.event_a && candidate.event_b ? resolveDuplicateAsMerged.bind(null, candidate.id, candidate.event_b.id) : undefined} />
            </div>
            <p className="mt-2 text-xs text-neutral-400">
              „Diese Version behalten“ löscht das jeweils andere Event, Verknüpfungen wandern auf die behaltene Version.
            </p>
            <div className="mt-3 flex items-center justify-end gap-4">
              <InstantButton action={resolveDuplicateAsDistinct.bind(null, candidate.id)} pendingLabel="Speichere…" className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50">
                Als unterschiedlich markieren
              </InstantButton>
            </div>
          </div>
        ))}
      </div>
    </DuplicateBulkSelection>
  );
}

function EventCard({ label, event, keepAction }: { label: string; event: CandidateEvent | null; keepAction?: () => Promise<void> }) {
  if (!event) return <div className="border border-neutral-300 bg-neutral-50 p-3 text-sm text-neutral-400">{label}: Event nicht mehr vorhanden.</div>;
  return (
    <div className="flex flex-col border border-neutral-300 bg-neutral-50 p-3">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">{label}</p>
      <p className="mt-1 text-sm font-medium text-neutral-900">{event.title}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {event.venues?.name ?? "Ort unbekannt"} · {formatMunichDateTime(event.start_datetime)}
      </p>
      {keepAction && (
        <InstantButton action={keepAction} pendingLabel="Führe zusammen…" className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50">
          Diese Version behalten
        </InstantButton>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------

function EmptyNote({ label }: { label: string }) {
  return (
    <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
      Keine offenen {label}-Kandidaten.
    </div>
  );
}

function ErrorNote({ message }: { message: string }) {
  return <p className="text-sm text-amber-700">Konnte Duplikate nicht laden: {message}</p>;
}
