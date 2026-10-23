// Erstellt von Claude Code. Werk-Identität für die Programmerkennung.
//
// Nutzerfeedback (Münchner Philharmoniker u. a.): Stücke wurden doppelt und
// falsch angelegt, weil sich ein Wort unterschied – "5. Sinfonie" vs.
// "Sinfonie Nr. 5 cis-Moll" vs. "Symphony No. 5", "Klavierkonzert Nr. 2" vs.
// "Konzert für Klavier und Orchester Nr. 2", Tonart mitten im Titel, Beinamen
// in Anführungszeichen. Der bisherige Vergleich normalisierte nur das
// Titelende.
//
// Identität innerhalb EINES Komponisten, in dieser Rangfolge:
//   1. Werkverzeichnis (op./KV/BWV/D/Hob./WoO/RV/HWV, inkl. "Nr." danach)
//   2. Gattung + Nummer ("sinfonie#5", "klavierkonzert#2")
//   3. bereinigter Titel (ohne Tonart, Beinamen, Besetzungszusätze)
// Zwei Werke verschiedener Komponisten sind nie dasselbe Werk.

export interface WorkIdentity {
  catalog: string | null;
  numbered: string | null;
  normalized: string;
}

const KEY_SIGNATURE =
  /\b(?:in\s+)?[a-h](?:is|es|s)?[-\s](?:dur|moll)\b|\b(?:in\s+)?[a-g](?:\s|-)?(?:flat|sharp)?\s+(?:major|minor)\b/gi;

// Katalog: Kürzel + Zahl, optional "Nr. 3" (Op. 10 Nr. 3). "D" nur vor Zahl
// (sonst "D-Dur"), "K." als KV-Synonym.
const CATALOG =
  /\b(op(?:us)?|bwv|kv|k|hob|woo|rv|hwv|d)\.?\s*((?:[ivx]+[a-z]?:)?\d+[a-z]?)(?:\s*,?\s*(?:nr|no)\.?\s*(\d+))?/i;

const GENRES: [RegExp, string][] = [
  [/\b(?:klavierkonzert|piano\s+concerto|konzert\s+für\s+klavier(?:\s+und\s+orchester)?|concerto\s+for\s+piano)\b/i, "klavierkonzert"],
  [/\b(?:violinkonzert|violin\s+concerto|konzert\s+für\s+violine(?:\s+und\s+orchester)?|concerto\s+for\s+violin)\b/i, "violinkonzert"],
  [/\b(?:cellokonzert|violoncellokonzert|cello\s+concerto|konzert\s+für\s+(?:violon)?cello(?:\s+und\s+orchester)?)\b/i, "cellokonzert"],
  [/\b(?:hornkonzert|horn\s+concerto|konzert\s+für\s+horn(?:\s+und\s+orchester)?)\b/i, "hornkonzert"],
  [/\b(?:klarinettenkonzert|clarinet\s+concerto|konzert\s+für\s+klarinette(?:\s+und\s+orchester)?)\b/i, "klarinettenkonzert"],
  [/\b(?:streichquartett|string\s+quartet)\b/i, "streichquartett"],
  [/\b(?:klaviertrio|piano\s+trio)\b/i, "klaviertrio"],
  [/\b(?:klaviersonate|piano\s+sonata|sonate\s+für\s+klavier)\b/i, "klaviersonate"],
  [/\b(?:violinsonate|violin\s+sonata|sonate\s+für\s+violine(?:\s+und\s+klavier)?)\b/i, "violinsonate"],
  [/\b(?:sinfonie|symphonie|symphony|sinfonia)\b/i, "sinfonie"],
  [/\b(?:messe|mass|missa)\b/i, "messe"],
];

function baseNormalize(title: string): string {
  return title
    .normalize("NFC")
    .toLowerCase()
    .replace(/[„“”"»«‚‘’'`]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

export function catalogKey(title: string, catalogNumber?: string | null): string | null {
  const source = [catalogNumber, title].filter(Boolean).join(" ");
  const m = baseNormalize(source).match(CATALOG);
  if (!m) return null;
  let prefix = m[1].toLowerCase();
  if (prefix === "opus") prefix = "op";
  if (prefix === "k") prefix = "kv";
  return `${prefix} ${m[2]}${m[3] ? ` nr ${m[3]}` : ""}`;
}

export function numberedKey(title: string): string | null {
  const t = baseNormalize(title).replace(KEY_SIGNATURE, " ");
  const genre = GENRES.find(([pattern]) => pattern.test(t))?.[1];
  if (!genre) return null;
  // "Nr. 5" / "No. 5" / "5. Sinfonie" / "Sinfonie 5"
  const number = t.match(/\b(?:nr|no|nummer)\.?\s*(\d+)\b/)?.[1]
    ?? t.match(/\b(\d+)\.\s*(?:\w+\s+){0,2}?(?:sinfonie|symphonie|symphony|klavierkonzert|violinkonzert|cellokonzert|streichquartett|klaviersonate|messe|konzert)/)?.[1]
    ?? t.match(/(?:sinfonie|symphonie|symphony)\s+(\d+)\b/)?.[1];
  return number ? `${genre}#${Number(number)}` : null;
}

export function normalizedWorkTitle(title: string): string {
  return baseNormalize(title)
    .replace(/\([^)]*\)/g, " ") // Beinamen/Zusätze in Klammern
    .replace(KEY_SIGNATURE, " ")
    .replace(CATALOG, " ")
    .replace(/\bfür\s+(?:großes\s+|kleines\s+)?(?:orchester|kammerorchester|streichorchester)\b/g, " ")
    .replace(/\b(?:symphonie|symphony|sinfonia)\b/g, "sinfonie")
    .replace(/\b(?:nr|no)\.?\s*/g, "nr ")
    .replace(/[.,;:–—-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function workIdentity(title: string, catalogNumber?: string | null): WorkIdentity {
  return { catalog: catalogKey(title, catalogNumber), numbered: numberedKey(title), normalized: normalizedWorkTitle(title) };
}

/** Gleiches Werk (Komponist muss vorher übereinstimmen). */
export function sameWork(a: WorkIdentity, b: WorkIdentity): boolean {
  if (a.catalog && b.catalog) return a.catalog === b.catalog;
  if (a.numbered && b.numbered) return a.numbered === b.numbered;
  return a.normalized.length > 0 && a.normalized === b.normalized;
}
