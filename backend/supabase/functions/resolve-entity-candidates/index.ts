// Batch-Nachlauf für die entity_candidates-Warteliste: die automatische
// KI-Entscheidung in enrich-event-references (siehe dort, flagEntityCandidate/
// autoCreateEntity) gilt nur für NEU erkannte Kandidaten ab ihrer Einführung
// — Kandidaten, die vorher schon in der Warteliste lagen, werden dadurch nie
// rückwirkend aufgelöst. Diese Function holt das nach: für jeden noch
// offenen person/ensemble-Kandidaten OHNE bereits vermerkten possible_match
// (Namensvetter-Risiko bleibt immer manuell) wird dieselbe Websuche+LLM-
// Anreicherung wie bei der Ersterkennung versucht (_shared/entityEnrichment.ts,
// mittlerweile DuckDuckGo statt des ausgeschöpften Tavily-Kontingents); ist
// das Ergebnis
// confident=true, wird der Stammdaten-Eintrag direkt angelegt und der
// Kandidat als "approved" markiert — sonst bleibt er unverändert in der
// Warteliste liegen (kein Blindes Ablehnen, das wäre eine stärkere,
// riskantere Behauptung als "unklar lassen").
//
// organizer-Kandidaten (aus discover-sources) bleiben bewusst außen vor:
// andere Anreicherungs-Heuristik nötig (Institution statt Person/Ensemble),
// noch nicht gebaut.
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 12)
// offene Kandidaten pro Lauf, mit begrenzter Nebenläufigkeit (siehe
// CONCURRENCY). Manuell auslösbar über den Button auf /entity-candidates im
// Admin-Dashboard, kein Cron (jeder Lauf kostet Tavily-/LLM-Credits pro
// geprüftem Namen).
//
// Sequentielle Verarbeitung + ein zu hohes Limit haben Supabases
// Edge-Function-Idle-Timeout (150s) gerissen (Tavily-Suche + LLM-Aufruf
// pro Kandidat braucht mehrere Sekunden) — der Button im Admin blieb dann
// einfach auf "KI prüft…" hängen, ohne dass je eine Antwort zurückkam.
// CONCURRENCY parallelisiert die Kandidaten wie in run-all-sources/index.ts,
// DEFAULT_LIMIT ist bewusst klein genug, um auch im ungünstigsten Fall
// (alle Kandidaten brauchen eine echte Tavily-Suche) sicher unter dem
// Timeout zu bleiben.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hasAnyAiProviderConfigured } from "../_shared/ai/router.ts";
import { enrichCandidateContext } from "../_shared/entityEnrichment.ts";
import { logSystemAction } from "../_shared/systemLog.ts";
import { recordFieldSource } from "../_shared/provenance.ts";

const DEFAULT_LIMIT = 12;
const CONCURRENCY = 4;

interface CandidateRow {
  id: string;
  entity_type: "person" | "ensemble";
  name: string;
  discovery_context: { possible_match?: unknown } | null;
}

Deno.serve(async (req) => {
  let body: { limit?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0 ? body.limit : DEFAULT_LIMIT;

  if (!hasAnyAiProviderConfigured()) {
    return jsonResponse({ error: "kein AI-Provider konfiguriert (siehe _shared/ai/router.ts)" }, 500);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // "Nie geprüft" zuerst, dann am längsten nicht geprüft — verhindert, dass
  // ein paar dauerhaft ambivalente Kandidaten am Anfang der Warteliste
  // (z.B. mit possible_match) für immer alle neueren Kandidaten dahinter
  // blockieren (siehe 20260826000001_entity_candidates_ai_checked_at.sql).
  // Ein reines "order by created_at" hätte bei jedem Aufruf wieder dieselben
  // paar unklaren Namen zuerst geliefert, nie die restliche Warteliste.
  const { data: candidates, error } = await supabase
    .from("entity_candidates")
    .select("id, entity_type, name, discovery_context")
    .eq("status", "pending")
    .in("entity_type", ["person", "ensemble"])
    .order("ai_last_checked_at", { ascending: true, nullsFirst: true })
    .order("created_at", { ascending: true })
    .limit(limit)
    .returns<CandidateRow[]>();

  if (error) {
    return jsonResponse({ error: `Kandidaten konnten nicht geladen werden: ${error.message}` }, 500);
  }

  const list = candidates ?? [];
  const results: Array<{ outcome: "approved" | "pending" | "error"; error?: string }> = [];

  // Begrenzte Nebenläufigkeit statt eines sequentiellen for-Loops (siehe
  // run-all-sources/index.ts für dasselbe Muster) — jeder Kandidat braucht
  // eine echte Tavily-Suche + LLM-Aufruf, sequentiell riss das bei größeren
  // Batches das 150s-Idle-Timeout der Edge Function.
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < list.length) {
      const candidate = list[nextIndex++];
      results.push(await processCandidate(supabase, candidate));
    }
  }
  const workerCount = Math.min(CONCURRENCY, list.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));

  const approved = results.filter((r) => r.outcome === "approved").length;
  const leftPending = results.filter((r) => r.outcome === "pending").length;
  const errors = results.filter((r) => r.outcome === "error").map((r) => r.error!);

  // Gesamtzahl noch offener Kandidaten NACH diesem Batch — ohne das sieht
  // jeder einzelne Klick bei einer großen Warteliste (z.B. 150+) wie
  // "immer dasselbe Ergebnis" aus, obwohl er tatsächlich Fortschritt macht.
  // Erlaubt dem Client außerdem zu erkennen, wann wirklich nichts mehr
  // offen ist (total_remaining_pending === 0), um eine Automatik-Schleife
  // zuverlässig zu stoppen statt an einer festen Klickzahl zu raten.
  const { count: totalRemainingPending } = await supabase
    .from("entity_candidates")
    .select("id", { count: "exact", head: true })
    .eq("status", "pending")
    .in("entity_type", ["person", "ensemble"]);

  return jsonResponse({
    processed: list.length,
    approved,
    left_pending: leftPending,
    total_remaining_pending: totalRemainingPending ?? 0,
    errors: errors.slice(0, 10),
  });
});

async function processCandidate(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  candidate: CandidateRow,
): Promise<{ outcome: "approved" | "pending" | "error"; error?: string }> {
  // Wird auf JEDEM Pfad gestempelt (auch pending/error) — sonst blockieren
  // dieselben unklaren/fehlerhaften Kandidaten für immer den Anfang der
  // Warteliste, siehe Migrationskommentar oben.
  const stamp = () => supabase.from("entity_candidates").update({ ai_last_checked_at: new Date().toISOString() }).eq("id", candidate.id);

  try {
    if (candidate.discovery_context?.possible_match) {
      await stamp();
      return { outcome: "pending" };
    }

    const enrichment = await enrichCandidateContext(candidate.entity_type, candidate.name);
    if (!enrichment) {
      await stamp();
      return { outcome: "pending" };
    }

    const table = candidate.entity_type === "person" ? "persons" : "ensembles";
    const slug = await generateUniqueSlug(supabase, table, candidate.name);
    const payload =
      candidate.entity_type === "person"
        ? { full_name: candidate.name, slug, is_verified: false, website_url: enrichment.websiteUrl }
        : { name: candidate.name, slug, type: "sonstiges", is_verified: false, website_url: enrichment.websiteUrl };

    const createdIdColumn = candidate.entity_type === "person" ? "created_person_id" : "created_ensemble_id";
    const { data: created, error: createError } = await supabase.from(table).insert(payload).select("id").single();
    if (createError || !created) {
      await stamp();
      return { outcome: "error", error: `"${candidate.name}": ${createError?.message ?? "kein Ergebnis"}` };
    }

    const { error: updateError } = await supabase
      .from("entity_candidates")
      .update({
        status: "approved",
        reviewed_at: new Date().toISOString(),
        ai_last_checked_at: new Date().toISOString(),
        [createdIdColumn]: created.id,
      })
      .eq("id", candidate.id);
    if (updateError) {
      return {
        outcome: "error",
        error: `"${candidate.name}" angelegt, aber Kandidat-Update fehlgeschlagen: ${updateError.message}`,
      };
    }

    await logSystemAction(supabase, candidate.entity_type, created.id, "ai_auto_approved", {
      name: candidate.name,
      entity_candidate_id: candidate.id,
      bio_snippet: enrichment.bioSnippet,
      batch: true,
    }, "system (AI-Entscheidung, Batch-Nachlauf)");

    // Gleiche Ergänzung wie in enrich-event-references' autoCreateEntity —
    // sonst taucht dieser automatisch angelegte Datensatz in /data-quality
    // nie mit einer Quelle auf.
    if (enrichment.websiteUrl) {
      await recordFieldSource(supabase, {
        entityType: candidate.entity_type,
        entityId: created.id,
        fieldName: "website_url",
        sourceUrl: enrichment.websiteUrl,
        sourceName: "Websuche (resolve-entity-candidates, automatisch angelegt)",
        confidence: "likely",
      });
    }

    return { outcome: "approved" };
  } catch (err) {
    await stamp();
    return { outcome: "error", error: `"${candidate.name}": ${err instanceof Error ? err.message : String(err)}` };
  }
}

async function generateUniqueSlug(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  table: "persons" | "ensembles",
  name: string,
): Promise<string> {
  const umlauts: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss", Ä: "ae", Ö: "oe", Ü: "ue" };
  let s = name;
  for (const [from, to] of Object.entries(umlauts)) s = s.split(from).join(to);
  const base = s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "") || "eintrag";

  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from(table).select("id").eq("slug", candidate).maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
