// Dritte Termin-Detailseiten-Pipeline nach Staatsoper/BRSO, erste für die
// Multi-City-Erweiterung (Nutzeranfrage: "mache venue-spezifische Hydration-
// Parser wie bei München" für Hamburg/Berlin/Wien/Frankfurt). Live gegen
// echtes HTML verifiziert (Deno, Event "Legende", Produktion 1436/1438):
// die Besetzung steht NICHT im initialen HTML der Event-Seite (nur ein
// "<!-- Placeholder for asynchronous loaded cast and crew -->"), sondern
// wird per Klick auf ein Element mit
// class="js-marker-get-cast-and-crew" data-performance-id="…"
// data-baselink="…" per XHR nachgeladen: GET
// /callbacks/get-cast-and-crew.json?performanceId=…&baselink=…
// liefert { Html: "<div class=\"castcrew\">…" } mit sauber strukturierten
// castcrew__item-Blöcken (Rolle + ein oder mehrere Namen, "/"-getrennt).
//
// Anders als bei der Staatsoper liefert diese Quelle kein separates
// Werk-/Programmverzeichnis (das Stück IST das Event, siehe event.title) —
// deshalb wie hydrate-brso-events nur event_participants, keine event_works.

export interface KomischeOperParticipant {
  name: string;
  profileUrl: string | null;
  role: string | null;
  type: "person" | "ensemble";
}

const CREW_ROLES_TO_SKIP =
  /^(Inszenierung|Regie|B(?:ü|u)hnenbild|Kost(?:ü|u)me?|Licht\s?Design|Sound\s?Design|Video\s?Design|Soundscapes|Dramaturgie|Choreografie|Choreographie|K(?:ü|u)nstlerische Produktionsleitung|Regieassistenz|B(?:ü|u)hnenbildassistenz|Kost(?:ü|u)mbildassistenz|Technischer Direktor|Produktionsleitung|Video)/i;

const CONDUCTOR_ROLE = /Musikalische Leitung|Dirigent/i;
const CHORLEADER_ROLE = /^Chor(?:leitung|einstudierung)?$/i;
const ENSEMBLE_NAME = /(?:orchester|chor|ensemble|ballett)/i;

/** Findet performanceId + baselink des `js-marker-get-cast-and-crew`-Links
 * auf der normal abgerufenen Event-Seite, unabhängig von der Reihenfolge
 * der data-* Attribute im Markup. */
export function extractCastCrewRef(html: string): { performanceId: string; baselink: string } | null {
  const tagMatch = html.match(/<a[^>]*class="[^"]*js-marker-get-cast-and-crew[^"]*"[^>]*>/i);
  if (!tagMatch) return null;
  const tag = tagMatch[0];
  const performanceId = tag.match(/data-performance-id="(\d+)"/)?.[1];
  const baselink = tag.match(/data-baselink="([^"]+)"/)?.[1];
  if (!performanceId || !baselink) return null;
  return { performanceId, baselink: decodeEntities(baselink) };
}

export function castCrewEndpoint(ref: { performanceId: string; baselink: string }): string {
  return `https://www.komische-oper-berlin.de/callbacks/get-cast-and-crew.json?performanceId=${ref.performanceId}&baselink=${encodeURIComponent(ref.baselink)}`;
}

/** Parst die {Html: "…"} JSON-Antwort des callbacks/get-cast-and-crew.json
 * Endpunkts. */
export function parseCastCrewResponse(jsonText: string): KomischeOperParticipant[] {
  let html: string;
  try {
    const parsed = JSON.parse(jsonText);
    html = typeof parsed?.Html === "string" ? parsed.Html : "";
  } catch {
    return [];
  }
  if (!html) return [];

  const participants: KomischeOperParticipant[] = [];
  const seen = new Set<string>();
  const itemRe = /<div class="castcrew__role">([^<]*)<\/div>\s*<div class="castcrew__names">([\s\S]*?)<\/div>\s*<\/div>/g;

  for (const item of html.matchAll(itemRe)) {
    const roleLabel = decodeEntities(item[1]).trim();
    if (!roleLabel || CREW_ROLES_TO_SKIP.test(roleLabel)) continue;

    const role = CONDUCTOR_ROLE.test(roleLabel) ? "dirigent" : CHORLEADER_ROLE.test(roleLabel) ? "chorleiter" : "solist";

    const namesHtml = item[2];
    for (const nameMatch of namesHtml.matchAll(/<(?:a|span)[^>]*>([^<]+)<\/(?:a|span)>/g)) {
      const name = decodeEntities(nameMatch[1]).replace(/\s+/g, " ").trim();
      if (!name || /^(N\.N\.?|TBA|TBD)$/i.test(name)) continue;
      const type: "person" | "ensemble" = ENSEMBLE_NAME.test(name) ? "ensemble" : "person";
      const key = `${type}:${name.toLocaleLowerCase("de")}`;
      if (seen.has(key)) continue;
      seen.add(key);
      participants.push({ name, profileUrl: null, role: type === "ensemble" ? null : role, type });
    }
  }
  return participants;
}

function decodeEntities(raw: string): string {
  return raw
    .replace(/&shy;/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&auml;/g, "ä").replace(/&ouml;/g, "ö").replace(/&uuml;/g, "ü").replace(/&szlig;/g, "ß")
    .replace(/&Auml;/g, "Ä").replace(/&Ouml;/g, "Ö").replace(/&Uuml;/g, "Ü");
}
