// Supabase Edge Function: Admin fügt eine einzelne URL ein (ein Konzert
// ODER ein ganzes Programm mit mehreren Terminen), diese Funktion extrahiert
// Event(s) daraus und legt sie als Entwürfe an — reuses die bestehende
// Ingestion-Pipeline (Schema.org-Parser, Venue-Fuzzy-Match, Event-Dedupe aus
// ingest-source/) statt eine Parallelstruktur aufzubauen.
//
// Zwei-stufige Extraktion:
//  1. Schema.org (JSON-LD) — kostenlos, zuverlässig, deckt die meisten
//     größeren Ticketing-/Venue-Seiten ab (viele pflegen strukturierte
//     Daten fürs SEO).
//  2. KI-Fallback über die AI-Provider-Fallback-Kette nur wenn (1) nichts
//     findet — siehe llm.ts / _shared/ai/router.ts.
//
// Alle so angelegten Events teilen sich eine feste "manual"-Quelle (siehe
// ensureManualSource) statt für jede eingegebene URL eine eigene
// sources-Zeile anzulegen — Ad-hoc-Einzelaktion, keine wiederkehrende
// Quelle wie bei den config-getriebenen scrape-Quellen.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseHTML } from "npm:linkedom@0.18.4";
import { isAllowedByRobots, USER_AGENT } from "../_shared/robots.ts";
import { parseSchemaOrg } from "../ingest-source/parsers/schema_org.ts";
import type { RawEvent } from "../ingest-source/types.ts";
import { upsertRawEvent } from "../ingest-source/write.ts";
import { extractEventsWithLlm } from "./llm.ts";

const MANUAL_SOURCE_NAME = "Manuelles Hinzufügen via URL";

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  let body: { url?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid JSON body" }, 400);
  }

  const url = typeof body.url === "string" ? body.url.trim() : null;
  if (!url) {
    return jsonResponse({ error: "url is required" }, 400);
  }
  try {
    new URL(url);
  } catch {
    return jsonResponse({ error: `"${url}" ist keine gültige URL` }, 400);
  }

  const allowed = await isAllowedByRobots(url);
  if (!allowed) {
    return jsonResponse(
      { status: "failed", error: `robots.txt untersagt das Abrufen von ${url}` },
      403,
    );
  }

  let html: string;
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      return jsonResponse(
        { status: "failed", error: `Abruf fehlgeschlagen: HTTP ${res.status} ${res.statusText}` },
        502,
      );
    }
    html = await res.text();
  } catch (err) {
    return jsonResponse(
      { status: "failed", error: `Abruf fehlgeschlagen: ${err instanceof Error ? err.message : String(err)}` },
      502,
    );
  }

  let extractionMethod: "schema_org" | "llm" = "schema_org";
  let events: RawEvent[];
  const extractionErrors: string[] = [];

  const schemaResult = parseSchemaOrg(html);
  if (schemaResult.events.length > 0) {
    events = schemaResult.events;
    extractionErrors.push(...schemaResult.errors);
  } else {
    extractionMethod = "llm";
    const pageText = extractReadableText(html);
    const llmResult = await extractEventsWithLlm(pageText, url, new Date().toISOString().slice(0, 10));
    events = llmResult.events;
    extractionErrors.push(...llmResult.errors);
  }

  if (events.length === 0) {
    return jsonResponse({
      status: "failed",
      error: "Keine Veranstaltung(en) auf dieser Seite erkannt.",
      extraction_method: extractionMethod,
      details: extractionErrors,
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const source = await ensureManualSource(supabase);
  if ("error" in source) {
    return jsonResponse({ status: "failed", error: source.error }, 500);
  }

  let created = 0;
  let updated = 0;
  let unchanged = 0;
  let flagged = 0;
  const results: Array<{ title: string; outcome: string; error?: string }> = [];
  const writeErrors: string[] = [];

  for (const raw of events) {
    const result = await upsertRawEvent(supabase, source, raw);
    results.push({
      title: raw.title,
      outcome: result.outcome,
      error: result.outcome === "error" ? result.error : undefined,
    });
    switch (result.outcome) {
      case "created":
        created++;
        break;
      case "updated":
        updated++;
        break;
      case "unchanged":
        unchanged++;
        break;
      case "flagged":
        flagged++;
        break;
      case "error":
        writeErrors.push(`"${raw.title}": ${result.error}`);
        break;
    }
  }

  const succeeded = created + updated + unchanged + flagged;

  return jsonResponse({
    status: succeeded > 0 ? "success" : "failed",
    extraction_method: extractionMethod,
    events_found: events.length,
    events_created: created,
    events_updated: updated,
    events_unchanged: unchanged,
    events_flagged_for_review: flagged,
    error_count: writeErrors.length,
    results,
    errors: [...extractionErrors, ...writeErrors],
  });
});

/** Entfernt Skripte/Styles/Nav/Footer, bevor der restliche sichtbare Text
 * für den KI-Fallback extrahiert wird — reduziert Rauschen und Tokens. */
function extractReadableText(html: string): string {
  try {
    const { document } = parseHTML(html);
    for (const tag of ["script", "style", "nav", "footer", "noscript"]) {
      // deno-lint-ignore no-explicit-any
      document.querySelectorAll(tag).forEach((el: any) => el.remove());
    }
    return (document.body?.textContent ?? "").replace(/\s+/g, " ").trim();
  } catch {
    return "";
  }
}

/** Alle per-URL manuell hinzugefügten Events teilen sich diese eine Quelle
 * (venue_id: null — jede URL kann eine andere Venue haben, Auflösung läuft
 * pro Event über den Fuzzy-Match in matching.ts). Legt sie beim ersten
 * Aufruf an, falls die Migration noch nicht gelaufen ist. */
async function ensureManualSource(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<{ id: string; venue_id: string | null } | { error: string }> {
  const { data: existing, error: selectError } = await supabase
    .from("sources")
    .select("id, venue_id")
    .eq("type", "manual")
    .eq("name", MANUAL_SOURCE_NAME)
    .maybeSingle();

  if (selectError) {
    return { error: `Konnte manuelle Quelle nicht laden: ${selectError.message}` };
  }
  if (existing) return existing;

  const { data: created, error: insertError } = await supabase
    .from("sources")
    .insert({
      name: MANUAL_SOURCE_NAME,
      type: "manual",
      url: "manual:url-import",
      venue_id: null,
      crawl_frequency_minutes: 0,
      legal_basis:
        "Admin fügt einzelne URLs manuell hinzu, keine automatisierte, wiederkehrende Quelle — " +
        "robots.txt wird trotzdem pro eingefügter URL geprüft.",
      status: "active",
    })
    .select("id, venue_id")
    .single();

  if (insertError || !created) {
    return { error: `Konnte manuelle Quelle nicht anlegen: ${insertError?.message ?? "unbekannt"}` };
  }
  return created;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
