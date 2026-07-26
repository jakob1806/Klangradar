// Schema.org (JSON-LD) connector for ingest-source.
//
// Input is the raw HTTP response body of a source URL. It can be either:
//   (a) raw JSON — a single JSON-LD node, an array of nodes, or a node with
//       an "@graph" array, or
//   (b) an HTML document containing one or more
//       <script type="application/ld+json">...</script> tags (each of which
//       can itself contain any of the shapes in (a)).
//
// We normalize both into a flat list of JSON-LD "candidate" nodes, keep only
// the ones whose @type looks like a schema.org Event (or subtype), and map
// each into a RawEvent. Anything that isn't recognizably an Event is
// silently skipped (it's expected noise — Organization/WebSite/BreadcrumbList
// nodes are commonly mixed into the same JSON-LD graph). Only genuine parse
// failures on something that *is* typed as an Event go into `errors`, so one
// malformed item never aborts the whole source.

import type { ParseResult, RawEvent } from "../types.ts";

export function parseSchemaOrg(content: string): ParseResult {
  const errors: string[] = [];
  const events: RawEvent[] = [];

  if (typeof content !== "string" || content.trim() === "") {
    errors.push("Empty response body");
    return { events, errors };
  }

  const cleaned = stripBom(content);
  const scriptBlocks = extractLdJsonScripts(cleaned);
  // If we found <script type="application/ld+json"> tags, use their contents.
  // Otherwise assume the whole body is a raw JSON-LD document.
  const jsonTexts = scriptBlocks.length > 0 ? scriptBlocks : [cleaned];

  const rawValues: unknown[] = [];
  jsonTexts.forEach((text, i) => {
    const trimmed = text.trim();
    if (!trimmed) return;

    const parsed = tryParseJson(trimmed);
    if (parsed.ok) {
      rawValues.push(parsed.value);
      return;
    }
    // parsed.ok is false here (we returned above on true) — asserted rather
    // than relying on narrowing, which some tsconfigs don't carry through
    // this union cleanly (value: unknown appears to be a factor).
    const firstError = (parsed as { ok: false; error: string }).error;

    // Some CMSs HTML-escape the JSON-LD script body (e.g. `&amp;` for `&`),
    // which is invalid per the HTML spec (script content is raw text) but
    // happens in practice. Retry once with entities decoded before giving up.
    const decoded = decodeHtmlEntities(trimmed);
    const retried = decoded !== trimmed ? tryParseJson(decoded) : null;
    if (retried?.ok) {
      rawValues.push(retried.value);
      return;
    }

    errors.push(`Failed to parse JSON-LD block ${i + 1}: ${firstError}`);
  });

  if (scriptBlocks.length === 0 && rawValues.length === 0 && errors.length === 0) {
    // Body wasn't script-tagged HTML and JSON.parse never ran (empty text) —
    // shouldn't normally happen given the trim() check above, but guard
    // against silently returning zero events with zero explanation.
    errors.push("No JSON-LD content found in response body");
  }

  const candidates: Record<string, unknown>[] = [];
  for (const value of rawValues) {
    candidates.push(...flattenJsonLd(value));
  }

  candidates.forEach((candidate, i) => {
    if (!isEventCandidate(candidate)) return;

    const title = getLocalizedString(candidate.name);
    if (!title) {
      errors.push(`Event candidate ${i + 1}: missing required "name"`);
      return;
    }

    const startDateTime = parseDateToIso(candidate.startDate);
    if (!startDateTime) {
      errors.push(`Event "${title}": missing or invalid required "startDate"`);
      return;
    }

    const endDateTime = parseDateToIso(candidate.endDate);
    const description = getLocalizedString(candidate.description);
    const { venueName, venueAddress } = extractVenue(candidate.location);
    const url = typeof candidate.url === "string" && candidate.url.trim()
      ? candidate.url.trim()
      : null;
    const imageUrl = extractImageUrl(candidate.image);
    const externalId = extractExternalId(candidate);

    const pricing = extractPricing(candidate.offers);
    const topLevelFree = candidate.isAccessibleForFree === true;
    const isFree = topLevelFree ? true : pricing.isFree;

    events.push({
      externalId,
      title,
      description,
      startDateTime,
      endDateTime,
      venueName,
      venueAddress,
      url,
      imageUrl,
      priceMin: pricing.priceMin,
      priceMax: pricing.priceMax,
      isFree,
    });
  });

  return { events, errors };
}

// ---------------------------------------------------------------------------
// HTML extraction
// ---------------------------------------------------------------------------

function stripBom(text: string): string {
  return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

function extractLdJsonScripts(html: string): string[] {
  const results: string[] = [];
  // Deliberately lenient: match any <script ...> tag and check its attribute
  // text for the ld+json mime type, rather than anchoring on a specific
  // attribute order/quote style (real-world markup varies: single quotes,
  // no quotes, extra id="..."/class="..." attributes, etc.).
  const scriptRegex = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
  let match: RegExpExecArray | null;
  while ((match = scriptRegex.exec(html)) !== null) {
    const attrs = match[1];
    if (/type\s*=\s*["']?\s*application\/ld\+json\s*["']?/i.test(attrs)) {
      results.push(match[2]);
    }
  }
  return results;
}

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#x27;/gi, "'")
    .replace(/&#(\d+);/g, (_, dec: string) => String.fromCharCode(parseInt(dec, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex: string) => String.fromCharCode(parseInt(hex, 16)))
    // Must run last: otherwise "&amp;lt;" would decode to "<" instead of "&lt;".
    .replace(/&amp;/g, "&");
}

function tryParseJson(text: string): { ok: true; value: unknown } | { ok: false; error: string } {
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

// ---------------------------------------------------------------------------
// JSON-LD tree flattening
// ---------------------------------------------------------------------------

/**
 * Flattens an arbitrary parsed JSON-LD value into a list of plain object
 * nodes, unwrapping top-level arrays and "@graph" wrappers. Non-object,
 * non-array values are dropped.
 */
function flattenJsonLd(value: unknown): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];

  const visit = (v: unknown): void => {
    if (v == null || typeof v !== "object") return;

    if (Array.isArray(v)) {
      for (const item of v) visit(item);
      return;
    }

    const obj = v as Record<string, unknown>;
    if (Array.isArray(obj["@graph"])) {
      // A "@graph" wrapper node is (almost always) just a container — its
      // children carry the actual @type. We don't also push the wrapper
      // itself, so a node that somehow has both "@graph" and its own
      // "@type": "Event" would be missed; that shape doesn't occur in
      // practice for schema.org event feeds.
      visit(obj["@graph"]);
      return;
    }

    out.push(obj);
  };

  visit(value);
  return out;
}

// ---------------------------------------------------------------------------
// @type matching
// ---------------------------------------------------------------------------

// schema.org subtypes of Event whose name doesn't itself contain the
// substring "Event" (Event, MusicEvent, TheaterEvent, ScreeningEvent, ... all
// match the substring check below; Festival is the notable exception since
// it's a subClassOf Event without "Event" in its name).
const EVENT_TYPE_ALLOWLIST = new Set(["Festival"]);

function normalizeTypeName(t: unknown): string | null {
  if (typeof t !== "string") return null;
  const trimmed = t.trim();
  if (!trimmed) return null;
  // @type is sometimes a full IRI like "https://schema.org/MusicEvent"
  // rather than a bare name — take the last path/fragment segment.
  const idx = Math.max(trimmed.lastIndexOf("/"), trimmed.lastIndexOf("#"));
  return idx >= 0 ? trimmed.slice(idx + 1) : trimmed;
}

function getTypeNames(candidate: Record<string, unknown>): string[] {
  const raw = candidate["@type"];
  const list = Array.isArray(raw) ? raw : raw != null ? [raw] : [];
  return list
    .map(normalizeTypeName)
    .filter((t): t is string => t !== null);
}

function isEventCandidate(candidate: Record<string, unknown>): boolean {
  return getTypeNames(candidate).some(
    (t) => t.includes("Event") || EVENT_TYPE_ALLOWLIST.has(t),
  );
}

// ---------------------------------------------------------------------------
// Field extraction helpers
// ---------------------------------------------------------------------------

/**
 * Resolves a schema.org string-valued property that might be a plain
 * string, an array (take the first resolvable entry — used for multi-
 * language alternatives), or a JSON-LD language-tagged value object of the
 * form { "@value": "...", "@language": "..." }.
 */
function getLocalizedString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed || null;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const resolved = getLocalizedString(item);
      if (resolved) return resolved;
    }
    return null;
  }
  if (value != null && typeof value === "object") {
    const obj = value as Record<string, unknown>;
    if (typeof obj["@value"] === "string") {
      const trimmed = obj["@value"].trim();
      return trimmed || null;
    }
  }
  return null;
}

function parseDateToIso(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  const d = new Date(trimmed);
  if (isNaN(d.getTime())) return null;
  // Normalize to a real ISO 8601 UTC string — the RawEvent contract requires
  // ISO 8601 and schema.org sources are inconsistent about it (some use
  // "YYYY-MM-DD HH:mm:ss", date-only values, non-padded offsets, etc.). This
  // preserves the correct time instant but not the source's original UTC
  // offset; timestamptz columns downstream only care about the instant.
  return d.toISOString();
}

function extractAddress(address: unknown): string | null {
  if (address == null) return null;
  if (typeof address === "string") {
    const trimmed = address.trim();
    return trimmed || null;
  }
  if (Array.isArray(address)) {
    for (const item of address) {
      const resolved = extractAddress(item);
      if (resolved) return resolved;
    }
    return null;
  }
  if (typeof address === "object") {
    // PostalAddress
    const a = address as Record<string, unknown>;
    const street = typeof a.streetAddress === "string" ? a.streetAddress.trim() : "";
    const zip = typeof a.postalCode === "string"
      ? a.postalCode.trim()
      : typeof a.postalCode === "number"
      ? String(a.postalCode)
      : "";
    const city = typeof a.addressLocality === "string" ? a.addressLocality.trim() : "";
    const cityLine = [zip, city].filter(Boolean).join(" ");
    const parts = [street, cityLine].filter(Boolean);
    const joined = parts.join(", ");
    return joined || null;
  }
  return null;
}

function extractVenue(location: unknown): { venueName: string | null; venueAddress: string | null } {
  // location can occasionally be an array (e.g. multiple alternate venues) —
  // we only support a single venue per event, so take the first entry.
  const loc = Array.isArray(location) ? location[0] : location;

  if (loc == null) return { venueName: null, venueAddress: null };

  if (typeof loc === "string") {
    const trimmed = loc.trim();
    return { venueName: trimmed || null, venueAddress: null };
  }

  if (typeof loc === "object") {
    const obj = loc as Record<string, unknown>;
    const venueName = getLocalizedString(obj.name);
    const venueAddress = extractAddress(obj.address);
    return { venueName, venueAddress };
  }

  return { venueName: null, venueAddress: null };
}

function extractImageUrl(image: unknown): string | null {
  if (image == null) return null;

  if (typeof image === "string") {
    const trimmed = image.trim();
    return trimmed || null;
  }

  if (Array.isArray(image)) {
    for (const item of image) {
      const resolved = extractImageUrl(item);
      if (resolved) return resolved;
    }
    return null;
  }

  if (typeof image === "object") {
    // ImageObject
    const obj = image as Record<string, unknown>;
    if (typeof obj.url === "string" && obj.url.trim()) return obj.url.trim();
    // "contentUrl" is the other schema.org ImageObject property commonly
    // used for the actual asset URL; not in the task spec but seen often
    // enough in the wild to be worth a fallback.
    if (typeof obj.contentUrl === "string" && obj.contentUrl.trim()) return obj.contentUrl.trim();
  }

  return null;
}

function parseNumeric(v: unknown): number | null {
  if (typeof v === "number") return isFinite(v) ? v : null;
  if (typeof v !== "string") return null;
  const trimmed = v.trim();
  if (!trimmed) return null;
  let n = Number(trimmed);
  if (!isFinite(n)) {
    // Fallback for a comma decimal separator, e.g. "19,99".
    n = Number(trimmed.replace(",", "."));
  }
  return isFinite(n) ? n : null;
}

function normalizeToArray(value: unknown): unknown[] {
  if (value == null) return [];
  return Array.isArray(value) ? value : [value];
}

function extractPricing(
  offersRaw: unknown,
): { priceMin: number | null; priceMax: number | null; isFree: boolean | null } {
  const offers = normalizeToArray(offersRaw).filter(
    (o): o is Record<string, unknown> => o != null && typeof o === "object",
  );

  if (offers.length === 0) {
    return { priceMin: null, priceMax: null, isFree: null };
  }

  const prices: number[] = [];
  let hasFreeSignal = false;

  for (const offer of offers) {
    if (offer.isAccessibleForFree === true) hasFreeSignal = true;

    const price = parseNumeric(offer.price);
    if (price !== null) {
      prices.push(price);
      if (price === 0) hasFreeSignal = true;
    }

    // AggregateOffer uses lowPrice/highPrice instead of a single "price".
    // Not in the task spec's field list, but AggregateOffer is extremely
    // common in real-world event JSON-LD (Eventbrite, Ticketmaster, etc.),
    // so we fold it into the same min/max computation.
    const low = parseNumeric(offer.lowPrice);
    const high = parseNumeric(offer.highPrice);
    if (low !== null) {
      prices.push(low);
      if (low === 0) hasFreeSignal = true;
    }
    if (high !== null) prices.push(high);
  }

  const priceMin = prices.length > 0 ? Math.min(...prices) : null;
  const priceMax = prices.length > 0 ? Math.max(...prices) : null;

  // isFree stays `null` (unknown) rather than `false` when we have offer
  // nodes but couldn't determine any actual price from them — `false` would
  // wrongly assert we *know* it's paid.
  const isFree = hasFreeSignal ? true : prices.length > 0 ? false : null;

  return { priceMin, priceMax, isFree };
}

// ---------------------------------------------------------------------------
// Bild-Extraktion für Quellen ohne eigenen schema_org-Sourcetyp
// ---------------------------------------------------------------------------

export interface JsonLdEventImage {
  url: string;
  credits: string | null;
}

/** Sucht das Bild des ersten Event-Kandidaten in beliebigem HTML mit
 * eingebettetem JSON-LD — für den Prioritäts-1-Schritt der
 * Coverbild-Kaskade (coverImageDetection.ts) bei Quellen, die keinen
 * dedizierten "schema_org"-Sourcetyp haben (scrape/rss/ical/api/brso),
 * deren Eventseite aber trotzdem schema.org-Markup einbettet. Reuses
 * dieselbe Flatten-/Typ-Match-/Bild-Extraktions-Logik wie parseSchemaOrg()
 * selbst, damit beide Wege garantiert dasselbe Bild finden. */
export function extractFirstEventImageFromJsonLd(html: string): JsonLdEventImage | null {
  if (typeof html !== "string" || html.trim() === "") return null;

  const scriptBlocks = extractLdJsonScripts(stripBom(html));
  if (scriptBlocks.length === 0) return null;

  for (const block of scriptBlocks) {
    const trimmed = block.trim();
    if (!trimmed) continue;

    const parsed = tryParseJson(trimmed);
    let value: unknown = null;
    if (parsed.ok) {
      value = parsed.value;
    } else {
      const decoded = decodeHtmlEntities(trimmed);
      const retried = decoded !== trimmed ? tryParseJson(decoded) : null;
      if (retried?.ok) value = retried.value;
    }
    if (value == null) continue;

    for (const candidate of flattenJsonLd(value)) {
      if (!isEventCandidate(candidate)) continue;
      const imageUrl = extractImageUrl(candidate.image);
      if (!imageUrl) continue;
      return { url: imageUrl, credits: extractImageCreditsFromJsonLd(candidate.image) };
    }
  }

  return null;
}

/** schema.org ImageObject trägt optional creditText/copyrightNotice/creator —
 * ein deutlich verlässlicheres Credit-Signal als ein Freitext-Scan der Seite
 * (siehe coverImageDetection.ts's regex-basierten Fallback für Quellen ohne
 * strukturiertes Markup), deshalb hier zuerst versucht. */
function extractImageCreditsFromJsonLd(image: unknown): string | null {
  const obj = Array.isArray(image) ? image[0] : image;
  if (obj == null || typeof obj !== "object") return null;
  const o = obj as Record<string, unknown>;

  const creditText = typeof o.creditText === "string" ? o.creditText.trim() : "";
  if (creditText) return creditText;

  const copyrightNotice = typeof o.copyrightNotice === "string" ? o.copyrightNotice.trim() : "";
  if (copyrightNotice) return copyrightNotice;

  const creator = getLocalizedString(
    o.creator != null && typeof o.creator === "object" && !Array.isArray(o.creator)
      ? (o.creator as Record<string, unknown>).name
      : o.creator,
  );
  return creator;
}

function extractExternalId(candidate: Record<string, unknown>): string | null {
  const id = candidate["@id"];
  if (typeof id === "string" && id.trim()) return id.trim();

  const identifier = candidate["identifier"];
  if (typeof identifier === "string" && identifier.trim()) return identifier.trim();
  if (typeof identifier === "number" && isFinite(identifier)) return String(identifier);
  if (identifier != null && typeof identifier === "object") {
    // PropertyValue
    const obj = identifier as Record<string, unknown>;
    if (typeof obj.value === "string" && obj.value.trim()) return obj.value.trim();
    if (typeof obj.value === "number" && isFinite(obj.value)) return String(obj.value);
  }

  return null;
}
