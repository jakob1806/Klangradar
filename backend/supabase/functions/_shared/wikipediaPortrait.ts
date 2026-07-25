// Präziserer Ersatz für die blinde Wikimedia-Commons-Namensvolltextsuche
// bei Personen — auf Nutzerfeedback: Commons' Volltextsuche über ALLE
// Dateien hinweg produzierte bei Personen zu viele falsche Treffer durch
// Namensgleichheiten (z. B. "Lazarova"). Wikipedias eigene Summary-API
// dagegen verlangt einen (nahezu) exakten Artikeltitel — kein
// Volltext-Ranking über tausende Dateien, sondern direkter Artikelabruf.
// Das ist speziell für bekannte historische Komponisten (Bach, Mozart,
// Beethoven, Brahms, Mahler, ...) sehr zuverlässig: eindeutiger Titel,
// EIN kuratiertes Infobox-Bild pro Artikel, plus eine Kurzbeschreibung
// ("deutscher Komponist"), die sich als zusätzliche Plausibilitätsprüfung
// nutzen lässt.
//
// Deutsche Wikipedia zuerst (unsere Zielgruppe/Sprache), englische als
// Fallback für international bekanntere Namen ohne deutschen Artikel.
// Ein "disambiguation"-Seitentyp (Mehrdeutigkeits-Übersicht statt eines
// echten Artikels) wird explizit verworfen statt geraten — z. B. würde
// "Fazil Say" als Titel eindeutig sein, ein häufigerer Name aber nicht.

export interface WikipediaPortrait {
  imageUrl: string;
  pageUrl: string;
  description: string | null;
}

interface WikipediaSummary {
  type?: string;
  description?: string;
  extract?: string;
  thumbnail?: { source?: string };
  originalimage?: { source?: string };
  content_urls?: { desktop?: { page?: string } };
}

async function fetchSummary(name: string, lang: "de" | "en"): Promise<WikipediaSummary | null> {
  const url = `https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(name)}`;
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": "KlassikMuenchenBot/1.0 (redaktionelle Bilderrecherche)",
        Accept: "application/json",
      },
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

/** Sucht den Wikipedia-Artikel zu `name` (erst de, dann en) und liefert
 * dessen Infobox-Bild + Kurzbeschreibung, oder null wenn kein Artikel
 * existiert, es eine Mehrdeutigkeitsseite ist, oder kein Bild hinterlegt
 * ist. Wirft nie — jeder Fehler wird als "kein Treffer" behandelt. */
export async function fetchWikipediaPortrait(name: string): Promise<WikipediaPortrait | null> {
  for (const lang of ["de", "en"] as const) {
    const summary = await fetchSummary(name, lang);
    if (!summary) continue;
    if (summary.type === "disambiguation") continue;

    const imageUrl = summary.originalimage?.source ?? summary.thumbnail?.source;
    if (!imageUrl) continue;

    const pageUrl = summary.content_urls?.desktop?.page ??
      `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(name)}`;

    return {
      imageUrl,
      pageUrl,
      description: summary.description ?? summary.extract?.slice(0, 200) ?? null,
    };
  }
  return null;
}
