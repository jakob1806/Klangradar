// Volltext-Quelle für Komponisten und Werke ohne eigene offizielle Website
// (Phase 5 der Datenanreicherung) — historische Komponisten und einzelne
// Werke haben naturgemäß keine "offizielle Website" wie Venues/lebende
// Künstler/Ensembles, aber häufig einen Wikipedia-Artikel. Ergänzt
// wikipediaPortrait.ts (das nur Bild + Kurzbeschreibung liefert) um einen
// LÄNGEREN Volltext-Extract für die inhaltliche Anreicherung.
//
// Zweistufig: zuerst Volltextsuche (findet den wahrscheinlichsten
// Artikeltitel zu einer mehrteiligen Suchanfrage wie "Johann Sebastian Bach
// Weihnachtsoratorium"), dann Volltext-Extract dieses Artikels. Deutsche
// Wikipedia zuerst, englische als Fallback. Eine Mehrdeutigkeitsseite wird
// verworfen statt geraten (gleiches Prinzip wie wikipediaPortrait.ts).
//
// Bug (live entdeckt): die erste Fassung nutzte action=opensearch — das ist
// reine PRÄFIX-Suche auf Artikeltitel (für Autovervollständigung gedacht),
// keine Volltextsuche. "Bach Weihnachtsoratorium" fand dadurch NICHTS (der
// Artikel heißt nur "Weihnachtsoratorium (Bach)", fängt also nicht mit
// "Bach" an), obwohl "Weihnachtsoratorium" allein sofort traf. Für
// "Komponist + Werktitel"-Anfragen ist action=query&list=search (echte
// MediaWiki-Volltextsuche) das richtige Werkzeug.

const MAX_CHARS = 6000;

export interface WikipediaExtract {
  text: string;
  pageUrl: string;
  articleTitle: string;
}

async function searchTitle(query: string, lang: "de" | "en"): Promise<string | null> {
  const url = `https://${lang}.wikipedia.org/w/api.php?action=query&format=json&list=search&srlimit=1&srsearch=${
    encodeURIComponent(query)
  }`;
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "KlassikMuenchenBot/1.0 (redaktionelle Recherche)" },
    });
    if (!res.ok) return null;
    const data = await res.json();
    const results = data?.query?.search as Array<{ title?: string }> | undefined;
    return results?.[0]?.title ?? null;
  } catch {
    return null;
  }
}

async function fetchExtract(title: string, lang: "de" | "en"): Promise<WikipediaExtract | null> {
  const url = `https://${lang}.wikipedia.org/w/api.php?action=query&format=json&prop=extracts|info&explaintext=1&inprop=url&titles=${
    encodeURIComponent(title)
  }`;
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "KlassikMuenchenBot/1.0 (redaktionelle Recherche)" },
    });
    if (!res.ok) return null;
    const data = await res.json();
    const pages = data?.query?.pages;
    if (!pages) return null;
    const page = Object.values(pages)[0] as
      | { extract?: string; fullurl?: string; pageid?: number; ns?: number }
      | undefined;
    if (!page || page.pageid === undefined || page.pageid < 0) return null;
    const extract = page.extract?.trim();
    if (!extract) return null;
    // Mehrdeutigkeitsseiten haben typischerweise sehr kurze Extracts ohne
    // Fließtext (nur eine Liste von Links) — ein Mindestmaß an Länge
    // schließt die gröbsten Fälle aus, ohne die HTML-Struktur parsen zu
    // müssen (explaintext liefert reinen Text ohne Markup).
    if (extract.length < 200) return null;
    return {
      text: extract.slice(0, MAX_CHARS),
      pageUrl: page.fullurl ?? `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(title)}`,
      articleTitle: title,
    };
  } catch {
    return null;
  }
}

/** Sucht den wahrscheinlichsten Wikipedia-Artikel zu `query` (erst de, dann
 * en) und liefert dessen Volltext-Extract (bis MAX_CHARS), oder null wenn
 * kein Artikel gefunden wird oder er zu kurz/leer ist. Wirft nie — jeder
 * Fehler wird als "kein Treffer" behandelt. */
export async function fetchWikipediaExtract(query: string): Promise<WikipediaExtract | null> {
  for (const lang of ["de", "en"] as const) {
    const title = await searchTitle(query, lang);
    if (!title) continue;
    const extract = await fetchExtract(title, lang);
    if (extract) return extract;
  }
  return null;
}
