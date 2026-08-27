// Eine einzige, quellenunabhängige Schutzschicht vor jeder automatischen
// Ensemble-Anlage. Importer, Kandidaten-Auflösung und Qualitätsprüfung müssen
// dieselbe Entscheidung treffen – sonst wird ein Name an einer Stelle
// abgelehnt und über einen anderen Importpfad doch wieder angelegt.

const ENSEMBLE_MARKERS = /(chor|choir|orchester|orchestra|ensemble|philharmoni|philharmonic|sinfoniker|symphoniker|symphony|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)/i;
const NON_ENTITY_TEXT = /\b(ticket(?:verkauf|s)?|abendkasse|vorverkauf|einlass|karten|reservierung|buchung|erhältlich|preis|euro|beginn|veranstalter|weitere informationen|mehr erfahren|jetzt buchen|hier klicken|ausverkauft|zahlen können|zahlen möchten|erleben sie|entscheiden anschließend)\b/i;
const ORGANIZATION_MARKERS = /\b(staatsoper|opernhaus|theater|rundfunk|foundation|stiftung|konzertdirektion|agentur|production|productions|produktionsfirma|veranstaltungsservice|förder(?:kreis|verein)|verein)\b|\be\.?\s*v\.?$/i;
const VENUE_MARKERS = /\b(kirche|basilika|dom|münster|konzerthaus|philharmonie|halle|saal|auditorium)\b/i;
const ROLE_OR_DEPARTMENT_MARKERS = /\b(ballettmeister|choreograph(?:ie)?|choreograf(?:ie)?|statisterie|kinderstatisterie|kostüm(?:bild)?|bühnenbild|regie|dramaturg(?:ie)?)\b/i;
const PLACEHOLDER = /(?:^|\s|[(*])(?:n\.?\s*n\.?|tba|tbd|unbekannt|unknown|noch offen)(?:$|\s|[),.;])/i;
const PERSON_CONNECTORS = new Set(["de", "del", "della", "di", "da", "van", "von", "zu", "zur", "la", "le"]);

export type EnsembleNameClassification =
  | "ensemble"
  | "person"
  | "multiple_people"
  | "organization"
  | "venue"
  | "role_or_department"
  | "generic"
  | "text"
  | "unknown";

export interface EnsembleNameAssessment {
  safe: boolean;
  cleaned: string;
  reason: string | null;
  classification: EnsembleNameClassification;
}

function decodeHtmlEntities(value: string): string {
  const named: Record<string, string> = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: '"',
  };
  return value.replace(/&(#(?:x[0-9a-f]+|\d+)|[a-z]+);/gi, (match, entity: string) => {
    if (entity[0] !== "#") return named[entity.toLowerCase()] ?? match;
    const hex = entity[1]?.toLowerCase() === "x";
    const codePoint = Number.parseInt(entity.slice(hex ? 2 : 1), hex ? 16 : 10);
    return Number.isFinite(codePoint) && codePoint > 0 ? String.fromCodePoint(codePoint) : match;
  });
}

export function cleanEntityName(rawName: string): string {
  return decodeHtmlEntities(rawName)
    .replace(/<[^>]+>/g, " ")
    .replace(/[*_~`]+/g, "")
    .replace(/[\u00a0\u2007\u202f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizedToken(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("de")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

export const GENERIC_ENSEMBLE_NAMES = new Set([
  "ballett",
  "blechblaser",
  "chor",
  "chore",
  "ensemble",
  "extrachor",
  "kinderchor",
  "operchor",
  "opernstudio",
  "orchester",
  "quatuor",
  "quartett",
  "statisterie",
  "kinderstatisterie",
  "zusatzchor",
]);

export function isGenericEnsembleName(rawName: string): boolean {
  return GENERIC_ENSEMBLE_NAMES.has(normalizedToken(cleanEntityName(rawName)));
}

function looksLikePersonName(value: string): boolean {
  const words = value.split(/\s+/).filter(Boolean);
  return words.length >= 2 && words.length <= 5 && words.every((word) =>
    PERSON_CONNECTORS.has(word.toLocaleLowerCase("de")) ||
    /^(?:[A-ZÄÖÜ][\p{L}'’.-]+|[A-ZÄÖÜ]\.)$/u.test(word)
  );
}

function looksLikeMultiplePeople(value: string): boolean {
  const parts = value.split(/\s*(?:,|;|\s+und\s+)\s*/i).filter(Boolean);
  return parts.length >= 2 && parts.length <= 5 && parts.every(looksLikePersonName);
}

/** Harte Schranke vor jeder automatischen Ensemble-Anlage. Die Klassifikation
 * ist absichtlich konservativ: Nur ein echtes Ensemble-Signal wird automatisch
 * akzeptiert; Personen, Institutionen, Rollen, Fließtext und Gattungswörter
 * werden niemals als Ensemble angelegt. */
export function assessEnsembleName(rawName: string): EnsembleNameAssessment {
  const cleaned = cleanEntityName(rawName);
  const words = cleaned.split(/\s+/).filter(Boolean);
  const result = (
    safe: boolean,
    reason: string | null,
    classification: EnsembleNameClassification,
  ): EnsembleNameAssessment => ({ safe, cleaned, reason, classification });

  if (cleaned.length < 3) return result(false, "zu kurz", "unknown");
  if (PLACEHOLDER.test(` ${cleaned} `)) return result(false, "enthält einen Platzhalter oder eine unbesetzte Rolle", "role_or_department");
  if (isGenericEnsembleName(cleaned)) return result(false, "bloßes Gattungswort statt eines konkreten Namens", "generic");
  if (NON_ENTITY_TEXT.test(cleaned) || /&(?:nbsp|amp|quot|apos);/i.test(cleaned)) {
    return result(false, "Ticket-, Werbe- oder Informationstext", "text");
  }
  if (looksLikeMultiplePeople(cleaned)) return result(false, "enthält mehrere Personennamen", "multiple_people");
  if (ROLE_OR_DEPARTMENT_MARKERS.test(cleaned)) {
    return result(false, "Rollen- oder Abteilungsbezeichnung statt Ensemble", "role_or_department");
  }
  if (ORGANIZATION_MARKERS.test(cleaned) && !ENSEMBLE_MARKERS.test(cleaned)) {
    return result(false, "Institution oder Veranstalter statt Ensemble", "organization");
  }
  if (VENUE_MARKERS.test(cleaned) && !ENSEMBLE_MARKERS.test(cleaned)) return result(false, "Spielstätte statt Ensemble", "venue");

  // Explizite Gruppensignale haben Vorrang vor der Personenerkennung. Dadurch
  // bleiben Eigennamen wie „Belcea Quartet“, „hr-Bigband“ und die offizielle
  // Kleinschreibung „via-nova-chor München“ gültig.
  if (ENSEMBLE_MARKERS.test(cleaned)) {
    if (words.length > 12 || /[.!?;:]$/.test(cleaned)) return result(false, "wahrscheinlich Fließtext", "text");
    return result(true, null, "ensemble");
  }
  if (looksLikePersonName(cleaned)) return result(false, "sieht wie ein Personenname aus", "person");
  if (/^[a-zäöüß]/.test(cleaned) || words.length > 10 || /[.!?;:]$/.test(cleaned)) {
    return result(false, "wahrscheinlich Fließtext", "text");
  }
  if (/^[A-ZÄÖÜ0-9]{2,8}$/.test(cleaned) || words.length === 1) {
    return result(false, "uneindeutiger Gruppenname", "unknown");
  }
  return result(false, "kein eindeutiges Ensemble-Signal", "unknown");
}

export function isObviousNonEnsembleText(rawName: string): boolean {
  return ["multiple_people", "organization", "venue", "role_or_department", "generic", "text"]
    .includes(assessEnsembleName(rawName).classification);
}
