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

async function fetchSummary(title: string, lang: "de" | "en"): Promise<WikipediaSummary | null> {
  const url = `https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`;
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

/** Normalisiert für den Namens-Überlappungs-Check unten: klein, ohne
 * Satzzeichen/Klammerzusätze wie "(Dirigent)". */
function normalizeForOverlap(value: string): string {
  return value.toLowerCase().replace(/\([^)]*\)/g, " ").replace(/[^\p{L}\s]/gu, " ");
}

/** Bewusst konservativ: verlangt, dass ALLE Namensteile (Vor- und Nachname)
 * im gefundenen Artikeltitel vorkommen — ein einzelner überlappender Teil
 * (z. B. nur der Nachname bei einem häufigen Namen) reicht nicht. Das
 * gefundene Bild landet ohnehin immer in der Review-Queue (nie
 * auto-appliziert), dieser Gate ist nur gegen offensichtliche
 * Fehltreffer der Volltextsuche gedacht. */
function titleLikelyMatchesName(name: string, title: string): boolean {
  const nameParts = normalizeForOverlap(name).split(/\s+/).filter((p) => p.length > 1);
  if (nameParts.length === 0) return false;
  const normalizedTitle = normalizeForOverlap(title);
  return nameParts.every((part) => normalizedTitle.includes(part));
}

/** Volltextsuche als Fallback, wenn der direkte Titel-Abruf nichts findet —
 * fängt Fälle wie Wikipedia-Mehrdeutigkeitszusätze ("Hans Müller (Dirigent)")
 * oder leicht abweichende Schreibweisen ab, die ein exakter Titel-Match
 * verpasst. Liefert nur einen Titel zurück, der den Namens-Überlappungs-Gate
 * besteht — sonst null. */
async function searchArticleTitle(name: string, lang: "de" | "en"): Promise<string | null> {
  const url = new URL(`https://${lang}.wikipedia.org/w/api.php`);
  url.searchParams.set("action", "query");
  url.searchParams.set("list", "search");
  url.searchParams.set("srsearch", name);
  url.searchParams.set("srlimit", "3");
  url.searchParams.set("format", "json");
  url.searchParams.set("origin", "*");

  try {
    const res = await fetch(url.toString(), {
      headers: { "User-Agent": "KlassikMuenchenBot/1.0 (redaktionelle Bilderrecherche)" },
    });
    if (!res.ok) return null;
    const data = await res.json();
    const hits = (data?.query?.search ?? []) as Array<{ title?: string }>;
    for (const hit of hits) {
      if (hit.title && titleLikelyMatchesName(name, hit.title)) return hit.title;
    }
    return null;
  } catch {
    return null;
  }
}

/** Sucht den Wikipedia-Artikel zu `name` (erst de, dann en) und liefert
 * dessen Infobox-Bild + Kurzbeschreibung, oder null wenn kein Artikel
 * existiert, es eine Mehrdeutigkeitsseite ist, oder kein Bild hinterlegt
 * ist. Wirft nie — jeder Fehler wird als "kein Treffer" behandelt.
 * Versucht pro Sprache erst den exakten Titel, dann (falls das nichts
 * findet) die Volltextsuche als Fallback — kostet nur einen zusätzlichen
 * Request an dieselbe kostenlose Wikipedia-API, kein neuer Dienst. */
export async function fetchWikipediaPortrait(name: string): Promise<WikipediaPortrait | null> {
  for (const lang of ["de", "en"] as const) {
    let summary = await fetchSummary(name, lang);
    let resolvedTitle = name;
    if (!summary || summary.type === "disambiguation") {
      const found = await searchArticleTitle(name, lang);
      if (!found) continue;
      summary = await fetchSummary(found, lang);
      resolvedTitle = found;
    }
    if (!summary || summary.type === "disambiguation") continue;

    const imageUrl = summary.originalimage?.source ?? summary.thumbnail?.source;
    if (!imageUrl) continue;

    const pageUrl = summary.content_urls?.desktop?.page ??
      `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(resolvedTitle)}`;

    return {
      imageUrl,
      pageUrl,
      description: summary.description ?? summary.extract?.slice(0, 200) ?? null,
    };
  }
  return null;
}
