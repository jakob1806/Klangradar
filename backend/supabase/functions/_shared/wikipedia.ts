// Ersatz für die DuckDuckGo-HTML-Suche als Quelle für Biografien/
// Beschreibungen — live festgestellt (siehe bioResearch.ts): DuckDuckGos
// HTML-Endpunkt liefert von Supabase-Edge-Function-IPs aus KEINE echten
// Ergebnisse mehr, sondern eine Anti-Bot-Challenge-Seite (HTTP 202,
// Redirect-Skelett ohne Trefferliste) — vermutlich eine Cloud-IP-Sperre,
// unabhängig vom User-Agent. Betrifft vermutlich auch die andere
// gemeldete Häng-/Timeout-Situation bei der automatischen Bildersuche.
//
// Wikipedias REST-/Action-API ist eine stabile, dokumentierte JSON-API
// ohne Anti-Bot-Schutz für maßvolle Nutzung (kein Scraping, kein API-Key
// nötig) — und für klassische Musik (Komponist:innen, Orchester,
// Konzertsäle) inhaltlich ohnehin oft die bessere Quelle als eine
// allgemeine Websuche.

const USER_AGENT = "KlassikMuenchenBot/1.0 (https://klassik-muenchen.de; Kontakt siehe Impressum)";

export interface WikipediaHit {
  title: string;
  extract: string;
  url: string;
}

/** Sucht `query` in der deutschen Wikipedia und liefert den Volltext-
 * Extrakt (Klartext, keine Wiki-Syntax) des besten Treffers — oder null,
 * wenn nichts gefunden wurde oder ein Netzwerkfehler auftrat. Ein einziger
 * kombinierter API-Aufruf (generator=search + prop=extracts) statt erst
 * suchen, dann separat abrufen. */
export async function searchWikipediaExtract(query: string, lang = "de"): Promise<WikipediaHit | null> {
  const url =
    `https://${lang}.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=` +
    `${encodeURIComponent(query)}&gsrlimit=1&prop=extracts&exintro=1&explaintext=1&format=json&origin=*`;

  let json: unknown;
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return null;
    json = await res.json();
  } catch {
    return null;
  }

  const pages = (json as { query?: { pages?: Record<string, { title?: string; extract?: string }> } })?.query?.pages;
  if (!pages) return null;
  const page = Object.values(pages)[0];
  if (!page?.extract || !page.title) return null;

  return {
    title: page.title,
    extract: page.extract.trim(),
    url: `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(page.title.replace(/ /g, "_"))}`,
  };
}
