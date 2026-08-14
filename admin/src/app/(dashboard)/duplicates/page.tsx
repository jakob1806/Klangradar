import Link from "next/link";
import { DuplicateBulkSelection, DuplicateSelectCheckbox } from "@/components/duplicate-bulk-selection";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { resolveDuplicateAsDistinct, resolveDuplicateAsMerged, resolveDuplicatesAsDistinct } from "./actions";
import {
  resolvePersonDuplicateAsDistinct,
  resolvePersonDuplicateAsMerged,
  resolvePersonDuplicatesAsDistinct,
} from "./persons/actions";
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
                ? "border-b-2 border-[#0071e3] text-[#0071e3]"
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

interface CandidateWork {
  id: string;
  title: string;
  catalog_number: string | null;
  key_signature: string | null;
  composer: { full_name: string } | null;
}
interface WorkCandidateRow {
  id: string;
  similarity_score: number;
  created_at: string;
  work_a: CandidateWork | null;
  work_b: CandidateWork | null;
}

async function WorkTab({ supabase }: { supabase: Supa }) {
  const { data, error } = await supabase
    .from("work_duplicate_candidates")
    .select(
      `id, similarity_score, created_at,
       work_a:works!work_duplicate_candidates_work_a_id_fkey(id, title, catalog_number, key_signature, composer:persons(full_name)),
       work_b:works!work_duplicate_candidates_work_b_id_fkey(id, title, catalog_number, key_signature, composer:persons(full_name))`,
    )
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .returns<WorkCandidateRow[]>();

  if (error) return <ErrorNote message={error.message} />;
  if (!data?.length) return <EmptyNote label="Werk-Duplikate" />;

  return (
    <DuplicateBulkSelection ids={data.map((c) => c.id)} onDismissMany={resolveWorkDuplicatesAsDistinct}>
      <div className="flex flex-col gap-3">
        {data.map((candidate) => (
          <div key={candidate.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
            <div className="flex items-center justify-between gap-4">
              <span className="text-xs text-neutral-400">
                Gefunden {formatDate(candidate.created_at)} · Ähnlichkeit {(candidate.similarity_score * 100).toFixed(0)}%
              </span>
              <DuplicateSelectCheckbox id={candidate.id} label={candidate.work_a?.title ?? "Werk-Duplikat"} />
            </div>
            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <WorkCard label="Bereits vorhanden" work={candidate.work_a} keepAction={candidate.work_a && candidate.work_b ? resolveWorkDuplicateAsMerged.bind(null, candidate.id, candidate.work_a.id) : undefined} />
              <WorkCard label="Neu angelegt" work={candidate.work_b} keepAction={candidate.work_a && candidate.work_b ? resolveWorkDuplicateAsMerged.bind(null, candidate.id, candidate.work_b.id) : undefined} />
            </div>
            <p className="mt-2 text-xs text-neutral-400">
              „Diese Version behalten“ löscht das jeweils andere Werk, alle Verlinkungen wandern auf die behaltene Version.
            </p>
            <div className="mt-3 flex items-center justify-end gap-4">
              <InstantButton
                action={resolveWorkDuplicateAsDistinct.bind(null, candidate.id)}
                pendingLabel="Speichere…"
                className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
              >
                Als unterschiedlich markieren
              </InstantButton>
            </div>
          </div>
        ))}
      </div>
    </DuplicateBulkSelection>
  );
}

function WorkCard({ label, work, keepAction }: { label: string; work: CandidateWork | null; keepAction?: () => Promise<void> }) {
  if (!work) return <div className="border border-neutral-300 bg-neutral-50 p-3 text-sm text-neutral-400">{label}: Werk nicht mehr vorhanden.</div>;
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
        <InstantButton action={keepAction} pendingLabel="Führe zusammen…" className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50">
          Diese Version behalten
        </InstantButton>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Personen (inkl. Namensvetter-Kandidaten aus entity_candidates)
// ---------------------------------------------------------------------------

interface CandidatePerson {
  id: string;
  full_name: string;
  birth_date: string | null;
  death_date: string | null;
  biography_de: string | null;
}
interface PersonCandidateRow {
  id: string;
  created_at: string;
  ai_recommends_merge: boolean | null;
  ai_reasoning: string | null;
  person_a: CandidatePerson | null;
  person_b: CandidatePerson | null;
}
interface MergeCandidateRow {
  id: string;
  name: string;
  created_at: string;
  discovery_context: { possible_match?: { id: string; name: string; similarity: number } } | null;
}

async function PersonTab({ supabase }: { supabase: Supa }) {
  const [{ data, error }, { data: mergeCandidates }] = await Promise.all([
    supabase
      .from("person_duplicate_candidates")
      .select(
        `id, created_at, ai_recommends_merge, ai_reasoning,
         person_a:persons!person_duplicate_candidates_person_a_id_fkey(id, full_name, birth_date, death_date, biography_de),
         person_b:persons!person_duplicate_candidates_person_b_id_fkey(id, full_name, birth_date, death_date, biography_de)`,
      )
      .eq("status", "pending")
      .order("ai_recommends_merge", { ascending: false, nullsFirst: false })
      .order("created_at", { ascending: false })
      .returns<PersonCandidateRow[]>(),
    supabase
      .from("entity_candidates")
      .select("id, name, created_at, discovery_context")
      .eq("status", "pending")
      .eq("entity_type", "person")
      .not("discovery_context->possible_match", "is", null)
      .order("created_at", { ascending: false })
      .returns<MergeCandidateRow[]>(),
  ]);

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
        <h2 className="text-sm font-semibold text-neutral-700">Bestehende Personen-Duplikate</h2>
        {!data?.length ? (
          <div className="mt-3"><EmptyNote label="Personen-Duplikate" /></div>
        ) : (
          <div className="mt-3">
            <DuplicateBulkSelection ids={data.map((c) => c.id)} onDismissMany={resolvePersonDuplicatesAsDistinct}>
              <div className="flex flex-col gap-3">
                {data.map((candidate) => (
                  <div key={candidate.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                    <div className="flex items-center justify-between gap-4">
                      <span className="text-xs text-neutral-400">Gefunden {formatDate(candidate.created_at)}</span>
                      <DuplicateSelectCheckbox id={candidate.id} label={candidate.person_a?.full_name ?? "Personen-Duplikat"} />
                    </div>
                    {candidate.ai_recommends_merge && (
                      <p className="mt-2 rounded bg-emerald-50 px-2 py-1 text-xs text-emerald-800">
                        ✓ KI empfiehlt Zusammenführen{candidate.ai_reasoning ? `: ${candidate.ai_reasoning}` : ""}
                      </p>
                    )}
                    {candidate.ai_recommends_merge === false && candidate.ai_reasoning && (
                      <p className="mt-2 rounded bg-neutral-50 px-2 py-1 text-xs text-neutral-500">KI ist sich nicht sicher: {candidate.ai_reasoning}</p>
                    )}
                    <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                      <PersonCard person={candidate.person_a} keepAction={candidate.person_a && candidate.person_b ? resolvePersonDuplicateAsMerged.bind(null, candidate.id, candidate.person_a.id) : undefined} />
                      <PersonCard person={candidate.person_b} keepAction={candidate.person_a && candidate.person_b ? resolvePersonDuplicateAsMerged.bind(null, candidate.id, candidate.person_b.id) : undefined} />
                    </div>
                    <p className="mt-2 text-xs text-neutral-400">
                      „Diese Version behalten“ löscht die jeweils andere Person, Verknüpfungen wandern auf die behaltene Version.
                    </p>
                    <div className="mt-3 flex items-center justify-end gap-4">
                      <InstantButton action={resolvePersonDuplicateAsDistinct.bind(null, candidate.id)} pendingLabel="Speichere…" className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50">
                        Als unterschiedlich markieren
                      </InstantButton>
                    </div>
                  </div>
                ))}
              </div>
            </DuplicateBulkSelection>
          </div>
        )}
      </section>
    </div>
  );
}

function PersonCard({ person, keepAction }: { person: CandidatePerson | null; keepAction?: () => Promise<void> }) {
  if (!person) return <div className="border border-neutral-300 bg-neutral-50 p-3 text-sm text-neutral-400">Person nicht mehr vorhanden.</div>;
  return (
    <div className="flex flex-col border border-neutral-300 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{person.full_name}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {person.birth_date ? `* ${person.birth_date}` : "Geburtsdatum unbekannt"}
        {person.death_date ? ` · † ${person.death_date}` : ""}
      </p>
      {person.biography_de && <p className="mt-2 text-xs text-neutral-600">{person.biography_de}</p>}
      {keepAction && (
        <InstantButton action={keepAction} pendingLabel="Führe zusammen…" className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50">
          Diese Version behalten
        </InstantButton>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Ensemble (inkl. Namensvetter-Kandidaten aus entity_candidates)
// ---------------------------------------------------------------------------

interface CandidateEnsemble {
  id: string;
  name: string;
  type: string;
  founded_year: number | null;
  description_de: string | null;
}
interface EnsembleCandidateRow {
  id: string;
  similarity_score: number | null;
  created_at: string;
  ensemble_a: CandidateEnsemble | null;
  ensemble_b: CandidateEnsemble | null;
}

async function EnsembleTab({ supabase }: { supabase: Supa }) {
  const [{ data, error }, { data: mergeCandidates }] = await Promise.all([
    supabase
      .from("ensemble_duplicate_candidates")
      .select(
        `id, similarity_score, created_at,
         ensemble_a:ensembles!ensemble_duplicate_candidates_ensemble_a_id_fkey(id, name, type, founded_year, description_de),
         ensemble_b:ensembles!ensemble_duplicate_candidates_ensemble_b_id_fkey(id, name, type, founded_year, description_de)`,
      )
      .eq("status", "pending")
      .order("similarity_score", { ascending: false })
      .returns<EnsembleCandidateRow[]>(),
    supabase
      .from("entity_candidates")
      .select("id, name, created_at, discovery_context")
      .eq("status", "pending")
      .eq("entity_type", "ensemble")
      .not("discovery_context->possible_match", "is", null)
      .order("created_at", { ascending: false })
      .returns<MergeCandidateRow[]>(),
  ]);

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
        {!data?.length ? (
          <div className="mt-3"><EmptyNote label="Ensemble-Duplikate" /></div>
        ) : (
          <div className="mt-3">
            <DuplicateBulkSelection ids={data.map((c) => c.id)} onDismissMany={resolveEnsembleDuplicatesAsDistinct}>
              <div className="flex flex-col gap-3">
                {data.map((candidate) => (
                  <div key={candidate.id} className="rounded-lg border border-neutral-200 bg-white p-4">
                    <div className="flex items-center justify-between gap-4">
                      <span className="text-xs text-neutral-400">
                        Gefunden {formatDate(candidate.created_at)}
                        {candidate.similarity_score != null ? ` · Ähnlichkeit ${(candidate.similarity_score * 100).toFixed(0)}%` : ""}
                      </span>
                      <DuplicateSelectCheckbox id={candidate.id} label={candidate.ensemble_a?.name ?? "Ensemble-Duplikat"} />
                    </div>
                    <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                      <EnsembleCard ensemble={candidate.ensemble_a} keepAction={candidate.ensemble_a && candidate.ensemble_b ? resolveEnsembleDuplicateAsMerged.bind(null, candidate.id, candidate.ensemble_a.id) : undefined} />
                      <EnsembleCard ensemble={candidate.ensemble_b} keepAction={candidate.ensemble_a && candidate.ensemble_b ? resolveEnsembleDuplicateAsMerged.bind(null, candidate.id, candidate.ensemble_b.id) : undefined} />
                    </div>
                    <p className="mt-2 text-xs text-neutral-400">
                      „Diese Version behalten“ löscht das jeweils andere Ensemble, Verknüpfungen wandern auf die behaltene Version.
                    </p>
                    <div className="mt-3 flex items-center justify-end gap-4">
                      <InstantButton action={resolveEnsembleDuplicateAsDistinct.bind(null, candidate.id)} pendingLabel="Speichere…" className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50">
                        Als unterschiedlich markieren
                      </InstantButton>
                    </div>
                  </div>
                ))}
              </div>
            </DuplicateBulkSelection>
          </div>
        )}
      </section>
    </div>
  );
}

function EnsembleCard({ ensemble, keepAction }: { ensemble: CandidateEnsemble | null; keepAction?: () => Promise<void> }) {
  if (!ensemble) return <div className="rounded-md border border-neutral-100 bg-neutral-50 p-3 text-sm text-neutral-400">Ensemble nicht mehr vorhanden.</div>;
  return (
    <div className="flex flex-col rounded-md border border-neutral-100 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{ensemble.name}</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {ensemble.type}
        {ensemble.founded_year ? ` · gegründet ${ensemble.founded_year}` : ""}
      </p>
      {ensemble.description_de && <p className="mt-2 text-xs text-neutral-600">{ensemble.description_de}</p>}
      {keepAction && (
        <InstantButton action={keepAction} pendingLabel="Führe zusammen…" className="mt-2 self-start text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50">
          Diese Version behalten
        </InstantButton>
      )}
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
