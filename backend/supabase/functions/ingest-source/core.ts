// Side-effect-free core of the ingest-source Edge Function — deliberately
// split out of index.ts so run-all-sources (and anything else) can import
// runIngestion()/SUPPORTED_TYPES WITHOUT also importing index.ts's top-level
// `Deno.serve(...)` call.
//
// That collision was a real, previously undiscovered bug: ES module imports
// fully evaluate the imported module's top-level code first, so importing
// straight from index.ts silently ran ITS Deno.serve() handler as a side
// effect. In the Supabase Edge Runtime, whichever Deno.serve() call succeeds
// first apparently wins for the whole isolate — so every request to
// run-all-sources (including the daily pg_cron job) was actually being
// answered by ingest-source's handler, which immediately rejects with
// "source_id is required" since run-all-sources doesn't send one. The daily
// automatic import has therefore been silently failing at the HTTP layer
// (visible as zero pg_net-triggered rows in ingestion_runs, since a 400
// response isn't surfaced by the fire-and-forget net.http_post call in
// run_all_active_sources()) — not actually running, despite the cron firing
// on schedule. This file's only purpose is to make that impossible again:
// no top-level Deno.serve() anywhere in this module.

import { parseBayernCloud } from "./parsers/bayerncloud.ts";
import { fetchBrsoConcertsJson, parseBrso } from "./parsers/brso.ts";
import { isAllowedByRobots, USER_AGENT } from "../_shared/robots.ts";
import { fetchWithRetry } from "../_shared/http/fetchWithRetry.ts";
import { parseIcal } from "./parsers/ical.ts";
import { parseRss } from "./parsers/rss.ts";
import { extractNextPageUrl, parseScrape } from "./parsers/scrape.ts";
import { parseSchemaOrg } from "./parsers/schema_org.ts";
import type { ParseResult } from "./types.ts";
import { upsertRawEvent } from "./write.ts";

// Exported so run-all-sources can exclude unsupported types (e.g. "manual")
// up front, instead of attempting + failing every single cron run.
// "brso" ist wie "api" ein Sonderfall mit eigenem Fetch-Ablauf statt des
// generischen Einzel-GET (siehe parsers/brso.ts's Datei-Kommentar für den
// Grund: der Konzertinhalt lädt clientseitig per AJAX, kein CSS-Scraping
// möglich).
export const SUPPORTED_TYPES = new Set(["schema_org", "ical", "rss", "scrape", "api", "brso"]);

/** Führt einen kompletten Ingestion-Lauf für eine Quelle aus — der eigentliche
 * Kern, den ingest-source/index.ts's Deno.serve-Handler direkt aufruft.
 * Als eigene, exportierte Funktion extrahiert, damit run-all-sources/index.ts
 * (der nebenläufige Orchestrator) sie in-process aufrufen kann, ohne
 * einen HTTP-Roundtrip auf sich selbst zu machen. */
export async function runIngestion(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  sourceId: string,
): Promise<{ httpStatus: number; body: Record<string, unknown> }> {
  function result(body: Record<string, unknown>, httpStatus = 200) {
    return { httpStatus, body };
  }

  const { data: source, error: sourceError } = await supabase
    .from("sources")
    .select(
      "id, name, type, url, venue_id, organizer_id, person_id, ensemble_id, config, consecutive_failures, crawl_frequency_minutes, confidence_thresholds",
    )
    .eq("id", sourceId)
    .maybeSingle();
  // deno-lint-ignore no-explicit-any
  const config = (source?.config ?? {}) as Record<string, any>;

  if (sourceError) {
    return result({ error: `failed to load source: ${sourceError.message}` }, 500);
  }
  if (!source) {
    return result({ error: `source ${sourceId} not found` }, 404);
  }

  const { data: run, error: runError } = await supabase
    .from("ingestion_runs")
    .insert({ source_id: source.id, started_at: new Date().toISOString(), status: "running" })
    .select("id")
    .single();

  if (runError || !run) {
    return result(
      { error: `failed to create ingestion_runs row: ${runError?.message ?? "unknown"}` },
      500,
    );
  }

  if (!SUPPORTED_TYPES.has(source.type)) {
    const message =
      `ingestion type '${source.type}' is not supported by the automatic worker (manual/api require separate handling)`;
    await finishRun(supabase, run.id, "failed", { events_found: 0 }, [message]);
    await touchSource(supabase, source.id, false);
    return result({ status: "failed", error: message }, 422);
  }

  if (source.type === "scrape" || source.type === "brso") {
    const allowed = await isAllowedByRobots(source.url);
    if (!allowed) {
      const message = `robots.txt disallows fetching ${source.url} — refusing to scrape`;
      await finishRun(supabase, run.id, "failed", { events_found: 0 }, [message]);
      await touchSource(supabase, source.id, false);
      return result({ status: "failed", error: message }, 403);
    }
  }

  // 'api'-Quellen (bisher nur BayernCloud Tourismus) sind Bearer-Token-
  // authentifiziert — anders als jede scrape/schema_org/rss/ical-Quelle,
  // die alle öffentlich/anonym abrufbar sind. Der Token selbst steht nie in
  // sources.config (das wäre ein Secret in der DB) — config trägt nur den
  // NAMEN des Supabase-Secrets, aus dem der Token zur Laufzeit gelesen wird.
  const headers: Record<string, string> = { "User-Agent": USER_AGENT };
  if (source.type === "api" && typeof config.authHeaderEnvVar === "string") {
    const token = Deno.env.get(config.authHeaderEnvVar);
    if (!token) {
      const message = `source.config.authHeaderEnvVar is "${config.authHeaderEnvVar}", but no such Supabase secret is set`;
      await finishRun(supabase, run.id, "failed", { events_found: 0 }, [message]);
      await touchSource(supabase, source.id, false);
      return result({ status: "failed", error: message }, 500);
    }
    // HTTP header values must be ByteStrings (code points 0-255) — fetch()
    // throws an opaque "not a valid ByteString" TypeError otherwise, giving
    // no clue which secret or character is at fault. A trimmed, out-of-range
    // character almost always means a copy-paste artifact (smart quote,
    // em-dash, BOM) got included when the secret was set — pinpoint it here
    // instead of letting the generic fetch-threw catch block below swallow
    // the detail.
    const trimmedToken = token.trim();
    const invalidCharIndex = [...trimmedToken].findIndex((ch) => ch.codePointAt(0)! > 255);
    if (invalidCharIndex !== -1) {
      const ch = [...trimmedToken][invalidCharIndex];
      const codePoint = ch.codePointAt(0)!.toString(16).toUpperCase().padStart(4, "0");
      const message =
        `Supabase secret "${config.authHeaderEnvVar}" contains an invalid character (U+${codePoint} ` +
        `at position ${invalidCharIndex}) that can't be used in an HTTP header — likely a copy-paste ` +
        `artifact (smart quote/em-dash/BOM). Re-set the secret with a plain-ASCII value, e.g.: ` +
        `supabase secrets set ${config.authHeaderEnvVar}=<token> --project-ref <ref>`;
      await finishRun(supabase, run.id, "failed", { events_found: 0 }, [message]);
      await touchSource(supabase, source.id, false);
      return result({ status: "failed", error: message }, 500);
    }
    headers["Authorization"] = `Bearer ${trimmedToken}`;
  }

  // HTTP-Caching: viele Quellen unterstützen ETag/Last-Modified, manche
  // (v.a. einzelne Künstler-/Ensemble-Seiten) gar keine Cache-Header — dafür
  // zusätzlich ein Body-Hash-Fallback (siehe unten). httpCache lebt in
  // sources.config statt einer eigenen Spalte, konsistent mit dem
  // bestehenden config.authHeaderEnvVar-Muster.
  const httpCache = (config.httpCache ?? {}) as {
    etag?: string;
    lastModified?: string;
    lastBodyHash?: string;
  };
  if (httpCache.etag) headers["If-None-Match"] = httpCache.etag;
  if (httpCache.lastModified) headers["If-Modified-Since"] = httpCache.lastModified;

  let responseBody: string;
  let responseEtag: string | null = null;
  let responseLastModified: string | null = null;
  try {
    // "brso" braucht einen zweistufigen Fetch (Kalenderseite -> Nonce ->
    // JSON-POST, siehe parsers/brso.ts) statt des generischen Einzel-GET —
    // liefert kein ETag/Last-Modified, der bodyHash-Fallback weiter unten
    // greift trotzdem unverändert.
    if (source.type === "brso") {
      responseBody = await fetchBrsoConcertsJson(source.url);
    } else {
      // Einzige zentrale Netzwerkstelle im Ingestion-Pfad ohne Timeout/
      // Retry (siehe _shared/http/fetchWithRetry.ts) — ein hängender
      // Request band sonst einen Worker-Slot in run-all-sources' begrenztem
      // Pool für die volle Laufzeit. Timeout pro Quelle konfigurierbar
      // (gleiches Muster wie config.crawlDelayMs), Default 20s.
      const timeoutMs = typeof source.config?.fetchTimeoutMs === "number" ? source.config.fetchTimeoutMs : undefined;
      const res = await fetchWithRetry(source.url, { headers }, { timeoutMs });

      if (res.status === 304) {
        // Server bestätigt: seit dem letzten Lauf unverändert — Parsen/
        // Schreiben komplett überspringen. flagMissingEvents() wird bewusst
        // NICHT aufgerufen (kein seenEventIds für diesen Lauf vorhanden), das
        // würde sonst fälschlich alles als "verschwunden" markieren.
        await finishRun(supabase, run.id, "skipped_unchanged", { events_found: 0 }, []);
        await touchSource(supabase, source.id, true);
        await adjustCrawlFrequency(supabase, source.id, source.crawl_frequency_minutes, false);
        return result({ status: "skipped_unchanged", events_found: 0 });
      }

      if (!res.ok) {
        const message = `fetch failed: HTTP ${res.status} ${res.statusText}`;
        await finishRun(supabase, run.id, "failed", { events_found: 0 }, [message]);
        await touchSource(supabase, source.id, false);
        return result({ status: "failed", error: message }, 502);
      }
      responseEtag = res.headers.get("etag");
      responseLastModified = res.headers.get("last-modified");
      responseBody = await res.text();
    }
  } catch (err) {
    const message = `fetch threw: ${err instanceof Error ? err.message : String(err)}`;
    await finishRun(supabase, run.id, "failed", { events_found: 0 }, [message]);
    await touchSource(supabase, source.id, false);
    return result({ status: "failed", error: message }, 502);
  }

  // Fallback für Quellen ohne (verlässliche) ETag/Last-Modified-Header
  // (die meisten Künstler-/Ensemble-Seiten): Hash über den Response-Body,
  // Vergleich gegen den zuletzt gespeicherten Wert. Auch hier: bei
  // Übereinstimmung komplett überspringen statt nur den (in Phase 1 noch
  // gar nicht vorhandenen) teuren LLM-Schritt — aus denselben Gründen wie
  // beim 304-Fall oben.
  const bodyHash = await sha256Hex(responseBody);
  if (!responseEtag && !responseLastModified && httpCache.lastBodyHash === bodyHash) {
    await finishRun(supabase, run.id, "skipped_unchanged", { events_found: 0 }, []);
    await touchSource(supabase, source.id, true);
    await adjustCrawlFrequency(supabase, source.id, source.crawl_frequency_minutes, false);
    return result({ status: "skipped_unchanged", events_found: 0 });
  }

  await adjustCrawlFrequency(supabase, source.id, source.crawl_frequency_minutes, true);

  await supabase
    .from("sources")
    .update({
      config: {
        ...config,
        httpCache: {
          etag: responseEtag ?? undefined,
          lastModified: responseLastModified ?? undefined,
          lastBodyHash: bodyHash,
        },
      },
    })
    .eq("id", source.id);

  let parsed: ParseResult;
  try {
    switch (source.type) {
      case "schema_org":
        parsed = parseSchemaOrg(responseBody);
        break;
      case "ical":
        parsed = parseIcal(responseBody);
        break;
      case "rss":
        parsed = await parseRss(responseBody);
        break;
      case "scrape": {
        parsed = parseScrape(responseBody, source.config);
        // Paginierung: manche Quellen (residenz-muenchen.de) haben keine
        // vorhersagbare Seitennummer-URL-Systematik — der "nächste Seite"-
        // Link muss also pro Seite verfolgt werden statt eine Ziel-URL zu
        // berechnen. Bricht ab, sobald extractNextPageUrl() null liefert
        // (kein nextPageSelector konfiguriert ODER letzte Seite erreicht)
        // oder MAX_PAGES erreicht ist — kein unbegrenztes Nachladen.
        const MAX_PAGES = 5;
        let pageUrl = source.url;
        let pageHtml = responseBody;
        for (let page = 1; page < MAX_PAGES; page++) {
          const nextUrl = extractNextPageUrl(pageHtml, source.config, pageUrl);
          if (!nextUrl) break;
          // robots.txt einiger Quellen (z.B. erzbistum-muenchen.de) nennt
          // einen Crawl-Delay — der gilt pro Request, also auch zwischen den
          // Folgeseiten innerhalb dieses einen Laufs.
          const delayMs = source.config?.crawlDelayMs;
          if (typeof delayMs === "number" && delayMs > 0) {
            await new Promise((resolve) => setTimeout(resolve, delayMs));
          }
          let nextRes: Response;
          try {
            nextRes = await fetch(nextUrl, { headers: { "User-Agent": USER_AGENT } });
          } catch (err) {
            parsed.errors.push(
              `pagination: fetch of page ${page + 1} threw: ${err instanceof Error ? err.message : String(err)}`,
            );
            break;
          }
          if (!nextRes.ok) {
            parsed.errors.push(`pagination: fetch of page ${page + 1} failed: HTTP ${nextRes.status}`);
            break;
          }
          pageHtml = await nextRes.text();
          pageUrl = nextUrl;
          const nextParsed = parseScrape(pageHtml, source.config);
          parsed = { events: [...parsed.events, ...nextParsed.events], errors: [...parsed.errors, ...nextParsed.errors] };
        }
        break;
      }
      case "api":
        parsed = parseBayernCloud(responseBody);
        break;
      case "brso":
        parsed = parseBrso(responseBody);
        break;
      default:
        // Unreachable given the SUPPORTED_TYPES guard above, but keeps the
        // switch exhaustive without a non-null assertion.
        parsed = { events: [], errors: [`unhandled source type '${source.type}'`] };
    }
  } catch (err) {
    const message = `parser threw: ${err instanceof Error ? err.message : String(err)}`;
    await finishRun(supabase, run.id, "failed", { events_found: 0 }, [message]);
    await touchSource(supabase, source.id, false);
    return result({ status: "failed", error: message }, 500);
  }

  let created = 0;
  let updated = 0;
  let unchanged = 0;
  let flagged = 0;
  const rawWriteErrors: string[] = [...parsed.errors];
  const seenEventIds: string[] = [];

  for (const raw of parsed.events) {
    const result = await upsertRawEvent(supabase, source, raw);
    switch (result.outcome) {
      case "created":
        created++;
        seenEventIds.push(result.eventId);
        break;
      case "updated":
        updated++;
        seenEventIds.push(result.eventId);
        break;
      case "unchanged":
        unchanged++;
        seenEventIds.push(result.eventId);
        break;
      case "flagged":
        flagged++;
        seenEventIds.push(result.eventId);
        break;
      case "error":
        rawWriteErrors.push(`"${raw.title}": ${result.error}`);
        break;
    }
  }

  const writeErrors = summarizeErrors(rawWriteErrors);

  const attempted = parsed.events.length;
  const succeeded = created + updated + unchanged + flagged;
  // "Diagnostic: ..."-Einträge (siehe parsers/bayerncloud.ts) sind bewusst
  // rein informativ, keine echten Fehler — z.B. "diese Bayern-weite Quelle
  // lieferte in diesem Lauf zufällig keine Münchner Events" ist ein
  // normaler, erwartbarer Zustand, kein Zeichen für einen kaputten
  // Connector. Nutzerfeedback: "BayernCloud Tourismus Events. schlägt
  // immer fehl" — live geprüft: der Fehlerzähler stieg NUR wegen dieser
  // rein diagnostischen Meldung, die Filterlogik selbst funktionierte
  // korrekt (Stichprobe bestätigte echte Nicht-München-Venues wie
  // "Fischen i. Allgäu"). Bleiben trotzdem im Bericht sichtbar (writeErrors
  // unten nutzt weiterhin parsed.errors unverändert), zählen nur nicht
  // gegen den Erfolgsstatus/consecutive_failures.
  const realErrorCount = parsed.errors.filter((e) => !e.startsWith("Diagnostic (info):")).length;
  const status = attempted === 0
    ? (realErrorCount > 0 ? "failed" : "success")
    : succeeded === 0
    ? "failed"
    : succeeded < attempted
    ? "partial"
    : "success";

  // Absage-Erkennung: nur für Quelltypen, die pro Lauf eine VOLLSTÄNDIGE
  // Liste aller aktuellen Termine liefern (ical/rss/schema_org). "scrape"
  // ist bewusst ausgeschlossen — MAX_PAGES=5 (oben) deckt nicht garantiert
  // jede Seite ab, ein zu früh abgebrochener Lauf würde sonst noch
  // existierende, nur nicht (erneut) gescrapte Events fälschlich als
  // "verschwunden" markieren. "api" ebenso ausgeschlossen (Paginierung/
  // Vollständigkeit nicht einheitlich garantiert über alle möglichen
  // API-Quellen hinweg). "manual" betrifft ohnehin nur Einzel-URL-Importe,
  // nie eine Liste. Zusätzlich: nur wenn dieser Lauf komplett fehlerfrei
  // war (keine Parse-Fehler, jedes RawEvent erfolgreich geschrieben) —
  // sonst könnte ein einzelner fehlgeschlagener Write ein weiterhin
  // existierendes Event fälschlich als "verschwunden" erscheinen lassen.
  const FULL_LISTING_TYPES = new Set(["ical", "rss", "schema_org"]);
  if (
    FULL_LISTING_TYPES.has(source.type) &&
    parsed.errors.length === 0 &&
    succeeded === attempted
  ) {
    await flagMissingEvents(supabase, source.id, seenEventIds);
  }

  await finishRun(
    supabase,
    run.id,
    status,
    {
      events_found: attempted,
      events_created: created,
      events_updated: updated,
      events_flagged_for_review: flagged,
    },
    writeErrors,
  );
  await touchSource(supabase, source.id, status !== "failed");

  return result({
    status,
    events_found: attempted,
    events_created: created,
    events_updated: updated,
    events_unchanged: unchanged,
    events_flagged_for_review: flagged,
    error_count: writeErrors.length,
  });
}

// Nutzerfeedback: Quellen ohne feste venue_id, deren Parser auch keinen
// Venue-Namen pro Event liefert (z.B. eine reine Terminliste eines
// Vereins/Konzertreihe, ohne wiederholte Ortsangabe), scheiterten mit
// EINER identischen Fehlermeldung pro Event — bei einer vollen Terminliste
// schnell Dutzende Zeilen desselben Fehlers, der in ingestion_runs.errors
// unübersichtlich wurde und die eigentlich nötige Handlung (Quelle
// bearbeiten, feste Venue setzen) verschleierte. Fasst wiederkehrende
// Venue-Zuordnungsfehler zu einer Zeile mit Beispielen + Handlungsanweisung
// zusammen, statt sie 1:1 durchzureichen.
function summarizeErrors(errors: string[]): string[] {
  const noVenueNameReason = "no venue_id on source and RawEvent has no venueName to match against";
  const titles: string[] = [];
  const passthrough: string[] = [];

  for (const e of errors) {
    if (e.endsWith(`": ${noVenueNameReason}`)) {
      titles.push(e.slice(1, e.indexOf(`": ${noVenueNameReason}`) + 1));
    } else {
      passthrough.push(e);
    }
  }

  if (titles.length === 0) return passthrough;

  const examples = titles.slice(0, 3).join(", ");
  const more = titles.length > 3 ? ` (+${titles.length - 3} weitere)` : "";
  passthrough.push(
    `${titles.length}× übersprungen, da diese Quelle keine feste Venue hat und die Events auch keinen Venue-Namen liefern: ${examples}${more}. ` +
      `Lösung: in den Quellen-Einstellungen eine feste Venue setzen (Feld "Venue"), dann erneut ausführen.`,
  );
  return passthrough;
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function finishRun(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  runId: string,
  status: "success" | "partial" | "failed" | "skipped_unchanged",
  counts: {
    events_found: number;
    events_created?: number;
    events_updated?: number;
    events_flagged_for_review?: number;
  },
  errors: string[],
) {
  const { error } = await supabase
    .from("ingestion_runs")
    .update({
      finished_at: new Date().toISOString(),
      status,
      events_found: counts.events_found,
      events_created: counts.events_created ?? 0,
      events_updated: counts.events_updated ?? 0,
      events_flagged_for_review: counts.events_flagged_for_review ?? 0,
      errors,
    })
    .eq("id", runId);

  if (error) {
    // Nothing more we can do — the run's own outcome already happened, this
    // would only affect the admin UI's visibility into it.
    console.error(`failed to finalize ingestion_runs ${runId}: ${error.message}`);
  }
}

/** Findet events dieser Quelle, die im aktuellen Lauf nicht (mehr)
 * vorkamen, und legt dafür einen cancellation_candidates-Eintrag zur
 * redaktionellen Prüfung an (20260815000003) — setzt NIE direkt
 * status='cancelled', das entscheidet die Redaktion im Admin-Dashboard.
 * Der partial unique index auf (event_id) where status='pending' sorgt
 * dafür, dass ein Event nicht bei jedem täglichen Lauf erneut geflaggt
 * wird, solange der vorherige Kandidat noch nicht reviewt wurde. */
async function flagMissingEvents(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  sourceId: string,
  seenEventIds: string[],
) {
  let query = supabase
    .from("events")
    .select("id")
    .eq("source_id", sourceId)
    .eq("status", "scheduled")
    // Explizite Obergrenze statt PostgRESTs stillem 1000-Zeilen-Limit — bei
    // Überschreiten würde sonst nur ein Teil der tatsächlich fehlenden
    // Events erkannt, ohne dass das irgendwo sichtbar wird.
    .limit(2000);

  // .not("id", "in", "()") ist ungültige Syntax bei einer leeren Liste —
  // wenn nichts gesehen wurde (z.B. leerer Feed), einfach alle scheduled
  // Events dieser Quelle als Kandidaten behandeln, ohne den in-Filter.
  if (seenEventIds.length > 0) {
    query = query.not("id", "in", `(${seenEventIds.join(",")})`);
  }

  const { data: missing, error } = await query;
  if (error) {
    console.error(`flagMissingEvents: lookup failed for source ${sourceId}: ${error.message}`);
    return;
  }
  if (!missing || missing.length === 0) return;

  // Supabase-js' .upsert({onConflict}) targets a plain unique constraint on
  // the given column(s) — it can't address our PARTIAL unique index
  // (event_id where status='pending'), so ON CONFLICT would either not
  // match it at all or (worse) collide with an old, already-reviewed
  // (non-pending) row for the same event and silently no-op there instead.
  // Check-then-insert avoids that ambiguity entirely; the partial index
  // still acts as a defensive DB-level backstop against a genuine race.
  const { data: existingPending, error: existingError } = await supabase
    .from("cancellation_candidates")
    .select("event_id")
    .eq("status", "pending")
    .in("event_id", missing.map((e: { id: string }) => e.id));
  if (existingError) {
    console.error(
      `flagMissingEvents: existing-candidate lookup failed for source ${sourceId}: ${existingError.message}`,
    );
    return;
  }

  const alreadyFlagged = new Set(
    (existingPending ?? []).map((r: { event_id: string }) => r.event_id),
  );
  const toInsert = missing
    .filter((e: { id: string }) => !alreadyFlagged.has(e.id))
    .map((e: { id: string }) => ({
      event_id: e.id,
      source_id: sourceId,
      reason: "missing_from_source",
      status: "pending",
    }));
  if (toInsert.length === 0) return;

  const { error: insertError } = await supabase.from("cancellation_candidates").insert(toInsert);
  if (insertError) {
    console.error(`flagMissingEvents: insert failed for source ${sourceId}: ${insertError.message}`);
  }
}

// deno-lint-ignore no-explicit-any
async function touchSource(supabase: any, sourceId: string, succeeded: boolean) {
  const nowIso = new Date().toISOString();

  if (succeeded) {
    await supabase
      .from("sources")
      .update({ last_run_at: nowIso, last_success_at: nowIso, consecutive_failures: 0 })
      .eq("id", sourceId);
    return;
  }

  const { data: current } = await supabase
    .from("sources")
    .select("consecutive_failures")
    .eq("id", sourceId)
    .maybeSingle();

  await supabase
    .from("sources")
    .update({
      last_run_at: nowIso,
      consecutive_failures: (current?.consecutive_failures ?? 0) + 1,
    })
    .eq("id", sourceId);
}

// Architektur-Dokument Abschnitt 5.1: adaptives Crawl-Intervall statt eines
// für alle Quellen gleichen fixen Werts. Bewusst nur als Kalibrierung von
// crawl_frequency_minutes umgesetzt (kein Scheduler-Verhalten geändert) —
// run-all-sources ruft aktuell noch alle status='active'-Quellen bei jedem
// (täglichen) Cron-Lauf auf, unabhängig von diesem Wert. Das Feld wird
// trotzdem schon jetzt live kalibriert, damit eine künftige
// Scheduler-Erweiterung (die crawl_frequency_minutes tatsächlich zum
// Filtern nutzt) auf bereits eingeschwungenen Werten aufsetzt statt bei
// 1440 (Default) für jede Quelle neu zu starten.
const MIN_CRAWL_FREQUENCY_MINUTES = 60; // 1 Stunde
const MAX_CRAWL_FREQUENCY_MINUTES = 10080; // 7 Tage

async function adjustCrawlFrequency(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  sourceId: string,
  currentMinutes: number | null | undefined,
  changed: boolean,
) {
  const current = currentMinutes ?? 1440;
  const next = changed
    ? Math.max(MIN_CRAWL_FREQUENCY_MINUTES, Math.round(current / 2))
    : Math.min(MAX_CRAWL_FREQUENCY_MINUTES, Math.round(current * 2));
  if (next === current) return;
  await supabase.from("sources").update({ crawl_frequency_minutes: next }).eq("id", sourceId);
}
