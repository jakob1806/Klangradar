// Kostenlose Websuche ohne API-Key als Ersatz für Tavily — auf
// Nutzerwunsch: das Tavily-Gratiskontingent (_shared/tavily.ts) war
// ausgeschöpft, ein kostenpflichtiges Upgrade war ausdrücklich nicht
// gewollt. DuckDuckGos HTML-Endpunkt (html.duckduckgo.com/html/) braucht
// keinen API-Key und keine Anmeldung — im Gegenzug ist es HTML-Scraping
// statt einer stabilen JSON-API: fragiler gegenüber Markup-Änderungen,
// daher bewusst konservativ geparst (nur die href-Extraktion, kein
// Snippet-Text). Für das hier genutzte Volumen (wenige Anfragen pro
// 15-Minuten-Lauf, siehe EVENT_URL_DISCOVERY_LIMIT in enrich-entity-
// images/index.ts) unproblematisch.

export interface DuckDuckGoResult {
  url: string;
}

const AD_REDIRECT_MARKERS = ["bing.com/aclick", "duckduckgo.com/y.js", "/ad_domain"];

/** Extrahiert die echte Ziel-URL aus DuckDuckGos Weiterleitungs-Link
 * (`//duckduckgo.com/l/?uddg=<url-encoded-target>&rut=...`). Gibt null
 * zurück, wenn kein "uddg"-Parameter vorhanden oder die Dekodierung
 * fehlschlägt. */
function extractTargetUrl(redirectHref: string): string | null {
  try {
    const url = new URL(redirectHref, "https://duckduckgo.com");
    const target = url.searchParams.get("uddg");
    return target ? decodeURIComponent(target) : null;
  } catch {
    return null;
  }
}

/** Sucht `query` über DuckDuckGos HTML-Oberfläche und liefert die
 * organischen Ergebnis-URLs (Werbe-/Tracking-Weiterleitungen werden
 * herausgefiltert), oder null bei jedem Fetch-/Parse-Fehler — Aufrufer
 * behandeln null wie "keine Anreicherung möglich", nie ein Werfen. */
export async function searchDuckDuckGo(query: string, maxResults = 3): Promise<DuckDuckGoResult[] | null> {
  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
  let html: string;
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; KlassikMuenchenBot/1.0; redaktionelle Recherche)",
      },
    });
    if (!res.ok) return null;
    html = await res.text();
  } catch {
    return null;
  }

  const results: DuckDuckGoResult[] = [];
  const linkPattern = /<a[^>]*class="result__a"[^>]*href="([^"]*)"/g;
  for (const match of html.matchAll(linkPattern)) {
    const rawHref = match[1].replace(/&amp;/g, "&");
    const targetUrl = extractTargetUrl(rawHref);
    if (!targetUrl) continue;
    if (AD_REDIRECT_MARKERS.some((marker) => targetUrl.includes(marker))) continue;
    results.push({ url: targetUrl });
    if (results.length >= maxResults) break;
  }

  return results;
}
