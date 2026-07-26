// BRSO-Konzertkalender-Connector (brso.de) — ANDERS als jede andere
// scrape-Quelle in diesem Repo: der Konzert-Volltext lädt NICHT als
// statisches HTML, sondern client-seitig per AJAX/JS über ein Formular
// (class="js-concert-fetch"), das gegen `${baseUrl}/wp-json/v1/filter/
// concerts` POSTet (live entdeckt: das serverseitig gerenderte HTML enthält
// nur ein leeres `<div class="concert-results">`, siehe fetchBrsoConcertsJson()
// unten). Kein CSS-Scraping möglich — braucht stattdessen einen
// zweistufigen Fetch: erst die Kalenderseite laden und daraus den
// WordPress-REST-Nonce extrahieren (eingebettet in ein inline `<script>`
// als `var settings = {...,"nonce":"...",...}`), dann damit den eigentlichen
// JSON-Endpunkt POSTen.
//
// Live verifiziert am 2026-07-26: Response-Form ist
// `{success, message, data: {concerts: [...], message}}`. `concerts`
// enthält AUCH vergangene Konzerte (is_archive:true) UND Konzerte
// außerhalb Münchens (die BRSO tourt international, z.B. Amsterdam, Köln,
// Kaohsiung) — beides muss gefiltert werden. `location` ist Freitext im
// Format "Stadt[, Ort][, Halle]" (z.B. "München, Gasteig HP8,
// Isarphilharmonie" oder "München, Prinzregententheater") — der LETZTE
// Abschnitt ist praktisch immer der eigentliche Hallenname und matcht am
// zuverlässigsten gegen find_matching_venue() (RPC-Fuzzy-Suche in
// matching.ts). `ticket_link` ist inkonsistent typisiert: mal ein leerer
// String `""`, mal ein Objekt `{title, url, target}` — beides abgedeckt.
//
// Der Nonce ist ein normaler WordPress-REST-Nonce (laut WP typischerweise
// ~24h gültig, an die Session gebunden, in der er erzeugt wurde) — deshalb
// IMMER frisch von der Kalenderseite holen, nie hartcodieren.

import type { ParseResult, RawEvent } from "../types.ts";
import { USER_AGENT } from "../../_shared/robots.ts";

const FILTER_ENDPOINT = "https://www.brso.de/wp-json/v1/filter/concerts";
const NONCE_PATTERN = /"nonce"\s*:\s*"([a-f0-9]+)"/;

// deno-lint-ignore no-explicit-any
function isRecord(v: unknown): v is Record<string, any> {
  return v != null && typeof v === "object" && !Array.isArray(v);
}

function firstNonEmptyString(...values: unknown[]): string | null {
  for (const v of values) {
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return null;
}

/** Holt die Kalenderseite, extrahiert den eingebetteten REST-Nonce und
 * POSTet damit an den JSON-Filter-Endpunkt. Wirft bei jedem Fehlschlag
 * (Seite nicht abrufbar, kein Nonce gefunden, POST fehlgeschlagen) — der
 * Aufrufer (core.ts) behandelt das wie jeden anderen Fetch-Fehler. */
export async function fetchBrsoConcertsJson(calendarPageUrl: string): Promise<string> {
  const pageRes = await fetch(calendarPageUrl, { headers: { "User-Agent": USER_AGENT } });
  if (!pageRes.ok) {
    throw new Error(`BRSO-Kalenderseite nicht abrufbar: HTTP ${pageRes.status}`);
  }
  const pageHtml = await pageRes.text();
  const nonceMatch = pageHtml.match(NONCE_PATTERN);
  if (!nonceMatch) {
    throw new Error("Kein REST-Nonce in der BRSO-Kalenderseite gefunden (Seitenstruktur hat sich vermutlich geändert)");
  }
  const nonce = nonceMatch[1];

  // Filterparameter aus der Quell-URL übernehmen (pagination/date_from_*
  // sind in sources.url bereits als Query-Parameter konfiguriert), damit
  // eine Änderung der Quellkonfiguration ohne Codeänderung wirkt.
  const sourceParams = new URL(calendarPageUrl).searchParams;
  const body = new URLSearchParams({ nonce });
  for (const key of ["pagination", "date_from_year", "date_from_month", "date_from_day", "presented_by", "director", "location", "abo"]) {
    const value = sourceParams.get(key);
    if (value !== null) body.set(key, value);
  }

  const filterRes = await fetch(FILTER_ENDPOINT, {
    method: "POST",
    headers: {
      "User-Agent": USER_AGENT,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });
  if (!filterRes.ok) {
    throw new Error(`BRSO-Filter-Endpunkt fehlgeschlagen: HTTP ${filterRes.status}`);
  }
  return await filterRes.text();
}

/** Letzter Abschnitt von "Stadt[, Ort][, Halle]" — praktisch immer der
 * eigentliche Hallenname, siehe Datei-Kommentar. */
function extractVenueName(location: string): string | null {
  const parts = location.split(",").map((p) => p.trim()).filter(Boolean);
  return parts.length > 0 ? parts[parts.length - 1] : null;
}

function isMunich(location: string): boolean {
  return /münchen|muenchen|munich/i.test(location);
}

export function parseBrso(content: string): ParseResult {
  const errors: string[] = [];
  const events: RawEvent[] = [];

  let raw: unknown;
  try {
    raw = JSON.parse(content);
  } catch (err) {
    errors.push(`Failed to parse response as JSON: ${err instanceof Error ? err.message : String(err)}`);
    return { events, errors };
  }

  if (!isRecord(raw) || raw.success !== true || !isRecord(raw.data) || !Array.isArray(raw.data.concerts)) {
    errors.push(
      'Response did not match the expected {success:true, data:{concerts:[...]}} shape — check the actual response, the API may have changed.',
    );
    return { events, errors };
  }

  const items: unknown[] = raw.data.concerts;
  let munichCount = 0;
  let upcomingCount = 0;

  items.forEach((item, i) => {
    const label = `item ${i + 1}`;
    if (!isRecord(item)) {
      errors.push(`${label}: not an object, skipped`);
      return;
    }

    // is_archive markiert vergangene Konzerte — die Quelle liefert IMMER
    // die volle Historie mit, nicht nur Kommendes.
    if (item.is_archive === true) return;
    upcomingCount++;

    const baseTitle = firstNonEmptyString(item.title);
    if (!baseTitle) {
      errors.push(`${label}: missing title, skipped`);
      return;
    }
    // subtitle ist z.B. "Finale Orgel" bei einem Wettbewerb — nur anhängen,
    // wenn tatsächlich vorhanden und nicht bereits identisch mit dem Titel.
    const subtitle = firstNonEmptyString(item.subtitle);
    const fullTitle = subtitle && subtitle !== baseTitle ? `${baseTitle}: ${subtitle}` : baseTitle;

    const startDateTime = firstNonEmptyString(item.start);
    if (!startDateTime || isNaN(new Date(startDateTime).getTime())) {
      errors.push(`${label} ("${fullTitle}"): missing or invalid "start", skipped`);
      return;
    }

    const location = firstNonEmptyString(item.location);
    // Kein Ort = kann nicht beurteilt werden = raus (dieselbe Regel wie bei
    // BayernCloud, siehe parsers/bayerncloud.ts) — die BRSO tourt
    // international, ohne Ortsangabe wäre eine München-Zuordnung geraten.
    if (!location || !isMunich(location)) return;
    munichCount++;

    const endDateTime = firstNonEmptyString(item.end);

    events.push({
      externalId: null,
      title: fullTitle,
      description: null,
      startDateTime,
      endDateTime: endDateTime && endDateTime !== startDateTime ? endDateTime : null,
      venueName: extractVenueName(location),
      venueAddress: null,
      url: firstNonEmptyString(item.url),
      imageUrl: firstNonEmptyString(item.thumbnail_url),
      priceMin: null,
      priceMax: null,
      isFree: null,
    });
    // ticket_link (inkonsistent typisiert: leerer String ODER
    // {title,url,target}-Objekt) wird bewusst NICHT gemappt — RawEvent hat
    // kein eigenes Ticket-URL-Feld (siehe types.ts), das läuft über die
    // bestehende spätere Anreicherung wie bei jeder anderen Quelle auch.
  });

  if (upcomingCount > 0 && munichCount === 0) {
    errors.push(
      `Diagnostic: none of ${upcomingCount} upcoming raw items matched a Munich location marker — ` +
        "plausibel, wenn dieser Lauf zufällig keine München-Termine enthielt, aber wert, bei Wiederholung zu prüfen.",
    );
  }

  return { events, errors };
}
