// Extrahiert das Open-Graph-/Twitter-Card-Bild einer beliebigen Event-
// Webseite — meistens genau das Bild, das die Veranstaltung selbst auf
// ihrer eigenen Quellseite bewirbt, und damit ein deutlich treffenderes
// Titelbild als ein generisches Venue-Foto (siehe enrich-entity-images:
// Venue-Foto ist dort bewusst nur der allerletzte Rückfall, wenn auch das
// hier nichts findet). robots.txt wird respektiert wie bei jedem anderen
// Fetch eines fremden Hosts in diesem Projekt (siehe _shared/robots.ts).

import { isAllowedByRobots, USER_AGENT } from "./robots.ts";

const META_TAG_PATTERN = /<meta\s+[^>]*>/gi;

function extractAttr(tag: string, attr: string): string | null {
  const re = new RegExp(`${attr}\\s*=\\s*["']([^"']+)["']`, "i");
  const match = tag.match(re);
  return match ? match[1] : null;
}

/** Sucht og:image (bevorzugt) oder twitter:image im <head> von `pageUrl`.
 * Gibt null bei robots.txt-Sperre, jedem Fetch-/Parse-Fehler oder fehlendem
 * Tag zurück — Aufrufer behandeln null als "kein Bild auf dieser Seite
 * gefunden", nie als Fehler. Liest nur die ersten ~200 KB (das <head>
 * einer normalen Event-Seite liegt weit darunter), um bei sehr großen
 * Seiten nicht den kompletten Body laden zu müssen. */
export async function extractOgImage(pageUrl: string): Promise<string | null> {
  if (!(await isAllowedByRobots(pageUrl))) return null;

  let res: Response;
  try {
    res = await fetch(pageUrl, { headers: { "User-Agent": USER_AGENT } });
  } catch {
    return null;
  }
  if (!res.ok || !res.body) return null;

  let html: string;
  try {
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let text = "";
    const maxBytes = 200_000;
    let read = 0;
    while (read < maxBytes) {
      const { done, value } = await reader.read();
      if (done) break;
      read += value.byteLength;
      text += decoder.decode(value, { stream: true });
      if (/<\/head>/i.test(text)) break;
    }
    await reader.cancel().catch(() => {});
    html = text;
  } catch {
    return null;
  }

  let ogImage: string | null = null;
  let twitterImage: string | null = null;
  for (const tagMatch of html.matchAll(META_TAG_PATTERN)) {
    const tag = tagMatch[0];
    const property = extractAttr(tag, "property") ?? extractAttr(tag, "name");
    if (!property) continue;
    const content = extractAttr(tag, "content");
    if (!content) continue;
    if (property.toLowerCase() === "og:image" && !ogImage) ogImage = content;
    if (property.toLowerCase() === "twitter:image" && !twitterImage) twitterImage = content;
  }

  const found = ogImage ?? twitterImage;
  if (!found) return null;
  try {
    return new URL(found, pageUrl).toString();
  } catch {
    return null;
  }
}
