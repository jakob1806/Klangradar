// Kleine Hilfsfunktion fuer die Bildersuche (Wikipedia/Wikidata/Wikimedia
// Commons): manche Namen sind in unserer DB mit Akzenten/diakritischen
// Zeichen erfasst, waehrend der zugehoerige Wikipedia-/Wikidata-Titel die
// unakzentuierte Schreibweise nutzt (oder umgekehrt) -- z. B. "Fazil Say"
// mit/ohne Sonderzeichen. Ein einzelner exakter/Volltext-Suchversuch
// verpasst das dann. Kostet nur einen zusaetzlichen (kostenlosen)
// API-Aufruf, und nur, wenn der Name ueberhaupt diakritische Zeichen
// enthaelt.

const COMBINING_DIACRITICS_PATTERN = new RegExp("[\\u0300-\\u036f]", "g");

export function stripDiacritics(value: string): string {
  return value.normalize("NFKD").replace(COMBINING_DIACRITICS_PATTERN, "");
}

/** Liefert [name], wenn der Name keine diakritischen Zeichen enthaelt
 * (haeufigster Fall -- kein zusaetzlicher Suchversuch noetig), sonst
 * [name, unakzentuierte Variante]. */
export function nameSearchVariants(name: string): string[] {
  const stripped = stripDiacritics(name);
  return stripped !== name ? [name, stripped] : [name];
}
