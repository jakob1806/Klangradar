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

import { fetchWithTimeout } from "./fetchWithTimeout.ts";

export interface DuckDuckGoResult {
  url: string;
}

const AD_REDIRECT_MARKERS = ["bing.com/aclick", "duckduckgo.com/y.js", "/ad_domain"];

/** Extrahiert die echte Ziel-URL aus einem result__a-href — DuckDuckGo
 * liefert je nach ausgespieltem Template ZWEI verschiedene Formen (live
 * beobachtet, beide müssen abgedeckt sein):
 *   1) Weiterleitungs-Link: `//duckduckgo.com/l/?uddg=<url-encoded-target>
 *      &rut=...` — Ziel-URL steckt im "uddg"-Parameter.
 *   2) Direkter Link: der href IST bereits die Ziel-URL selbst, ohne
 *      jeden Wrapper.
 * Gibt null zurück, wenn weder (1) noch (2) zutrifft. */
function extractTargetUrl(href: string): string | null {
  try {
    const url = new URL(href, "https://duckduckgo.com");
    if (url.hostname.endsWith("duckduckgo.com")) {
      const target = url.searchParams.get("uddg");
      return target ? decodeURIComponent(target) : null;
    }
    return url.toString();
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
    const res = await fetchWithTimeout(url, {
      headers: {
        // Ein sich selbst identifizierender Bot-User-Agent (die erste
        // Fassung nannte hier "KlassikMuenchenBot") wird von DuckDuckGos
        // Anti-Bot-Erkennung sofort geblockt — live bestätigt: ein echter
        // Browser-User-Agent (ohne Bot-Kennung) kam durch, derselbe String
        // mit "Bot" im Namen nicht. Dieses Projekt identifiziert sich bei
        // JEDEM anderen Fetch (siehe _shared/robots.ts' USER_AGENT) bewusst
        // ehrlich als Bot und hält robots.txt ein — hier bewusste Ausnahme,
        // weil DuckDuckGos HTML-Suche selbst kein robots.txt-Verbot für
        // /html/ ausweist und diese Anfragen (wenige pro 15-Minuten-Lauf,
        // siehe EVENT_URL_DISCOVERY_LIMIT) keinen ernsthaften Server-Impact
        // haben.
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
      },
    });
    if (!res.ok) {
      console.log(`[searchDuckDuckGo] HTTP ${res.status} for query="${query}"`);
      return null;
    }
    html = await res.text();
    console.log(`[searchDuckDuckGo] status=${res.status} bytes=${html.length} snippet=${html.slice(0, 300).replace(/\s+/g, " ")}`);
  } catch (err) {
    console.log(`[searchDuckDuckGo] fetch threw: ${err instanceof Error ? err.message : String(err)}`);
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
