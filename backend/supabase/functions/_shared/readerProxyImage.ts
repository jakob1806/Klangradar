// Generischer Reader-Proxy-Fallback für Websites, die einen normalen Fetch
// blockieren (Bot-Schutz, 403/503, ...) — vorher war dieser Rückfall exakt
// EINE Domain (staatsoper.de) hart codiert (siehe staatsoperDetail.ts).
// Nutzeranfrage: "ich brauche noch viel mehr websiten, wie z.b. bei der
// staatsoper, die bei der bilder recherche weiterarbeiten" — statt für jede
// weitere Website eine eigene Sonderbehandlung zu schreiben, greift dieser
// generische Rückfall jetzt für JEDE Domain, bei der der normale Fetch
// fehlschlägt: https://r.jina.ai/<url> rendert die Seite serverseitig und
// liefert sie als Markdown zurück, aus dem hier ein plausibles Titelbild
// extrahiert wird. Domain-spezifische Extraktoren (aktuell nur Staatsoper)
// bleiben bevorzugt, wo sie existieren — die Site-Struktur ist dort genauer
// bekannt (Abschnittsmarker, Partner-Logo-Ausschlussliste etc.).

import { USER_AGENT } from "./robots.ts";
import { isLikelyGenericImage } from "./imageValidation.ts";
import { fetchWithTimeout } from "./fetchWithTimeout.ts";

// Etwas großzügiger als der Standard-12s-Timeout: r.jina.ai rendert die
// Zielseite serverseitig (inkl. JS), das dauert grundsätzlich länger als
// ein einfacher Fetch — aber immer noch begrenzt, siehe fetchWithTimeout.ts
// zur Begründung, warum hier überhaupt ein Timeout stehen muss.
const READER_PROXY_TIMEOUT_MS = 20_000;

export async function fetchViaReaderProxy(pageUrl: string): Promise<string | null> {
  try {
    const reader = await fetchWithTimeout(
      `https://r.jina.ai/${pageUrl}`,
      { headers: { "User-Agent": USER_AGENT } },
      READER_PROXY_TIMEOUT_MS,
    );
    if (!reader.ok) return null;
    return await reader.text();
  } catch {
    return null;
  }
}

// URL-Teil bewusst nicht auf https?:// beschränkt — r.jina.ai liefert zwar
// praktisch immer bereits absolute URLs, ein relativer Pfad wird trotzdem
// unten über new URL(rawUrl, pageUrl) korrekt gegen die Seiten-URL aufgelöst.
const MARKDOWN_IMAGE_PATTERN = /!\[([^\]]*)\]\(([^)\s]+)\)/g;

// Nur der Anfang des Dokuments wird geprüft — Site-Logo/Navigation stehen in
// r.jina.ai-Markdown praktisch immer vor dem eigentlichen Inhalt, spätere
// Empfehlungs-/Footer-Bilder sollen nicht versehentlich als Titelbild
// gewählt werden (gleiche Grundidee wie die "vor den Stück-Details"-Grenze
// in staatsoperDetail.ts, nur ohne domain-spezifischen Abschnittsmarker).
const SEARCH_WINDOW = 20_000;

/** Generische Ersatz-Heuristik für Domains ohne eigenen Markdown-Extraktor:
 * erstes Bild aus dem Markdown, das nicht offensichtlich Logo/Icon/
 * Platzhalter ist. Liefert null statt eines unsicheren Treffers, wenn kein
 * plausibles Bild gefunden wird. */
export function extractHeroImageFromMarkdown(markdown: string, pageUrl: string): string | null {
  const window = markdown.slice(0, SEARCH_WINDOW);
  for (const match of window.matchAll(MARKDOWN_IMAGE_PATTERN)) {
    const [, alt, rawUrl] = match;
    if (/\b(logo|icon|avatar|favicon|sprite)\b/i.test(alt)) continue;
    let resolved: string;
    try {
      resolved = new URL(rawUrl, pageUrl).toString();
    } catch {
      continue;
    }
    if (isLikelyGenericImage(resolved)) continue;
    if (/\.svg(?:$|\?)/i.test(resolved)) continue;
    return resolved;
  }
  return null;
}

const CREDIT_PATTERNS = [
  /©[^\n]{2,80}/,
  /\bFoto:\s*[^\n]{2,80}/i,
  /\bPhoto:\s*[^\n]{2,80}/i,
  /\bPhotographer:?\s*[^\n]{2,80}/i,
  /\bCopyright:?\s*[^\n]{2,80}/i,
];

/** Best-effort Credit-Extraktion aus dem Markdown-Freitext — liefert null
 * statt eines unsicheren Rateergebnisses, wenn kein Copyright-/Credit-Text
 * gefunden wird (gleiche Vorsicht wie extractImageCredits in
 * coverImageDetection.ts). */
export function extractMarkdownImageCredit(markdown: string): string | null {
  for (const pattern of CREDIT_PATTERNS) {
    const match = pattern.exec(markdown);
    if (match) return match[0].trim().slice(0, 200);
  }
  return null;
}

const MARKDOWN_LINK_OR_IMAGE_PATTERN = /(!)?\[([^\]]*)\]\(([^)\s]+)\)/g;

/** Baut aus r.jina.ai-Markdown ein minimales synthetisches HTML-Dokument
 * (nur <img>- und <a>-Tags, in Dokumentreihenfolge) — dadurch kann eine
 * blockierte Seite die BEREITS BESTEHENDE HTML-Kandidaten-/Scoring-Pipeline
 * in officialSiteImageSearch.ts unverändert weiterverwenden (Bildkandidaten
 * per <img alt/src>, Unterseiten-Erkennung per <a href>), statt eine zweite,
 * parallele Markdown-Auswertung pflegen zu müssen. */
export function markdownToSyntheticHtml(markdown: string, pageUrl: string): string {
  let html = "";
  for (const match of markdown.matchAll(MARKDOWN_LINK_OR_IMAGE_PATTERN)) {
    const [, isImage, text, rawUrl] = match;
    let resolved: string;
    try {
      resolved = new URL(rawUrl, pageUrl).toString();
    } catch {
      continue;
    }
    const safeText = text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
    html += isImage ? `<img src="${resolved}" alt="${safeText}">\n` : `<a href="${resolved}">${safeText}</a>\n`;
  }
  return html;
}
