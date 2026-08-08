"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

export interface ResolveWithAiResult {
  status: "ok" | "failed";
  processed?: number;
  approved?: number;
  leftPending?: number;
  totalRemainingPending?: number;
  errors?: string[];
  error?: string;
}

// Ruft die resolve-entity-candidates Edge Function auf: Batch-Nachlauf für
// bereits wartende Kandidaten, die nie durch die automatische Entscheidung
// in enrich-event-references liefen (die gilt nur für neu erkannte Namen ab
// ihrer Einführung — Nutzer-Feedback: "ich muss immer noch alles selbst
// freigeben", weil die bestehende Warteliste davon unberührt blieb).
export async function resolveEntityCandidatesWithAi(): Promise<ResolveWithAiResult> {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Explizites Timeout knapp über dem 150s-Idle-Timeout der Edge Function
  // selbst — ohne das blieb der Button bei einem serverseitigen Timeout
  // ohne jede Rückmeldung auf "KI prüft…" hängen, statt einen Fehler zu
  // zeigen (siehe resolve-entity-candidates/index.ts für den eigentlichen
  // Fix: kleineres Default-Limit + Nebenläufigkeit).
  let res: Response;
  try {
    res = await fetch(`${baseUrl}/functions/v1/resolve-entity-candidates`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey ?? "",
        Authorization: `Bearer ${anonKey ?? ""}`,
      },
      body: JSON.stringify({}),
      signal: AbortSignal.timeout(155_000),
    });
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "TimeoutError";
    return {
      status: "failed",
      error: timedOut
        ? "Zeitüberschreitung — bitte erneut versuchen (Batch ist bewusst klein gehalten, sollte normalerweise schnell durchlaufen)."
        : `resolve-entity-candidates nicht erreichbar: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  let body: Record<string, unknown>;
  try {
    body = await res.json();
  } catch {
    return { status: "failed", error: `Unerwartete Antwort (HTTP ${res.status}).` };
  }

  if (!res.ok || body.error) {
    return { status: "failed", error: (body.error as string) ?? `HTTP ${res.status}` };
  }

  revalidatePath("/entity-candidates");

  return {
    status: "ok",
    processed: body.processed as number | undefined,
    approved: body.approved as number | undefined,
    leftPending: body.left_pending as number | undefined,
    totalRemainingPending: body.total_remaining_pending as number | undefined,
    errors: body.errors as string[] | undefined,
  };
}

// Slugify hier dupliziert statt aus den Deno-Functions importiert — die
// Admin-App (Next.js) und die Edge Functions (Deno) teilen keinen
// Modul-Raum, dieselbe kleine Funktion existiert auch in
// backend/supabase/functions/ingest-source/write.ts und
// enrich-event-references/index.ts.
function slugify(title: string): string {
  const umlauts: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss", Ä: "ae", Ö: "oe", Ü: "ue" };
  let s = title;
  for (const [from, to] of Object.entries(umlauts)) s = s.split(from).join(to);
  s = s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "");
  return s || "eintrag";
}

/** Kollisionssicherer Slug — hängt bei Bedarf "-2", "-3", ... an, statt
 * blind den rohen slugify()-Wert einzufügen. Bugfix (Nutzerfeedback:
 * "duplicate key value violates unique constraint persons_slug_key"):
 * approveEntityCandidate prüfte bisher gar nicht, ob der generierte Slug
 * schon existiert, bevor eingefügt wurde — ein zweiter Kandidat mit
 * gleichem/ähnlichem Namen (oder einer, dessen Name bereits als echte
 * Stammdaten-Zeile existiert, z.B. durch einen parallel laufenden
 * Anreicherungs-Schritt) ließ den rohen INSERT mit einer für die
 * Redaktion unverständlichen Postgres-Fehlermeldung scheitern. */
async function generateUniqueSlug(
  supabase: Awaited<ReturnType<typeof createClient>>,
  table: "persons" | "ensembles" | "organizers",
  name: string,
): Promise<string> {
  const base = slugify(name);
  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from(table).select("id").eq("slug", candidate).maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

const TABLE_FOR_ENTITY_TYPE = { person: "persons", ensemble: "ensembles", organizer: "organizers" } as const;
const NAME_COLUMN_FOR_ENTITY_TYPE = { person: "full_name", ensemble: "name", organizer: "name" } as const;

/** Prüft VOR jeder Neuanlage, ob schon eine Stammdaten-Zeile mit exakt
 * diesem Namen existiert — z.B. weil ein anderer Anreicherungsschritt
 * (Werk-Programm-Erkennung, ein anderer bereits genehmigter Kandidat mit
 * gleichem Namen) sie zwischenzeitlich angelegt hat. Statt dann blind
 * einen zweiten, duplizierten Eintrag zu versuchen (und an der
 * Slug-Eindeutigkeit zu scheitern), wird der Kandidat wie ein manuelles
 * "Zusammenführen" mit der bestehenden Zeile verknüpft. */
async function findExistingByName(
  supabase: Awaited<ReturnType<typeof createClient>>,
  entityType: "person" | "ensemble" | "organizer",
  name: string,
): Promise<string | null> {
  const { data } = await supabase
    .from(TABLE_FOR_ENTITY_TYPE[entityType])
    .select("id")
    .ilike(NAME_COLUMN_FOR_ENTITY_TYPE[entityType], name)
    .maybeSingle();
  return data?.id ?? null;
}

export async function rejectEntityCandidate(candidateId: string) {
  const supabase = await createClient();

  const { error } = await supabase
    .from("entity_candidates")
    .update({ status: "rejected", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "entity_candidate",
    entityId: candidateId,
    action: "rejected",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/entity-candidates");
}

// Legt die echte persons/ensembles/organizers-Zeile an (is_verified: false —
// unterscheidet sich bewusst von einer handkuratierten Stammdaten-Zeile),
// verlinkt den Kandidaten damit und markiert ihn als 'approved'. Verknüpft
// NICHT automatisch mit einem Event — das passiert erst, wenn eine echte
// Quelle (ingest-source) das Event tatsächlich einliest und dabei die neue
// Person/das neue Ensemble findet.
export async function approveEntityCandidate(candidateId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("entity_candidates")
    .select("entity_type, name")
    .eq("id", candidateId)
    .maybeSingle();
  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Kandidat nicht gefunden");
  }

  const entityType = (candidate.entity_type === "person" || candidate.entity_type === "ensemble"
    ? candidate.entity_type
    : "organizer") as "person" | "ensemble" | "organizer";
  const createdIdColumn = ({ person: "created_person_id", ensemble: "created_ensemble_id", organizer: "created_organizer_id" } as const)[
    entityType
  ];

  // Erst prüfen, ob längst eine Stammdaten-Zeile mit exakt diesem Namen
  // existiert (siehe generateUniqueSlug-Kommentar oben) — dann verknüpfen
  // statt einen zweiten, unnötigen Eintrag zu versuchen.
  const existingId = await findExistingByName(supabase, entityType, candidate.name);
  let newId: string;
  let linkedExisting = false;

  if (existingId) {
    newId = existingId;
    linkedExisting = true;
  } else {
    const slug = await generateUniqueSlug(supabase, TABLE_FOR_ENTITY_TYPE[entityType], candidate.name);
    if (entityType === "person") {
      const { data, error } = await supabase
        .from("persons")
        .insert({ full_name: candidate.name, slug, is_verified: false })
        .select("id")
        .single();
      if (error || !data) throw new Error(error?.message ?? "persons insert fehlgeschlagen");
      newId = data.id;
    } else if (entityType === "ensemble") {
      const { data, error } = await supabase
        .from("ensembles")
        .insert({ name: candidate.name, slug, type: "sonstiges", is_verified: false })
        .select("id")
        .single();
      if (error || !data) throw new Error(error?.message ?? "ensembles insert fehlgeschlagen");
      newId = data.id;
    } else {
      const { data, error } = await supabase
        .from("organizers")
        .insert({ name: candidate.name, slug })
        .select("id")
        .single();
      if (error || !data) throw new Error(error?.message ?? "organizers insert fehlgeschlagen");
      newId = data.id;
    }
  }

  const { error: updateError } = await supabase
    .from("entity_candidates")
    .update({ status: "approved", reviewed_at: new Date().toISOString(), [createdIdColumn]: newId })
    .eq("id", candidateId);
  if (updateError) throw new Error(updateError.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "entity_candidate",
    entityId: candidateId,
    action: linkedExisting ? "approved_linked_existing" : "approved_created",
    actor: user?.email ?? user?.id ?? "unknown",
    after: { [createdIdColumn]: newId, name: candidate.name },
  });

  revalidatePath("/entity-candidates");
}

// Für Kandidaten mit einem discovery_context.possible_match (Fuzzy-Match
// aus find_matching_person/find_matching_ensemble, siehe
// 20260722000002_find_matching_person_ensemble.sql): verlinkt den Kandidaten
// mit der BEREITS VORHANDENEN Person/dem Ensemble statt einen neuen
// Stammdaten-Eintrag anzulegen. Legt bewusst NICHTS in persons/ensembles an
// — der Hauptname der vorhandenen Zeile bleibt unverändert (Nutzeranfrage:
// "im Zweifel soll beim Zusammenführen der Hauptname nicht geändert werden,
// sondern das einfach nur als alternative Schreibweise hinzugefügt
// werden"); der Kandidatenname landet stattdessen als Alias in
// entity_aliases (20260907000001_field_provenance_and_aliases.sql), damit
// er z. B. bei der Suche weiter auffindbar bleibt.
export async function mergeEntityCandidate(candidateId: string, matchedEntityId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("entity_candidates")
    .select("entity_type, name")
    .eq("id", candidateId)
    .maybeSingle();
  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Kandidat nicht gefunden");
  }
  if (candidate.entity_type !== "person" && candidate.entity_type !== "ensemble") {
    throw new Error(`Zusammenführen nur für person/ensemble unterstützt, nicht "${candidate.entity_type}"`);
  }

  const createdIdColumn = candidate.entity_type === "person" ? "created_person_id" : "created_ensemble_id";
  const { error: updateError } = await supabase
    .from("entity_candidates")
    .update({ status: "approved", reviewed_at: new Date().toISOString(), [createdIdColumn]: matchedEntityId })
    .eq("id", candidateId);
  if (updateError) throw new Error(updateError.message);

  await supabase
    .from("entity_aliases")
    .insert({ entity_type: candidate.entity_type, entity_id: matchedEntityId, alias: candidate.name })
    .select("id")
    .maybeSingle(); // best effort — unique-Constraint-Konflikt (Alias existiert schon) ist kein Fehlerfall

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "entity_candidate",
    entityId: candidateId,
    action: "merged",
    actor: user?.email ?? user?.id ?? "unknown",
    after: { [createdIdColumn]: matchedEntityId, alias_added: candidate.name },
  });

  revalidatePath("/entity-candidates");
}

/** Mehrfachauswahl-Variante von approveEntityCandidate — für die
 * "hohe Konfidenz"-Kategorie (Score > 60%), die auf einen Schlag komplett
 * freigegeben werden kann, sowie für die manuelle Mehrfachauswahl der
 * übrigen Kandidaten. Einzelne Fehlschläge (z. B. Slug-Kollision) brechen
 * den restlichen Batch nicht ab. */
export async function bulkApproveEntityCandidates(candidateIds: string[]) {
  const errors: string[] = [];
  for (const id of candidateIds) {
    try {
      await approveEntityCandidate(id);
    } catch (err) {
      errors.push(err instanceof Error ? err.message : String(err));
    }
  }
  if (errors.length > 0) throw new Error(errors.join("; "));
}

export async function bulkRejectEntityCandidates(candidateIds: string[]) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("entity_candidates")
    .update({ status: "rejected", reviewed_at: new Date().toISOString() })
    .in("id", candidateIds);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  for (const id of candidateIds) {
    await logSystemAction(supabase, {
      entityType: "entity_candidate",
      entityId: id,
      action: "rejected",
      actor: user?.email ?? user?.id ?? "unknown",
    });
  }

  revalidatePath("/entity-candidates");
}
