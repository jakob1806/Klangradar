// Generischer HTML-Scraping-Connector — für Quellen ohne Schema.org/iCal/RSS.
// sources.config (jsonb) hält die pro-Site-Selektoren, siehe ScrapeConfig
// unten; kein Code-Deploy nötig, um eine neue Scrape-Quelle anzubinden,
// nur eine neue config auf der sources-Zeile (config-getriebene
// "Selektoren" war schon in der ursprünglichen Schema-Doku für sources.config
// vorgesehen, siehe docs/02-database-schema.md §8).
//
// ACHTUNG (bewusste Produktentscheidung, nicht mein Vorschlag): docs/06-mvp-
// plan.md und docs/07-roadmap.md hatten Web-Scraping ausdrücklich auf "nach
// rechtlicher Einzelprüfung je Quelle" verschoben (Roadmap Phase 4). Dieser
// Connector existiert auf expliziten Wunsch, der diese Verschiebung bewusst
// umgeht — nicht meine Einschätzung, dass die rechtliche Prüfung entfallen
// kann. Als Mindest-Sorgfalt: robots.txt wird vor jedem Fetch geprüft (siehe
// index.ts), ein identifizierender User-Agent wird gesendet, keine hohe
// Crawl-Rate (ein Request pro Lauf).

import { parseHTML } from "npm:linkedom@0.18.4";
import type { ParseResult, RawEvent } from "../types.ts";

export interface ScrapeConfig {
  /** CSS-Selektor für ein einzelnes Event-"Karten"-Element. */
  itemSelector: string;
  /** Selektor relativ zum Item für den Titel. Falls "titleAttribute" fehlt,
   * wird standardmäßig nur der ERSTE direkte Text-Kindknoten genutzt (nicht
   * der ganze textContent) — Karten haben oft einen verschachtelten
   * Untertitel-<span>, der sonst mit reingezogen würde. Sites, deren Titel
   * selbst mehrzeilig ist (z.B. per <br> getrennte Komponisten-Liste ohne
   * eigenes Untertitel-Element) setzen titleFullText, um stattdessen den
   * kompletten textContent zu nehmen. */
  titleSelector: string;
  titleAttribute?: string;
  titleFullText?: boolean;
  /** Selektor für den Link zur Event-Detailseite (wird als externalId UND
   * als url verwendet — der Link ist auf solchen Seiten praktisch immer
   * pro Event eindeutig und stabil). Optional: manche Seiten (z.B.
   * residenz-muenchen.de) verlinken nicht jedes Event einzeln, sondern nur
   * auf einen gemeinsamen Ticketanbieter — ohne urlSelector bleiben
   * url/externalId null und die Zuordnung läuft über den Fuzzy-Match
   * (Titel+Venue+Zeit) statt über die exakte (source_id, external_id)-
   * Kurzschluss-Prüfung. */
  urlSelector?: string;
  urlAttribute?: string; // default "href"
  /** Selektor für Datum/Uhrzeit. dateAttribute (z.B. "datetime" bei <time>)
   * wird bevorzugt, sonst wird der Text-Inhalt geparst: unterstützt sowohl
   * "YYYY-MM-DD[ HH:MM]" als auch deutsches Langformat ("27. September
   * 2026" + optional "19 Uhr" irgendwo im selben Text) als auch knappes
   * Format ohne Jahr ("Fr 24 Jul", z.B. st-michael-muenchen.de) — dort wird
   * das Jahr aus dem aktuellen Datum abgeleitet (Kalenderlisten zeigen nur
   * kommende Termine: liegt das Datum im laufenden Jahr bereits > 1 Tag in
   * der Vergangenheit, wird das nächste Jahr angenommen). */
  dateSelector: string;
  dateAttribute?: string;
  /** Separater Selektor für die Uhrzeit, falls sie nicht im selben Element
   * wie das Datum steht (z.B. st-michael-muenchen.de: Datum und Uhrzeit
   * sind zwei getrennte Geschwister-Elemente). Wird an den dateSelector-Text
   * angehängt, bevor geparst wird. */
  timeSelector?: string;
  descriptionSelector?: string;
  imageSelector?: string;
  imageAttribute?: string; // default "src"
  /** Selektor für Tag-/Kategorie-Links relativ zum Item. */
  tagsSelector?: string;
  /** Nur Items behalten, bei denen mindestens ein Tag (kleingeschrieben)
   * eine dieser Zeichenketten enthält — z.B. ["musik", "klassik"]. Leer/
   * fehlend = keine Filterung. */
  includeIfTagContains?: string[];
  /** Regex (als String) gegen den href eines Tag-Links — der Text des
   * ERSTEN Tags, dessen href matcht, wird als venueName verwendet. Für
   * Seiten, die mehrere Säle/Räume unter einer Sammel-URL listen und den
   * Saal nur über das Link-Ziel eines Tags markieren (z.B. gasteig.de). */
  venueTagHrefPattern?: string;
  /** Fallback, falls kein Tag zu venueTagHrefPattern passt (z.B. die
   * gebäudeweite Location statt des einzelnen Saals). */
  venueTagFallbackHrefPattern?: string;
  /** Direkter Selektor für einen Venue-Namen-Text relativ zum Item — für
   * die häufigere Seitenstruktur mit einem eigenen Venue-Element statt
   * Gasteigs Tag-Link-System. Hat Vorrang vor venueTagHrefPattern, falls
   * beide gesetzt sind. */
  venueSelector?: string;
  /** Nur Items behalten, deren (kleingeschriebener) venueName mindestens
   * eine dieser Zeichenketten enthält — z.B. ["isarphilharmonie"], um von
   * einer Seite mit Tourneedaten nur Münchner Konzerte zu behalten. Leer/
   * fehlend = keine Filterung nach Venue. */
  venueAllowlist?: string[];
  /** Basis-URL zum Auflösen relativer href/src-Werte. */
  baseUrl?: string;
  /** CSS-Selektor für einen "nächste Seite"-Link. Manche Quellen (z.B.
   * residenz-muenchen.de) haben keine vorhersagbare Seitennummer-URL-
   * Systematik (Seite 1 nutzt einen anderen Parameter-Wert als Seite 2), der
   * Link muss also pro Seite aus dem jeweiligen HTML gelesen und verfolgt
   * werden statt eine Ziel-URL zu berechnen — siehe extractNextPageUrl()
   * und den Paginierungs-Loop in index.ts. Fehlt dieses Feld, wird nur eine
   * einzelne Seite abgerufen (bisheriges Verhalten, keine Breaking Change
   * für bestehende Quellen). */
  nextPageSelector?: string;
  /** Attribut, das die nächste Seite trägt, falls kein href (z.B. ein reiner
   * JS-Button wie erzbistum-muenchen.de's `<button data-page="2">` ohne
   * eigenen Link). Default "href". Element mit einem "disabled"-Attribut
   * gilt als letzte Seite (kein Fehler, beendet nur die Paginierung). */
  nextPageAttribute?: string;
  /** Falls gesetzt, wird der gelesene Attributwert NICHT als relative URL
   * aufgelöst, sondern als Wert für diesen Query-Parameter auf der
   * AKTUELLEN Seiten-URL gesetzt (z.B. "_page" bei erzbistum-muenchen.de,
   * das serverseitig nur `?_page=N` auswertet statt echte Seiten-Links zu
   * rendern). */
  nextPageParam?: string;
  /** Millisekunden Pause vor jedem Paginierungs-Folgerequest — für Quellen,
   * deren robots.txt einen Crawl-Delay nennt (z.B. erzbistum-muenchen.de:
   * "Crawl-delay: 30"). Ohne dieses Feld kein Delay (bisheriges Verhalten). */
  crawlDelayMs?: number;
  /** Items verwerfen, deren Titel (kleingeschrieben) eine dieser
   * Zeichenketten enthält — z.B. um einen gemischten Musik-Feed auf
   * klassische Konzerte einzugrenzen (nicht-klassische Programmpunkte wie
   * "Marktmusik" haben dort kein eigenes Tag/Kategorie-Feld, nur den
   * Titeltext). Leer/fehlend = keine Filterung. */
  titleExcludeIfContains?: string[];
}

/** Löst den "nächste Seite"-Link relativ zur AKTUELL abgerufenen Seiten-URL
 * auf (nicht relativ zu config.baseUrl, das für Detail-/Bild-Links relativ
 * zur Seitenwurzel gedacht ist — die nächste-Seite-URL ist typischerweise
 * relativ zur aktuellen Suchergebnis-URL selbst, inklusive derselben
 * Query-Parameter-Basis). Gibt null zurück, wenn kein nextPageSelector
 * konfiguriert ist oder kein passendes Element mit href gefunden wird —
 * beides beendet die Paginierung, kein Fehler. */
export function extractNextPageUrl(
  html: string,
  config: ScrapeConfig,
  currentPageUrl: string,
): string | null {
  if (!config.nextPageSelector) return null;
  try {
    const { document } = parseHTML(html);
    const el = document.querySelector(config.nextPageSelector);
    if (!el || el.hasAttribute?.("disabled")) return null;
    const value = el.getAttribute?.(config.nextPageAttribute ?? "href");
    if (!value) return null;
    if (config.nextPageParam) {
      const url = new URL(currentPageUrl);
      url.searchParams.set(config.nextPageParam, value);
      return url.toString();
    }
    return new URL(value, currentPageUrl).toString();
  } catch {
    return null;
  }
}

export function parseScrape(html: string, config: ScrapeConfig): ParseResult {
  const events: RawEvent[] = [];
  const errors: string[] = [];

  if (!config || typeof config !== "object" || !config.itemSelector) {
    errors.push(
      "scrape source is missing a valid config (itemSelector is required) — see ScrapeConfig in parsers/scrape.ts",
    );
    return { events, errors };
  }

  let document: Document;
  try {
    ({ document } = parseHTML(html));
  } catch (err) {
    errors.push(
      `failed to parse HTML: ${err instanceof Error ? err.message : String(err)}`,
    );
    return { events, errors };
  }

  const items = document.querySelectorAll(config.itemSelector);
  if (items.length === 0) {
    errors.push(
      `no elements matched itemSelector "${config.itemSelector}" — the site's markup may have changed`,
    );
    return { events, errors };
  }

  items.forEach((item, i) => {
    const label = `item ${i + 1}`;
    try {
      const title = extractText(
        item,
        config.titleSelector,
        config.titleAttribute,
        !config.titleFullText,
      );
      if (!title) {
        errors.push(`${label}: no title found via "${config.titleSelector}", skipped`);
        return;
      }
      if (config.titleExcludeIfContains?.length) {
        const titleLower = title.toLowerCase();
        if (config.titleExcludeIfContains.some((s) => titleLower.includes(s.toLowerCase()))) {
          return; // not an error — deliberately filtered out, e.g. non-classical items on a mixed feed
        }
      }

      const url = config.urlSelector
        ? resolveUrl(
          extractText(item, config.urlSelector, config.urlAttribute ?? "href"),
          config.baseUrl,
        )
        : null;

      const dateRaw = extractText(item, config.dateSelector, config.dateAttribute);
      const timeRaw = config.timeSelector ? extractText(item, config.timeSelector) : null;
      const combinedDateRaw = timeRaw ? `${dateRaw ?? ""} ${timeRaw}`.trim() : dateRaw;
      const startDateTime = combinedDateRaw ? parseFlexibleDate(combinedDateRaw) : null;
      if (!startDateTime) {
        errors.push(`${label} ("${title}"): no parseable date via "${config.dateSelector}" (got "${combinedDateRaw}"), skipped`);
        return;
      }

      const tagEls = config.tagsSelector ? Array.from(item.querySelectorAll(config.tagsSelector)) : [];
      // deno-lint-ignore no-explicit-any
      const tags = tagEls.map((t: any) => ({
        text: (t.textContent ?? "").trim(),
        href: t.getAttribute?.("href") ?? null,
      }));
      const tagTextsLower = tags.map((t) => t.text.toLowerCase());

      if (config.includeIfTagContains && config.includeIfTagContains.length > 0) {
        const wanted = config.includeIfTagContains.map((s) => s.toLowerCase());
        const matches = tagTextsLower.some((tag) => wanted.some((w) => tag.includes(w)));
        if (!matches) return; // not an error — most items on a general listing page are expected to be filtered out
      }

      // Sites that list multiple rooms/halls under one page (e.g. a venue
      // complex) can mark the room-specific tag via its link target rather
      // than its visible text — venueTagHrefPattern lets a config pick that
      // tag out instead of guessing from tag text alone. Falls back to
      // venueTagFallbackHrefPattern (e.g. the building-level location) if no
      // room-level tag matches. An event can carry SEVERAL room tags at once
      // (a festival spanning multiple halls) — if includeIfTagContains is
      // itself being used as a room filter, prefer whichever room-pattern
      // tag actually matches it over just the first one in DOM order, so a
      // multi-room event gets attributed to the room it was filtered for
      // rather than an arbitrary other room on the same event.
      const roomMatches = config.venueTagHrefPattern
        ? tags.filter((t) => t.href && new RegExp(config.venueTagHrefPattern!).test(t.href))
        : [];
      let venueName: string | null = null;
      if (roomMatches.length > 0) {
        const wanted = (config.includeIfTagContains ?? []).map((s) => s.toLowerCase());
        venueName = roomMatches.find((t) => wanted.includes(t.text.toLowerCase()))?.text
          ?? roomMatches[0].text;
      }
      if (!venueName && config.venueTagFallbackHrefPattern) {
        const re = new RegExp(config.venueTagFallbackHrefPattern);
        venueName = tags.find((t) => t.href && re.test(t.href))?.text ?? null;
      }
      if (config.venueSelector) {
        venueName = extractText(item, config.venueSelector) ?? venueName;
      }

      if (config.venueAllowlist && config.venueAllowlist.length > 0) {
        const wanted = config.venueAllowlist.map((s) => s.toLowerCase());
        const venueOk = venueName != null &&
          wanted.some((w) => venueName!.toLowerCase().includes(w));
        if (!venueOk) return; // not an error — a listing spanning many venues is expected to filter most items out
      }

      const description = config.descriptionSelector
        ? extractText(item, config.descriptionSelector)
        : null;
      const imageUrl = config.imageSelector
        ? resolveUrl(
          extractText(item, config.imageSelector, config.imageAttribute ?? "src"),
          config.baseUrl,
        )
        : null;

      events.push({
        externalId: url, // the detail-page URL is the natural stable id for a scraped item
        title,
        description,
        startDateTime,
        endDateTime: null,
        venueName,
        venueAddress: null,
        url,
        imageUrl,
        priceMin: null,
        priceMax: null,
        isFree: tagTextsLower.some((t) => t.includes("gratis") || t.includes("kostenlos")) || null,
      });
    } catch (err) {
      errors.push(
        `${label}: unexpected error — ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  });

  return { events, errors };
}

// deno-lint-ignore no-explicit-any
function extractText(root: any, selector: string, attribute?: string, firstTextNodeOnly = false): string | null {
  const el = root.querySelector(selector);
  if (!el) return null;
  if (attribute) {
    const val = el.getAttribute(attribute);
    return val ? val.trim() : null;
  }
  if (firstTextNodeOnly) {
    // NOT just the first text-node child's own content — linkedom's HTML
    // tokenizer splits a single run of text into SEVERAL sibling text nodes
    // at every named character reference (e.g. "Lobet &amp; Singet" becomes
    // three text nodes: "Lobet ", "&", " Singet"). Stopping at the first one
    // silently truncated any title/text containing an entity (&, umlauts as
    // &auml; etc.) right before it — concatenate ALL direct text-node
    // children instead. Still deliberately excludes nested ELEMENT children
    // (e.g. a subtitle <span>), which is the actual intent of this mode.
    const text = Array.from(el.childNodes)
      // deno-lint-ignore no-explicit-any
      .filter((child: any) => child.nodeType === 3 /* TEXT_NODE */)
      // deno-lint-ignore no-explicit-any
      .map((child: any) => child.textContent ?? "")
      .join("")
      .replace(/\s+/g, " ")
      .trim();
    return text || null;
  }
  const text = (el.textContent ?? "").replace(/\s+/g, " ").trim();
  return text || null;
}

function resolveUrl(value: string | null, baseUrl?: string): string | null {
  if (!value) return null;
  if (!baseUrl) return value;
  try {
    return new URL(value, baseUrl).toString();
  } catch {
    return value;
  }
}

const GERMAN_MONTHS: Record<string, number> = {
  "januar": 1,
  "februar": 2,
  "märz": 3,
  "maerz": 3,
  "april": 4,
  "mai": 5,
  "juni": 6,
  "juli": 7,
  "august": 8,
  "september": 9,
  "oktober": 10,
  "november": 11,
  "dezember": 12,
};

const GERMAN_MONTHS_ABBR: Record<string, number> = {
  "jan": 1,
  "feb": 2,
  "mär": 3,
  "mrz": 3,
  "apr": 4,
  "mai": 5,
  "jun": 6,
  "jul": 7,
  "aug": 8,
  "sep": 9,
  "okt": 10,
  "nov": 11,
  "dez": 12,
};

/** Handles "YYYY-MM-DD[ HH:MM]" (gasteig.de's <time datetime> format), as a
 * fallback German long-form date text with an optional "N Uhr" time
 * anywhere in the same string — e.g. "Sonntag, 27. September 2026 19 Uhr"
 * (residenz-muenchen.de, which has no machine-readable date attribute at
 * all) — and, as a final fallback, abbreviated month with no year at all —
 * e.g. "Fr 24 Jul 20:00 Uhr" (st-michael-muenchen.de, which never states
 * the year anywhere, not even on its own detail pages) — where the year is
 * inferred from the current date (see inferYear). Assumes Europe/Berlin
 * local time throughout, same DST logic as parsers/rss.ts's
 * toIsoWithBerlinOffset. */
function parseFlexibleDate(raw: string): string | null {
  const text = raw.trim();

  // Optionales 6. Capture-Group: "Z" oder ein expliziter "+HH:MM"/"-HHMM"-
  // Offset. gasteig.de's <time datetime> ist naive Lokalzeit ohne Suffix
  // (z.B. "2026-07-21 17:00") — dafür ist die Berlin-Offset-Ableitung
  // unten korrekt. muenchen.hoertnagel.de dagegen liefert eine ECHTE UTC-
  // Instanz mit "Z" (z.B. "2026-11-01T15:00:00Z" für 16:00 Ortszeit) — ohne
  // diese Fallunterscheidung würde die Stunde fälschlich nochmal als
  // Lokalzeit interpretiert und der Berlin-Offset ein zweites Mal
  // draufgerechnet (1-2h Versatz).
  const iso = text.match(
    /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::\d{2})?)?(Z|[+-]\d{2}:?\d{2})?/,
  );
  if (iso) {
    const year = parseInt(iso[1], 10);
    const month = parseInt(iso[2], 10);
    const day = parseInt(iso[3], 10);
    const hour = iso[4] !== undefined ? parseInt(iso[4], 10) : 0;
    const minute = iso[5] !== undefined ? parseInt(iso[5], 10) : 0;
    if (iso[6]) {
      const pad2 = (n: number) => n.toString().padStart(2, "0");
      const offset = iso[6] === "Z"
        ? "+00:00"
        : iso[6].length === 5
        ? `${iso[6].slice(0, 3)}:${iso[6].slice(3)}`
        : iso[6];
      return `${year}-${pad2(month)}-${pad2(day)}T${pad2(hour)}:${pad2(minute)}:00${offset}`;
    }
    return toBerlinIsoString(year, month, day, hour, minute);
  }

  const german = text.match(
    /(\d{1,2})\.\s*(Januar|Februar|März|Maerz|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)\s*(\d{4})/i,
  );
  if (german) {
    const day = parseInt(german[1], 10);
    const month = GERMAN_MONTHS[german[2].toLowerCase()];
    const year = parseInt(german[3], 10);
    if (!month) return null;
    const timeMatch = text.match(/(\d{1,2})(?:[:.](\d{2}))?\s*Uhr/i);
    const hour = timeMatch ? parseInt(timeMatch[1], 10) : 0;
    const minute = timeMatch && timeMatch[2] !== undefined ? parseInt(timeMatch[2], 10) : 0;
    return toBerlinIsoString(year, month, day, hour, minute);
  }

  // Deutscher Monatsname (ausgeschrieben ODER abgekürzt) OHNE Jahr, mit
  // Punkt direkt hinterm Tag (z.B. "09. Mai" UND "06. Jun" — beide Formen
  // kommen auf derselben toelzerknabenchor.de-Kalenderliste vor: nahe
  // Termine schreiben den Monat aus, weiter entfernte kürzen ihn ab). Anders
  // als der abbreviated-Fallback unten (für Seiten wie st-michael-
  // muenchen.de, "Fr 24 Jul" — Ziffer+Whitespace+Buchstaben OHNE Punkt
  // dazwischen) steht hier zwingend ein "." zwischen Tag und Monat, daher
  // eigener Block statt Wiederverwendung. Uhrzeit kommt per timeSelector als
  // eigenes "HH:MM"-Element dazu, wie beim TT.MM.-Kurzformat unten, nicht
  // als "N Uhr"-Text wie beim german-Block oben. Muss NACH dem german-Block
  // stehen, sonst würde er Daten MIT Jahr vorzeitig ohne Jahr interpretieren.
  const germanNoYear = text.match(
    /(\d{1,2})\.\s*([A-Za-zÄÖÜäöü]{3,})\b/i,
  );
  if (germanNoYear) {
    const day = parseInt(germanNoYear[1], 10);
    const nameLower = germanNoYear[2].toLowerCase();
    const month = GERMAN_MONTHS[nameLower] ?? GERMAN_MONTHS_ABBR[nameLower.slice(0, 3)];
    if (month) {
      const timeMatch = text.match(/(\d{1,2}):(\d{2})/);
      const hour = timeMatch ? parseInt(timeMatch[1], 10) : 0;
      const minute = timeMatch ? parseInt(timeMatch[2], 10) : 0;
      const year = inferYear(month, day, hour, minute);
      return toBerlinIsoString(year, month, day, hour, minute);
    }
  }

  // Rein numerisches deutsches Kurzformat "TT.MM." ohne Jahr (z.B.
  // muenchener-biennale.de: Kalenderliste zeigt nur "23.04.", Jahr steht nur
  // im Seitentitel/Zeitraum, nicht pro Termin). Uhrzeit kommt hier über
  // timeSelector als eigenes Element dazu (z.B. "18:00") und wird an den
  // Datumstext angehängt, bevor geparst wird — Doppelpunkt statt "Uhr"
  // unterscheidet die Uhrzeit zuverlässig von den Punkten im Datum selbst.
  const numericGerman = text.match(/(\d{1,2})\.(\d{1,2})\.(?:(\d{4}))?/);
  if (numericGerman) {
    const day = parseInt(numericGerman[1], 10);
    const month = parseInt(numericGerman[2], 10);
    if (month >= 1 && month <= 12) {
      const timeMatch = text.match(/(\d{1,2}):(\d{2})/);
      const hour = timeMatch ? parseInt(timeMatch[1], 10) : 0;
      const minute = timeMatch ? parseInt(timeMatch[2], 10) : 0;
      const year = numericGerman[3]
        ? parseInt(numericGerman[3], 10)
        : inferYear(month, day, hour, minute);
      return toBerlinIsoString(year, month, day, hour, minute);
    }
  }

  // No period-after-day and no 4-digit year, e.g. "Fr 24 Jul" — the leading
  // weekday abbreviation has no digit before it, so matching "digit(s) +
  // whitespace + letters" directly lands on "24 Jul" without needing to
  // explicitly strip "Fr" first.
  const abbreviated = text.match(/(\d{1,2})\s+([A-Za-zÄÖÜäöü]{3,4})\b/);
  if (abbreviated) {
    const day = parseInt(abbreviated[1], 10);
    const month = GERMAN_MONTHS_ABBR[abbreviated[2].toLowerCase().slice(0, 3)];
    if (month) {
      const timeMatch = text.match(/(\d{1,2})(?:[:.](\d{2}))?\s*Uhr/i);
      const hour = timeMatch ? parseInt(timeMatch[1], 10) : 0;
      const minute = timeMatch && timeMatch[2] !== undefined ? parseInt(timeMatch[2], 10) : 0;
      const year = inferYear(month, day, hour, minute);
      return toBerlinIsoString(year, month, day, hour, minute);
    }
  }

  return null;
}

/** Calendar listings only ever show upcoming events, so a year-less date is
 * either this year or next. If reading it in the current year would already
 * be more than a day in the past, it must mean next year instead (e.g. "15
 * Jan" encountered while scraping in December). The 1-day buffer absorbs
 * the Berlin-vs-UTC offset without needing exact timezone math here. */
function inferYear(month: number, day: number, hour: number, minute: number): number {
  const now = new Date();
  const currentYear = now.getUTCFullYear();
  const candidateMs = Date.UTC(currentYear, month - 1, day, hour, minute);
  const oneDayMs = 24 * 60 * 60 * 1000;
  return candidateMs < now.getTime() - oneDayMs ? currentYear + 1 : currentYear;
}

function toBerlinIsoString(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
): string | null {
  const d = new Date(Date.UTC(year, month - 1, day));
  if (d.getUTCFullYear() !== year || d.getUTCMonth() !== month - 1 || d.getUTCDate() !== day) {
    return null;
  }
  const isSummer = isBerlinSummerTime(year, month, day, hour);
  const offset = isSummer ? "+02:00" : "+01:00";
  const pad = (n: number) => n.toString().padStart(2, "0");
  return `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:00${offset}`;
}

function isBerlinSummerTime(year: number, month: number, day: number, hour: number): boolean {
  const naiveMs = Date.UTC(year, month - 1, day, hour);
  const dstStart = lastSundayUtcMs(year, 2, 1);
  const dstEnd = lastSundayUtcMs(year, 9, 1);
  return naiveMs >= dstStart && naiveMs < dstEnd;
}

function lastSundayUtcMs(year: number, monthIndex0: number, hour: number): number {
  const lastDayOfMonth = new Date(Date.UTC(year, monthIndex0 + 1, 0)).getUTCDate();
  const lastDate = new Date(Date.UTC(year, monthIndex0, lastDayOfMonth));
  const dow = lastDate.getUTCDay();
  const lastSundayDate = lastDayOfMonth - dow;
  return Date.UTC(year, monthIndex0, lastSundayDate, hour);
}
