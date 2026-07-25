// Orchestriert einen Ingestion-Lauf über ALLE aktiven Quellen mit echter,
// begrenzter Nebenläufigkeit — löst run_all_active_sources() (SQL-Funktion,
// siehe 20260815000001_daily_ingestion_cron.sql) ab, die pro Quelle einen
// unbegrenzten, nicht aggregierten pg_net.http_post-Fire-and-forget-Request
// abgesetzt hat (keine Backpressure, kein gesammeltes Ergebnis).
//
// Ruft ingest-source's Kernlogik (runIngestion()) DIREKT auf, nicht per HTTP
// gegen sich selbst — vermeidet einen unnötigen Netzwerk-Umweg auf derselben
// Edge-Runtime. Der tägliche pg_cron-Job ruft künftig nur noch DIESE eine
// Funktion auf statt pro Quelle einzeln zu loopen.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// core.ts, NOT index.ts — index.ts has its own top-level Deno.serve() call,
// and importing it here would silently register it as this isolate's
// request handler too (see core.ts's file comment for the bug that caused).
import { runIngestion, SUPPORTED_TYPES } from "../ingest-source/core.ts";

// Bewusst niedrig gehalten: viele Quellen könnten dieselbe Ziel-Domain
// treffen (z.B. mehrere Gasteig-Säle unter derselben Basis-URL), eine hohe
// Parallelität würde robots.txt-Crawl-Delay-Erwartungen einzelner Quellen
// unterlaufen, auch wenn jede Quelle für sich genommen ihren eigenen Delay
// einhält (siehe crawlDelayMs in ingest-source/index.ts) — das gilt nur
// zwischen Paginierungs-Schritten DERSELBEN Quelle, nicht quellenübergreifend.
const CONCURRENCY = 5;

interface RunSummary {
  sourceId: string;
  status: string;
  error?: string;
}

Deno.serve(async (_req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // "manual" (and any other type ingest-source's SUPPORTED_TYPES doesn't
  // cover) is excluded here, not just inside runIngestion() — otherwise a
  // manual-only source (e.g. the admin's single-URL-import placeholder)
  // gets attempted and fails every single cron run forever, purely as noise.
  const { data: sources, error } = await supabase
    .from("sources")
    .select("id, last_run_at, crawl_frequency_minutes")
    .eq("status", "active")
    .in("type", Array.from(SUPPORTED_TYPES));

  if (error) {
    return jsonResponse({ error: `failed to load active sources: ${error.message}` }, 500);
  }

  // Architektur-Dokument Abschnitt 5.1: adaptives Crawl-Intervall. Bisher
  // wurde crawl_frequency_minutes von adjustCrawlFrequency() (siehe
  // ingest-source/index.ts) schon live kalibriert, aber NICHTS hier las den
  // Wert je — dieser tägliche Cron-Lauf holte trotzdem jede aktive Quelle,
  // egal ob sie sich seit Wochen nicht geändert hat oder stündlich
  // aktualisiert wird. Jetzt: eine Quelle ist "fällig", wenn last_run_at
  // fehlt (noch nie gelaufen) oder länger als crawl_frequency_minutes
  // zurückliegt (Default 1440 = täglich, deckt sich mit dem bisherigen
  // Cron-Rhythmus, wenn keine Kalibrierung vorliegt).
  const now = Date.now();
  const dueSources = (sources ?? []).filter(
    (s: { last_run_at: string | null; crawl_frequency_minutes: number | null }) => {
      if (!s.last_run_at) return true;
      const frequencyMs = (s.crawl_frequency_minutes ?? 1440) * 60_000;
      return now - new Date(s.last_run_at).getTime() >= frequencyMs;
    },
  );
  const skippedNotDue = (sources ?? []).length - dueSources.length;

  const ids = dueSources.map((s: { id: string }) => s.id);
  const results: RunSummary[] = [];

  let nextIndex = 0;
  async function worker() {
    while (nextIndex < ids.length) {
      const sourceId = ids[nextIndex++];
      try {
        const { body } = await runIngestion(supabase, sourceId);
        const status = typeof body.status === "string" ? body.status : "unknown";
        results.push({
          sourceId,
          status,
          error: typeof body.error === "string" ? body.error : undefined,
        });
      } catch (err) {
        results.push({
          sourceId,
          status: "failed",
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  const workerCount = Math.min(CONCURRENCY, ids.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));

  const succeeded = results.filter((r) => r.status === "success" || r.status === "partial").length;
  const skipped = results.filter((r) => r.status === "skipped_unchanged").length;
  const failed = results.filter((r) => r.status === "failed").length;

  return jsonResponse({
    total_active: (sources ?? []).length,
    due: ids.length,
    skipped_not_due: skippedNotDue,
    succeeded,
    skipped,
    failed,
    errors: results
      .filter((r) => r.status === "failed")
      .slice(0, 20)
      .map((r) => `${r.sourceId}: ${r.error ?? "unknown"}`),
  });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
