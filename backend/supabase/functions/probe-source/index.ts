// Onboarding-Assistent für neue Quellen (Architektur-Dokument Abschnitt 5):
// Admin gibt eine URL ein, diese Function probiert automatisch Tier 1
// (schema.org) -> Tier 2 (RSS/iCal, falls der Content-Type passt) -> Tier 3
// (KI-Extraktion aus dem sichtbaren Seitentext) durch und gibt eine Vorschau
// der erkannten Events + die empfohlene sources.type-Einstellung zurück.
// Legt NICHTS in der DB an — reines Read-only-Probing, das Anlegen bleibt
// der bestehenden Quellen-Verwaltung (sources/new) überlassen, jetzt mit
// vorausgefülltem Typ/URL.
//
// Bewusst "vollständig codefrei" NICHT vollständig erreicht (siehe
// Architektur-Dokument Abschnitt 5): das Ergebnis ist eine Empfehlung zur
// Bestätigung durch den Admin, kein automatisches Anlegen — eine
// KI-Extraktion kann falsch liegen, und eine ungeprüft angelegte Quelle
// ist ein Datenqualitätsrisiko.

import { parseHTML } from "npm:linkedom@0.18.4";
import { isAllowedByRobots, USER_AGENT } from "../_shared/robots.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { isPublicImageUrl } from "../_shared/imageValidation.ts";
import { parseSchemaOrg } from "../ingest-source/parsers/schema_org.ts";
import { parseIcal } from "../ingest-source/parsers/ical.ts";
import { parseRss } from "../ingest-source/parsers/rss.ts";
import type { ParseResult, RawEvent } from "../ingest-source/types.ts";
import { extractEventsWithLlm } from "../extract-event-from-url/llm.ts";

const PREVIEW_LIMIT = 5;

Deno.serve(async (req) => {
  // Vorher ohne jede Prüfung: jeder mit dem öffentlichen Anon-Key konnte
  // beliebige URLs abrufen lassen (SSRF) und LLM-Kosten verursachen.
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  let body: { url?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid JSON body" }, 400);
  }

  const url = typeof body.url === "string" ? body.url.trim() : null;
  if (!url) return jsonResponse({ error: "url is required" }, 400);
  try {
    new URL(url);
  } catch {
    return jsonResponse({ error: `"${url}" ist keine gültige URL` }, 400);
  }
  // Prüft http(s) und blockt localhost/private/Link-Local-Adressen (SSRF).
  if (!isPublicImageUrl(url)) {
    return jsonResponse({ status: "blocked", error: "Nur öffentliche http(s)-URLs sind erlaubt." }, 400);
  }

  const allowed = await isAllowedByRobots(url);
  if (!allowed) {
    return jsonResponse({ status: "blocked", error: `robots.txt untersagt das Abrufen von ${url}` }, 403);
  }

  let contentType = "";
  let body_: string;
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      return jsonResponse({ status: "failed", error: `Abruf fehlgeschlagen: HTTP ${res.status} ${res.statusText}` }, 502);
    }
    contentType = res.headers.get("content-type") ?? "";
    body_ = await res.text();
  } catch (err) {
    return jsonResponse(
      { status: "failed", error: `Abruf fehlgeschlagen: ${err instanceof Error ? err.message : String(err)}` },
      502,
    );
  }

  // Tier 1: schema.org (funktioniert auf HTML-Antworten unabhängig vom
  // Content-Type-Header, da es nach <script type="application/ld+json">
  // sucht bzw. rohes JSON versucht).
  const schemaResult = parseSchemaOrg(body_);
  if (schemaResult.events.length > 0) {
    return jsonResponse(buildPreview("schema_org", schemaResult, url));
  }

  // Tier 2a: iCal — erkennbar am Dateiinhalt (BEGIN:VCALENDAR), nicht
  // verlässlich am Content-Type (viele Server liefern text/plain o.ä.).
  if (body_.trim().startsWith("BEGIN:VCALENDAR")) {
    const icalResult = parseIcal(body_);
    if (icalResult.events.length > 0) {
      return jsonResponse(buildPreview("ical", icalResult, url));
    }
  }

  // Tier 2b: RSS/Atom — erkennbar an <rss/<feed>-Root-Element oder
  // xml-Content-Type.
  const looksLikeFeed = /content-type:.*xml/i.test(contentType) || /<rss[\s>]|<feed[\s>]/i.test(body_.slice(0, 2000));
  if (looksLikeFeed) {
    try {
      const rssResult = await parseRss(body_);
      if (rssResult.events.length > 0) {
        return jsonResponse(buildPreview("rss", rssResult, url));
      }
    } catch {
      // Kein valider RSS/Atom-Feed trotz XML-Anschein — weiter zu Tier 3.
    }
  }

  // Tier 3: KI-Extraktion aus dem sichtbaren Seitentext — teuerste Stufe,
  // deshalb zuletzt. WICHTIG: liefert NUR eine Vorschau, KEINE Empfehlung
  // für sources.type="scrape" — dieser Typ braucht in der wiederkehrenden
  // Ingestion-Pipeline (ingest-source/parsers/scrape.ts) manuell
  // konfigurierte CSS-Selektoren (config.itemSelector etc.), die hier nicht
  // generiert werden. Eine allein aufgrund dieses Treffers als type=scrape
  // angelegte Quelle würde beim nächsten automatischen Lauf 0 Events
  // liefern, ohne dass das auffällt — deshalb recommendedType hier explizit
  // null, mit Klartext-Hinweis statt einer falschen Empfehlung.
  const pageText = extractReadableText(body_);
  const llmResult = await extractEventsWithLlm(pageText, url, new Date().toISOString().slice(0, 10));
  if (llmResult.events.length > 0) {
    return jsonResponse({
      status: "ok_manual_only",
      recommendedType: null,
      eventsFound: llmResult.events.length,
      preview: llmResult.events.slice(0, PREVIEW_LIMIT).map(previewFields),
      errors: llmResult.errors,
      url,
      message:
        "Keine strukturierten Daten (schema.org/RSS/iCal) gefunden — per KI wurden trotzdem Veranstaltungen " +
        "im Seitentext erkannt (siehe Vorschau). Für eine WIEDERKEHRENDE automatische Quelle braucht " +
        "type=\"scrape\" manuell konfigurierte CSS-Selektoren (siehe Quellen-Formular, Feld „Konfiguration\") — " +
        "ohne die liefert ein automatischer Lauf 0 Events. Bis dahin: Events einzeln über " +
        "„URL manuell hinzufügen\" importieren.",
    });
  }

  return jsonResponse({
    status: "no_events_found",
    recommendedType: null,
    message: "Auf dieser Seite konnten weder strukturierte Daten noch per KI Veranstaltungen erkannt werden.",
    errors: [...schemaResult.errors, ...llmResult.errors],
  });
});

function buildPreview(
  recommendedType: "schema_org" | "ical" | "rss",
  result: ParseResult,
  url: string,
) {
  return {
    status: "ok",
    recommendedType,
    eventsFound: result.events.length,
    preview: result.events.slice(0, PREVIEW_LIMIT).map(previewFields),
    errors: result.errors,
    url,
  };
}

function previewFields(e: RawEvent) {
  return {
    title: e.title,
    startDateTime: e.startDateTime,
    venueName: e.venueName,
    isFree: e.isFree,
  };
}

/** Entfernt Skripte/Styles/Nav/Footer, bevor der restliche sichtbare Text
 * für den KI-Fallback extrahiert wird — identisch zu extract-event-from-url/
 * index.ts, hier dupliziert statt importiert (kein exportiertes Utility dort). */
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

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
