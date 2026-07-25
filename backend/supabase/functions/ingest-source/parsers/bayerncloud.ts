// BayernCloud Tourismus API connector (data.bayerncloud.digital, dataCycle-
// basiert). ANDERS als jede andere Quelle in diesem Repo: Bearer-Token-
// authentifiziert (siehe index.ts's Auth-Header-Injektion für type='api').
// War ursprünglich nicht live getestet (Token ist Nutzer-Sache), daher
// bewusst DEFENSIV geschrieben: die klar dokumentierten Felder
// (id/name/startDate/endDate/description/copyrightNotice/sdLicense) werden
// mit hoher Zuversicht gemappt, die NICHT klar dokumentierten (Venue-Name
// aus "location", Bild-URL aus "image") mit mehreren Fallback-Versuchen und
// sauberer Degradierung auf null statt eines Crashs.
//
// Live verifiziert am 2026-07-25 (erster gültiger Token): Response ist
// JSON-LD, Event-Liste liegt unter "@graph" (nicht "data" oder ein nacktes
// Array, wie ursprünglich angenommen) — jetzt korrekt abgedeckt. name/
// startDate/endDate/description sind wie angenommen einfache Strings, auch
// bei dc:multilingual=true. "location" fehlte im ersten Testevent, konnte
// also noch nicht bestätigt werden; extractVenue()'s Fallback-Kette bleibt
// vorerst unverändert.
//
// Quelle der Feldnamen: öffentliche OpenAPI-Spec (bayerncloud.digital/
// BayernCloud_API_Documentation_v3.yaml) + ein echtes Anfragebeispiel
// (bayerncloud.digital/docs/api-examples/events-chiemsee-alpenland-
// weihnachten), geprüft am 2026-07-17. Pflicht-Attributionsangabe laut
// Mail von BayernCloud Tourismus: "der entsprechende Urheberrechtsvermerk
// der Datensätze muss mit angegeben werden" (Nutzungsbedingungen Teil C
// §18 dataCycle) — copyrightNotice/sdLicense sind direkt auf jedem
// Event-Objekt vorhanden, siehe RawEvent.attributionNotice/
// attributionLicenseUrl.
//
// location laut Spec: array von { "@id": uuid, "@type": "skos:Concept" }
// — strukturell identisch zu dc:classification, also eher eine
// Gebiets-/Konzept-Referenz als eine Venue-mit-Adresse. Das Anfragebeispiel
// verwendet "include": "...,location,..." — die Annahme hier ist, dass das
// die Referenz zu einem volleren Objekt (mit Name/Adresse) expandiert; das
// ist aber NICHT Teil der statischen OpenAPI-Schema-Doku und daher nicht
// bestätigt. extractVenueName() probiert mehrere plausible Feldnamen.
//
// image laut Spec: nur { id, type } dokumentiert, kein url/contentUrl-Feld
// — Bild-URLs sind daher (noch) nicht extrahierbar; imageUrl bleibt immer
// null, bis das live verifiziert werden kann.

import type { ParseResult, RawEvent } from "../types.ts";

const MUNICH_MARKERS = ["münchen", "muenchen", "munich"];

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

/** location[0] ist laut Spec nur {"@id","@type"} — falls "include" das
 * tatsächlich zu einem volleren Objekt expandiert, probiert das hier
 * mehrere plausible Feldnamen (name/title/label, verschachtelte oder
 * flache Adresse) statt sich auf einen einzigen zu verlassen. */
function extractVenue(location: unknown): { venueName: string | null; venueAddress: string | null } {
  const loc = Array.isArray(location) ? location[0] : location;
  if (!isRecord(loc)) return { venueName: null, venueAddress: null };

  const venueName = firstNonEmptyString(loc.name, loc.title, loc.label, loc["skos:prefLabel"]);

  const addr = isRecord(loc.address) ? loc.address : loc;
  const street = firstNonEmptyString(addr.streetAddress, addr.street);
  const zip = firstNonEmptyString(addr.postalCode, addr.zip);
  const city = firstNonEmptyString(addr.addressLocality, addr.city, addr.locality);
  const cityLine = [zip, city].filter(Boolean).join(" ");
  const venueAddress = [street, cityLine].filter(Boolean).join(", ") || null;

  return { venueName, venueAddress };
}

function isMunichVenue(venueName: string | null, venueAddress: string | null): boolean {
  const haystack = `${venueName ?? ""} ${venueAddress ?? ""}`.toLowerCase();
  return MUNICH_MARKERS.some((m) => haystack.includes(m));
}

export function parseBayernCloud(content: string): ParseResult {
  const errors: string[] = [];
  const events: RawEvent[] = [];

  let raw: unknown;
  try {
    raw = JSON.parse(content);
  } catch (err) {
    errors.push(`Failed to parse response as JSON: ${err instanceof Error ? err.message : String(err)}`);
    return { events, errors };
  }

  // Manche dataCycle-Deployments wrappen die Liste in {"data": [...]} statt
  // ein nacktes Array zurückzugeben — beides wird akzeptiert. Live-
  // verifiziert am 2026-07-25: die tatsächliche Antwort ist JSON-LD mit der
  // Event-Liste unter "@graph" (schema.org-Kontext, siehe "@context").
  const items: unknown[] = Array.isArray(raw)
    ? raw
    : isRecord(raw) && Array.isArray(raw.data)
    ? raw.data
    : isRecord(raw) && Array.isArray(raw["@graph"])
    ? raw["@graph"]
    : [];

  if (items.length === 0) {
    errors.push(
      "Response contained no event items (neither a bare array, {data: [...]}, nor {\"@graph\": [...]}) — check the actual response shape.",
    );
    return { events, errors };
  }

  const nowMs = Date.now();
  let venueExtractedCount = 0;
  let munichCount = 0;

  items.forEach((item, i) => {
    const label = `item ${i + 1}`;
    if (!isRecord(item)) {
      errors.push(`${label}: not an object, skipped`);
      return;
    }

    const title = firstNonEmptyString(item.name);
    if (!title) {
      errors.push(`${label}: missing required "name", skipped`);
      return;
    }

    const startDateTime = firstNonEmptyString(item.startDate);
    const startMs = startDateTime ? new Date(startDateTime).getTime() : NaN;
    if (!startDateTime || isNaN(startMs)) {
      errors.push(`${label} ("${title}"): missing or invalid "startDate", skipped`);
      return;
    }
    // Nur kommende Events — die API-Anfrage selbst filtert (noch) nicht
    // serverseitig nach Datum, siehe Kommentar in der Migration. Numerischer
    // Vergleich statt String-Vergleich: startDate kann mit beliebigem
    // Offset kommen (+01:00/+02:00/Z) — ein reiner String-Vergleich wäre bei
    // unterschiedlichen Offsets nicht zuverlässig chronologisch korrekt.
    if (startMs < nowMs) return;

    const endDateTime = firstNonEmptyString(item.endDate);
    const description = firstNonEmptyString(item.description);

    const { venueName, venueAddress } = extractVenue(item.location);
    if (venueName) venueExtractedCount++;

    // Nur München-Events — die BayernCloud deckt ganz Bayern ab, diese App
    // nur München. Kein Venue-Text = kann nicht beurteilt werden = raus,
    // genau wie ein Venue-Text ohne München-Bezug (nicht als Fehler
    // gewertet, siehe DIFFABLE-Kommentar unten für die Ausnahme).
    if (!isMunichVenue(venueName, venueAddress)) return;
    munichCount++;

    events.push({
      externalId: firstNonEmptyString(item.id),
      title,
      description,
      startDateTime,
      endDateTime,
      venueName,
      venueAddress,
      url: null,
      imageUrl: null, // siehe Datei-Kommentar: kein url-Feld in der Image-Schema-Doku
      priceMin: null,
      priceMax: null,
      isFree: null,
      attributionNotice: firstNonEmptyString(item.copyrightNotice),
      attributionLicenseUrl: firstNonEmptyString(item.sdLicense),
    });
  });

  // Diagnose-Signal statt stillem "0 Events": wenn wirklich KEIN einziges
  // Item einen Venue-Namen hergab, ist das eher ein Zeichen, dass die
  // location-Expansion (include=location) nicht wie angenommen funktioniert
  // hat, als dass zufällig alle Bayern-weiten Events ohne Venue-Angabe sind.
  if (items.length > 0 && venueExtractedCount === 0) {
    errors.push(
      `Diagnostic: none of ${items.length} raw items yielded an extractable venue name from "location" — ` +
        `this likely means the API's "include" expansion for location isn't working as this connector assumes ` +
        `(see extractVenue() in parsers/bayerncloud.ts), not that no events have a venue. Needs live verification.`,
    );
  } else if (venueExtractedCount > 0 && munichCount === 0) {
    errors.push(
      `Diagnostic: ${venueExtractedCount} items had an extractable venue, but none matched a Munich marker ` +
        `(${MUNICH_MARKERS.join("/")}) — plausible if this run genuinely had no Munich-area events, but worth a ` +
        `second look if this repeats every run.`,
    );
  }

  return { events, errors };
}
