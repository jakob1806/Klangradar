// Prioritätsbasierte Coverbild-Erkennung für Event-Importer-Quellen ohne
// eigenes zuverlässiges Bild-Feld (scrape/rss/ical/api/brso — schema_org-
// Quellen liefern ihr Event.image bereits direkt über RawEvent.imageUrl,
// siehe ingest-source/parsers/schema_org.ts, und werden deshalb in
// ingest-source/write.ts gar nicht erst hierher geleitet).
//
// Reihenfolge exakt wie im Architektur-Auftrag, erste gefundene Quelle
// gewinnt (kein Zusammenführen mehrerer Treffer):
//   1. schema.org Event.image (JSON-LD, falls die Seite trotzdem welches hat)
//   2. og:image
//   3. twitter:image
//   4. Hero-/Bannerbild
//   5. Bild innerhalb des Event-Containers
//
// robots.txt wird respektiert wie bei jedem anderen Fetch eines fremden
// Hosts in diesem Projekt (siehe _shared/robots.ts).

import { isAllowedByRobots, USER_AGENT } from "./robots.ts";
import { extractMetaImages, readHeadHtml } from "./ogImage.ts";
import { extractFirstEventImageFromJsonLd } from "../ingest-source/parsers/schema_org.ts";
import { isLikelyGenericImage } from "./imageValidation.ts";
import { extractStaatsoperProductionImage } from "./staatsoperDetail.ts";
import { extractHeroImageFromMarkdown, extractMarkdownImageCredit, fetchViaReaderProxy } from "./readerProxyImage.ts";

export interface DetectedCoverImage {
  url: string;
  credits: string | null;
  tier: "schema_org" | "og_image" | "twitter_image" | "hero" | "container";
}

// Etwas großzügiger als ogImage.ts's readHeadHtml-Default: die Hero-/
// Container-Stufen müssen ggf. auch Markup unterhalb von </head> sehen
// (Bilder stehen im <body>), ein Event.image im JSON-LD oder og:image im
// <head> wird trotzdem in aller Regel weit vorher gefunden.
const MAX_HTML_BYTES = 500_000;

export async function detectEventCoverImage(pageUrl: string): Promise<DetectedCoverImage | null> {
  if (!(await isAllowedByRobots(pageUrl))) return null;

  let html: string;
  try {
    const res = await fetch(pageUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      // Generischer Rückfall für JEDE Domain, die den normalen Fetch
      // blockiert (Bot-Schutz, 403/503, ...) — vorher nur für staatsoper.de,
      // siehe readerProxyImage.ts für die Begründung. Domain-spezifische
      // Extraktoren bleiben bevorzugt, wo sie existieren.
      const markdown = await fetchViaReaderProxy(pageUrl);
      if (!markdown) return null;
      const hostname = new URL(pageUrl).hostname;
      if (hostname.endsWith("staatsoper.de")) {
        const imageUrl = extractStaatsoperProductionImage(markdown);
        return imageUrl ? { url: imageUrl, credits: "© Bayerische Staatsoper", tier: "hero" } : null;
      }
      const imageUrl = extractHeroImageFromMarkdown(markdown, pageUrl);
      return imageUrl ? { url: imageUrl, credits: extractMarkdownImageCredit(markdown), tier: "hero" } : null;
    }
    html = await readHeadHtml(res, MAX_HTML_BYTES);
  } catch {
    return null;
  }
  if (!html) return null;

  const jsonLdImage = safely(() => extractFirstEventImageFromJsonLd(html));
  if (jsonLdImage && !isLikelyGenericImage(jsonLdImage.url)) {
    return { url: jsonLdImage.url, credits: jsonLdImage.credits, tier: "schema_org" };
  }

  const { ogImage, twitterImage } = safely(() => extractMetaImages(html, pageUrl)) ?? {
    ogImage: null,
    twitterImage: null,
  };
  if (ogImage && !isLikelyGenericImage(ogImage)) {
    return { url: ogImage, credits: extractImageCredits(html, ogImage), tier: "og_image" };
  }
  if (twitterImage && !isLikelyGenericImage(twitterImage)) {
    return { url: twitterImage, credits: extractImageCredits(html, twitterImage), tier: "twitter_image" };
  }

  const hero = safely(() => extractHeroImage(html, pageUrl));
  if (hero && !isLikelyGenericImage(hero)) {
    return { url: hero, credits: extractImageCredits(html, hero), tier: "hero" };
  }

  const container = safely(() => extractContainerImage(html, pageUrl));
  if (container && !isLikelyGenericImage(container)) {
    return { url: container, credits: extractImageCredits(html, container), tier: "container" };
  }

  return null;
}

function safely<T>(fn: () => T): T | null {
  try {
    return fn();
  } catch {
    return null;
  }
}

const IMG_TAG_PATTERN = /<img\b[^>]*>/gi;

function attr(tag: string, name: string): string | null {
  const re = new RegExp(`${name}\\s*=\\s*["']([^"']+)["']`, "i");
  const match = tag.match(re);
  return match ? match[1] : null;
}

function resolveUrl(src: string, pageUrl: string): string | null {
  try {
    return new URL(src, pageUrl).toString();
  } catch {
    return null;
  }
}

/** Sucht ein <img> mit Hero-/Banner-typischen class/id-Attributen — die
 * gängigsten Namensmuster für das große Titelbild oberhalb des eigentlichen
 * Inhalts (WordPress-Themes, generische CMS-Templates). Erstes Vorkommen im
 * Dokument gewinnt (Hero-Bilder stehen praktisch immer weit oben im Markup,
 * vor jedem Event-Container). */
function extractHeroImage(html: string, pageUrl: string): string | null {
  const heroPattern = /\b(hero|banner|jumbotron|teaser|stage|headimage|header-image|titelbild)\b/i;
  for (const match of html.matchAll(IMG_TAG_PATTERN)) {
    const tag = match[0];
    const classAndId = `${attr(tag, "class") ?? ""} ${attr(tag, "id") ?? ""}`;
    if (!heroPattern.test(classAndId)) continue;
    const src = attr(tag, "src") ?? attr(tag, "data-src");
    if (!src) continue;
    const resolved = resolveUrl(src, pageUrl);
    if (resolved) return resolved;
  }
  return null;
}

/** Letzte Stufe der Kaskade: erstes <img> innerhalb eines Containers, der
 * nach Event-Inhalt aussieht (class/id-Namensmuster). Bewusst großzügig (die
 * konkrete Klassenbenennung ist pro Quelle unbekannt) — gefiltert über
 * isLikelyGenericImage() gegen die offensichtlichsten Logo-/Platzhalter-
 * Treffer, genau wie die anderen Stufen oben. */
function extractContainerImage(html: string, pageUrl: string): string | null {
  const containerPattern =
    /<(article|div|section|main)\b[^>]*(?:class|id|itemtype)\s*=\s*["'][^"']*(event|veranstaltung|content|artikel)[^"']*["'][^>]*>/i;
  const containerMatch = containerPattern.exec(html);
  if (!containerMatch) return null;

  const searchFrom = html.slice(containerMatch.index + containerMatch[0].length);
  for (const match of searchFrom.matchAll(IMG_TAG_PATTERN)) {
    const tag = match[0];
    const src = attr(tag, "src") ?? attr(tag, "data-src");
    if (!src) continue;
    const resolved = resolveUrl(src, pageUrl);
    if (!resolved || isLikelyGenericImage(resolved)) continue;
    return resolved;
  }
  return null;
}

const CREDIT_PATTERNS = [
  /©[^<\n]{2,80}/,
  /\bFoto:\s*[^<\n]{2,80}/i,
  /\bPhoto:\s*[^<\n]{2,80}/i,
  /\bPhotographer:?\s*[^<\n]{2,80}/i,
  /\bImage Credit:?\s*[^<\n]{2,80}/i,
  /\bCopyright:?\s*[^<\n]{2,80}/i,
];

/** Best-effort Credit-Extraktion für Stufen ohne eigenes strukturiertes
 * Bild-Metadatum (og:image/twitter:image/Hero/Container — die schema.org-
 * Stufe hat ihre eigene, verlässlichere Extraktion aus dem ImageObject
 * selbst, siehe schema_org.ts). Erst alt/title des gefundenen <img> selbst
 * prüfen, sonst ein Freitext-Scan der ganzen Seite nach den üblichen
 * Copyright-/Credit-Formulierungen. Liefert null statt eines unsicheren
 * Rateergebnisses, wenn nichts passt — ein falscher Credit ist schlimmer
 * als gar keiner. */
function extractImageCredits(html: string, imageUrl: string): string | null {
  for (const match of html.matchAll(IMG_TAG_PATTERN)) {
    const tag = match[0];
    const src = attr(tag, "src") ?? attr(tag, "data-src");
    if (!src) continue;
    // Grober Abgleich statt exaktem URL-Vergleich (imageUrl wurde ggf. schon
    // gegen die Seiten-URL aufgelöst, src im Markup kann noch relativ sein).
    const filename = src.split("/").pop() ?? "";
    if (!filename || !imageUrl.includes(filename)) continue;
    const alt = attr(tag, "alt");
    const title = attr(tag, "title");
    for (const candidate of [alt, title]) {
      if (candidate && CREDIT_PATTERNS.some((p) => p.test(candidate))) {
        return candidate.trim().slice(0, 200);
      }
    }
  }

  for (const pattern of CREDIT_PATTERNS) {
    const match = pattern.exec(html);
    if (match) return match[0].trim().slice(0, 200);
  }

  return null;
}
