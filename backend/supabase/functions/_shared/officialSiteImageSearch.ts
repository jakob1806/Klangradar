// Bildsuche über die offizielle Website einer Entität (Person/Ensemble/
// Venue/Festival/Veranstalter) — Ergänzung zur bisherigen Wikipedia/
// Wikidata/Commons-Suche, die laut Nutzerfeedback "so ungenau ist und oft
// keine Bilder hat". Durchsucht die Startseite plus bis zu 9 wahrscheinliche
// Unterseiten (Presse/Über-uns/Team/Kontakt), sammelt Bildkandidaten aus
// mehreren Quellen und bewertet jeden Kandidaten mit einer reinen,
// unabhängig testbaren Scoring-Funktion (siehe scoreCandidate unten und
// officialSiteImageSearch.test.ts).
//
// Bewusste Abgrenzung zu bestehenden Modulen (keine Parallelstruktur):
// - coverImageDetection.ts bleibt unverändert — das ist die EVENT-
//   spezifische Kaskade für ingest-source/enrich-entity-images und
//   produktionskritisch. Dieses Modul hier ist ENTITÄTS-spezifisch
//   (Personen-/Gebäude-/Ensemblefotos, nicht "das Bild dieser
//   Veranstaltung") und hat andere Filterregeln (z.B. Logos ausschließen
//   statt zu bevorzugen).
// - subpageDiscovery.ts bleibt unverändert (max. 2 Unterseiten, eigener
//   Fetch pro Aufruf) — dieses Modul braucht eine echte Tiefe-2-BFS mit
//   bis zu 10 Seiten insgesamt und wiederverwendet das schon geladene
//   HTML, statt jede Unterseite einzeln nachzuladen.
// - ogImage.ts (extractMetaImages) wird direkt wiederverwendet, keine
//   eigene og:image-Extraktion.
//
// Sicherheits-/Robustheitsgarantien (siehe auch imageValidation.ts):
// - isPublicImageUrl() (SSRF-Schutz: kein localhost/private IPs/
//   Metadaten-Endpunkte/file://) wird für JEDE Seiten- und Bild-URL vor
//   jedem Fetch geprüft, auch nach jedem Redirect-Hop erneut.
// - Timeout + begrenzte Redirect-Kette + Byte-Obergrenze pro Seite.
// - Nur text/html-Antworten werden als Seite gelesen.
// - Kein einzelner Fehlschlag (eine Unterseite nicht erreichbar, kaputtes
//   JSON-LD, ein einzelner Kandidat ohne gültige URL) bricht den Lauf ab —
//   die äußere Funktion wirft nie, siehe Kommentar bei
//   searchOfficialSiteForImages().

import { isAllowedByRobots, USER_AGENT } from "./robots.ts";
import { extractMetaImages } from "./ogImage.ts";
import { isLikelyGenericImage, isPublicImageUrl } from "./imageValidation.ts";

const MAX_PAGES = 10;
const MAX_DEPTH = 2;
const PAGE_TIMEOUT_MS = 12_000;
const MAX_HTML_BYTES = 800_000;
// Grobe Obergrenze für die Warteschlange selbst (nicht nur für besuchte
// Seiten) — verhindert, dass eine Seite mit hunderten passenden Linktexten
// die Warteschlange unnötig aufbläht, bevor MAX_PAGES überhaupt greift.
const MAX_QUEUE_SIZE = MAX_PAGES * 4;

const SUBPAGE_KEYWORD_PATTERN =
  /presse|press|media|medien|about|über-?uns|ueber-?uns|kontakt|contact|team|geschichte|history|profil|portrait|ensemble|orchester|biografie|biography/i;

const A_TAG_PATTERN = /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a\s*>/gi;
const IMG_TAG_PATTERN = /<img\b[^>]*>/gi;
const IMAGE_EXT_PATTERN = /\.(jpe?g|png|webp|avif)(?:[?#]|$)/i;
const HERO_PATTERN = /\b(hero|banner|jumbotron|teaser|stage|headimage|header-image|titelbild|portrait|profile|foto|photo)\b/i;
const DECORATIVE_PATTERN =
  /icon|sprite|spacer|pixel|1x1|tracking|cookie|social[-_]?icon|avatar[-_]?placeholder|favicon|badge|payment|flag[-_]|arrow[-_]|chevron|captcha/i;

type CandidateSource =
  | "json_ld"
  | "og_image"
  | "twitter_image"
  | "hero"
  | "content"
  | "direct_link";

export interface RawCandidate {
  url: string;
  pageUrl: string;
  source: CandidateSource;
  isPressPage: boolean;
  altText: string | null;
  widthHint: number | null;
  heightHint: number | null;
  /** Position unter den <img>-Tags im Dokument (0 = zuerst) — nur für
   * "hero"/"content" sinnvoll ermittelt, sonst 99 (kein Bonus). */
  positionIndex: number;
  /** true, wenn der Kandidat aus dem "logo"-Feld strukturierter Daten
   * stammt statt aus "image"/"photo"/"thumbnailUrl" — für Personen-/
   * Gebäudefotos meist kein brauchbarer Treffer, siehe scoreCandidate(). */
  isLogoField?: boolean;
}

export interface CrawledImageCandidate {
  url: string;
  pageUrl: string;
  source: CandidateSource;
  altText: string | null;
  score: number;
  confidence: "high" | "medium" | "low";
  reasons: string[];
}

export interface OfficialSiteCrawlResult {
  candidates: CrawledImageCandidate[];
  pagesVisited: string[];
  errors: string[];
}

/** Reine Bewertungsfunktion ohne jeden Netzwerkzugriff — unabhängig testbar,
 * siehe officialSiteImageSearch.test.ts. Gewichte sind bewusst additiv/
 * subtraktiv statt eines ML-Modells: nachvollziehbar für die Redaktion
 * (jede Zahl hat einen Grund in `reasons`) und ohne Trainingsdaten sofort
 * einsetzbar. Schwellenwerte (6/3) wurden so gewählt, dass ein einzelnes
 * starkes Signal (z.B. schema.org-Bild auf der Presseseite mit Namenstreffer)
 * allein schon "high" erreicht, ein einzelnes schwaches Signal (z.B. nur
 * "irgendein Bild im Content") bei "low" bleibt. */
export function scoreCandidate(
  candidate: {
    url: string;
    source: CandidateSource;
    isPressPage: boolean;
    altText: string | null;
    widthHint: number | null;
    heightHint: number | null;
    positionIndex: number;
    isLogoField?: boolean;
  },
  context: { entityName: string; siteHost: string },
): { score: number; confidence: "high" | "medium" | "low"; reasons: string[] } {
  let score = 0;
  const reasons: string[] = [];

  let imageHost: string | null = null;
  try {
    imageHost = new URL(candidate.url).host;
  } catch {
    // ungültige URL wird schon vor dem Scoring aussortiert, hier nur defensiv
  }
  if (imageHost && registrableDomain(imageHost) === registrableDomain(context.siteHost)) {
    score += 2;
    reasons.push("Bild liegt auf der offiziellen Domain der Entität.");
  } else if (imageHost) {
    score += 0.5;
    reasons.push("Bild liegt auf einer externen Domain (z.B. CDN) der offiziellen Seite.");
  }

  if (candidate.isPressPage) {
    score += 2;
    reasons.push("Gefunden auf einer Presse-/Über-uns-/Team-Seite.");
  }

  switch (candidate.source) {
    case "json_ld":
      score += 2.5;
      reasons.push("Aus strukturierten Daten (schema.org Person/Organization/Place) der Seite.");
      break;
    case "og_image":
      score += 2;
      reasons.push("Als og:image der Seite ausgezeichnet.");
      break;
    case "twitter_image":
      score += 1.5;
      reasons.push("Als twitter:image der Seite ausgezeichnet.");
      break;
    case "hero":
      score += 1;
      reasons.push("Großes Titel-/Headerbild der Seite.");
      break;
    case "content":
      score += 0.5;
      reasons.push("Inhaltsbild im Seitentext.");
      break;
    case "direct_link":
      score += 0.5;
      reasons.push("Direkter Bilddatei-Link (z.B. Pressefoto-Download).");
      break;
  }

  if (candidate.altText && nameAppearsIn(context.entityName, candidate.altText)) {
    score += 2;
    reasons.push("Alt-Text enthält den Namen der Entität.");
  }
  if (nameAppearsIn(context.entityName, candidate.url)) {
    score += 1.5;
    reasons.push("Dateiname enthält den Namen der Entität.");
  }

  if (candidate.widthHint !== null) {
    if (candidate.widthHint >= 800) {
      score += 1.5;
      reasons.push("Im Markup erkennbar hohe Auflösung.");
    } else if (candidate.widthHint >= 640) {
      score += 0.5;
      reasons.push("Im Markup erkennbar ausreichende Auflösung.");
    } else if (candidate.widthHint < 400) {
      score -= 2;
      reasons.push("Im Markup erkennbar niedrige Auflösung (endgültige Prüfung erfolgt beim Download).");
    }
  }

  if (candidate.positionIndex <= 2) {
    score += 0.5;
    reasons.push("Prominente Position auf der Seite.");
  }

  if (candidate.isLogoField) {
    score -= 4;
    reasons.push("Stammt aus einem Logo-Feld der strukturierten Daten, vermutlich kein Personen-/Gebäudefoto.");
  }

  score = Math.round(score * 10) / 10;
  const confidence: "high" | "medium" | "low" = score >= 6 ? "high" : score >= 3 ? "medium" : "low";
  return { score, confidence, reasons };
}

/** Grobe Registrable-Domain-Heuristik (letzte zwei Labels) — deckt die
 * ganz überwiegende Mehrheit der hier vorkommenden Domains (.de/.com/.org)
 * korrekt ab, scheitert aber an Public-Suffix-Ausnahmen wie "co.uk". Für
 * eine reine Bonuspunkte-Heuristik (kein Sicherheitsmechanismus — die
 * SSRF-Prüfung läuft komplett unabhängig über isPublicImageUrl) ist das
 * bewusst ausreichend statt eine vollständige Public-Suffix-Liste
 * einzubinden. */
function registrableDomain(host: string): string {
  const parts = host.toLowerCase().split(".");
  return parts.slice(-2).join(".");
}

function normalizeForMatch(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Mindestens die Hälfte der signifikanten Namens-Tokens (Länge >= 3, damit
 * z.B. "Ensemble" oder "Der" keine falschen Treffer erzeugen) muss im Text
 * vorkommen — ein einzelner Nachname-Treffer bei einem Zwei-Wort-Namen reicht,
 * ein einzelner Treffer bei einem Vier-Wort-Ensemblenamen nicht. */
function nameAppearsIn(entityName: string, haystack: string): boolean {
  const normalizedHaystack = normalizeForMatch(haystack);
  const tokens = normalizeForMatch(entityName).split(" ").filter((t) => t.length >= 3);
  if (!tokens.length) return false;
  const hits = tokens.filter((t) => normalizedHaystack.includes(t));
  return hits.length >= Math.max(1, Math.ceil(tokens.length / 2));
}

function largestFromSrcset(srcset: string, pageUrl: string): { url: string; widthHint: number | null } | null {
  let best: { url: string; width: number } | null = null;
  for (const entry of srcset.split(",")) {
    const parts = entry.trim().split(/\s+/);
    const url = parts[0];
    if (!url) continue;
    const descriptor = parts[1] ?? "";
    let width = 0;
    if (descriptor.endsWith("w")) width = parseInt(descriptor, 10) || 0;
    else if (descriptor.endsWith("x")) width = (parseFloat(descriptor) || 1) * 1000;
    if (!best || width > best.width) best = { url, width };
  }
  if (!best) return null;
  try {
    return { url: new URL(best.url, pageUrl).toString(), widthHint: best.width || null };
  } catch {
    return null;
  }
}

function attr(tag: string, name: string): string | null {
  const re = new RegExp(`${name}\\s*=\\s*["']([^"']+)["']`, "i");
  const match = tag.match(re);
  return match ? match[1] : null;
}

function stripTags(html: string): string {
  return html.replace(/<[^>]*>/g, " ").trim();
}

const RELEVANT_JSON_LD_TYPES = new Set([
  "Person",
  "Organization",
  "MusicGroup",
  "PerformingGroup",
  "Place",
  "LocalBusiness",
  "MusicVenue",
  "CivicStructure",
  "TouristAttraction",
]);

/** Sammelt Bild-URLs aus JSON-LD-Blöcken für Personen-/Organisations-/Orts-
 * artige Typen — getrennt nach "echtem" Foto (image/photo/thumbnailUrl) und
 * Logo (logo-Feld, siehe isLogoField-Penalty in scoreCandidate). Rekursiv
 * über @graph und beliebig verschachtelte Objekte, da manche Seiten
 * mehrere Entitäten in einem einzigen <script>-Block verschachteln. Jeder
 * JSON.parse-Fehler eines einzelnen Blocks wird übersprungen, nicht
 * geworfen — eine kaputte JSON-LD-Insel auf der Seite darf die übrigen
 * Blöcke/Kandidaten nicht verhindern. */
function extractJsonLdImages(html: string, pageUrl: string): { images: string[]; logos: string[] } {
  const images: string[] = [];
  const logos: string[] = [];
  const scriptPattern = /<script[^>]+type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;

  const addUrl = (target: string[], value: string) => {
    try {
      target.push(new URL(value, pageUrl).toString());
    } catch {
      // ungültige URL im JSON-LD ignorieren
    }
  };
  const pushImageValue = (target: string[], val: unknown) => {
    if (!val) return;
    if (typeof val === "string") return addUrl(target, val);
    if (Array.isArray(val)) return val.forEach((v) => pushImageValue(target, v));
    if (typeof val === "object") {
      const obj = val as Record<string, unknown>;
      if (typeof obj.url === "string") addUrl(target, obj.url);
      else if (typeof obj.contentUrl === "string") addUrl(target, obj.contentUrl);
    }
  };
  const collect = (node: unknown) => {
    if (Array.isArray(node)) {
      node.forEach(collect);
      return;
    }
    if (!node || typeof node !== "object") return;
    const obj = node as Record<string, unknown>;
    if (Array.isArray(obj["@graph"])) collect(obj["@graph"]);

    const typeField = obj["@type"];
    const types = Array.isArray(typeField) ? typeField : [typeField];
    if (types.some((t) => typeof t === "string" && RELEVANT_JSON_LD_TYPES.has(t))) {
      pushImageValue(images, obj["image"]);
      pushImageValue(images, obj["photo"]);
      pushImageValue(images, obj["thumbnailUrl"]);
      pushImageValue(logos, obj["logo"]);
    }

    for (const value of Object.values(obj)) {
      if (value && typeof value === "object") collect(value);
    }
  };

  for (const match of html.matchAll(scriptPattern)) {
    try {
      collect(JSON.parse(match[1]));
    } catch {
      // ein kaputter JSON-LD-Block darf die anderen nicht verhindern
    }
  }
  return { images, logos };
}

function extractImgTagCandidates(html: string, pageUrl: string, isPressPage: boolean): RawCandidate[] {
  const results: RawCandidate[] = [];
  let position = 0;
  for (const match of html.matchAll(IMG_TAG_PATTERN)) {
    const tag = match[0];
    const classAndId = `${attr(tag, "class") ?? ""} ${attr(tag, "id") ?? ""}`;
    const srcset = attr(tag, "srcset");

    let resolvedUrl: string | null = null;
    let widthFromSrcset: number | null = null;
    if (srcset) {
      const best = largestFromSrcset(srcset, pageUrl);
      if (best) {
        resolvedUrl = best.url;
        widthFromSrcset = best.widthHint;
      }
    }
    if (!resolvedUrl) {
      const src = attr(tag, "src") ?? attr(tag, "data-src");
      if (!src) {
        position++;
        continue;
      }
      try {
        resolvedUrl = new URL(src, pageUrl).toString();
      } catch {
        position++;
        continue;
      }
    }

    const widthAttr = Number(attr(tag, "width"));
    const heightAttr = Number(attr(tag, "height"));
    results.push({
      url: resolvedUrl,
      pageUrl,
      source: HERO_PATTERN.test(classAndId) ? "hero" : "content",
      isPressPage,
      altText: attr(tag, "alt"),
      widthHint: widthFromSrcset ?? (Number.isFinite(widthAttr) && widthAttr > 0 ? widthAttr : null),
      heightHint: Number.isFinite(heightAttr) && heightAttr > 0 ? heightAttr : null,
      positionIndex: position,
    });
    position++;
  }
  return results;
}

function extractDirectImageLinks(html: string, pageUrl: string, isPressPage: boolean): RawCandidate[] {
  const results: RawCandidate[] = [];
  for (const match of html.matchAll(A_TAG_PATTERN)) {
    const href = match[1];
    if (!IMAGE_EXT_PATTERN.test(href)) continue;
    let resolved: URL;
    try {
      resolved = new URL(href, pageUrl);
    } catch {
      continue;
    }
    if (resolved.protocol !== "http:" && resolved.protocol !== "https:") continue;
    results.push({
      url: resolved.toString(),
      pageUrl,
      source: "direct_link",
      isPressPage,
      altText: stripTags(match[2]) || null,
      widthHint: null,
      heightHint: null,
      positionIndex: 99,
    });
  }
  return results;
}

function extractCandidatesFromPage(html: string, pageUrl: string): RawCandidate[] {
  const isPressPage = SUBPAGE_KEYWORD_PATTERN.test(pageUrl);
  const results: RawCandidate[] = [];

  const { ogImage, twitterImage } = extractMetaImages(html, pageUrl);
  if (ogImage) {
    results.push({ url: ogImage, pageUrl, source: "og_image", isPressPage, altText: null, widthHint: null, heightHint: null, positionIndex: 99 });
  }
  if (twitterImage) {
    results.push({ url: twitterImage, pageUrl, source: "twitter_image", isPressPage, altText: null, widthHint: null, heightHint: null, positionIndex: 99 });
  }

  const { images: jsonLdImages, logos: jsonLdLogos } = extractJsonLdImages(html, pageUrl);
  for (const url of jsonLdImages) {
    results.push({ url, pageUrl, source: "json_ld", isPressPage, altText: null, widthHint: null, heightHint: null, positionIndex: 99 });
  }
  for (const url of jsonLdLogos) {
    results.push({ url, pageUrl, source: "json_ld", isPressPage, altText: null, widthHint: null, heightHint: null, positionIndex: 99, isLogoField: true });
  }

  results.push(...extractImgTagCandidates(html, pageUrl, isPressPage));
  results.push(...extractDirectImageLinks(html, pageUrl, isPressPage));
  return results;
}

/** Filtert offensichtlich dekorative Treffer VOR dem Scoring aus (Icons,
 * Spacer, Tracking-Pixel, Social-Media-Badges, SVGs, extreme
 * Seitenverhältnisse) — reine Verteidigung in der Tiefe, das Scoring würde
 * die meisten davon ohnehin niedrig bewerten, aber sie sollen erst gar
 * nicht als Kandidat auftauchen. isLikelyGenericImage() (aus
 * imageValidation.ts) wird wiederverwendet statt eine zweite,
 * abweichende Logo-/Platzhalter-Erkennung zu pflegen. Exportiert für
 * officialSiteImageSearch.test.ts — reine Funktion, kein Netzwerkzugriff. */
export function isDecorative(c: RawCandidate): boolean {
  if (/\.svg(?:[?#]|$)/i.test(c.url)) return true;
  if (isLikelyGenericImage(c.url)) return true;
  if (DECORATIVE_PATTERN.test(c.url) || (c.altText && DECORATIVE_PATTERN.test(c.altText))) return true;
  if (c.widthHint !== null && c.widthHint < 150) return true;
  if (c.heightHint !== null && c.heightHint < 150) return true;
  if (c.widthHint && c.heightHint) {
    const ratio = c.widthHint / c.heightHint;
    if (ratio > 6 || ratio < 0.15) return true;
  }
  return false;
}

async function readBoundedHtml(res: Response, maxBytes: number): Promise<string> {
  if (!res.body) return "";
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  let read = 0;
  while (read < maxBytes) {
    const { done, value } = await reader.read();
    if (done) break;
    read += value.byteLength;
    text += decoder.decode(value, { stream: true });
  }
  await reader.cancel().catch(() => {});
  return text;
}

/** Lädt eine einzelne Seite SSRF-sicher (isPublicImageUrl wird trotz des
 * bild-spezifischen Namens hier bewusst wiederverwendet — die Prüfung
 * selbst ist generisch: Protokoll/Host, nicht bildspezifisch) mit
 * begrenzter, erneut geprüfter Redirect-Kette, Timeout und Byte-Obergrenze.
 * Wirft bei jedem Fehlschlag (Netzwerk, Timeout, Nicht-HTML-Antwort,
 * HTTP-Fehlerstatus) — der Aufrufer fängt das pro Seite ab und macht mit
 * der nächsten Seite weiter, siehe searchOfficialSiteForImagesInner(). */
async function fetchPageHtml(pageUrl: string): Promise<string> {
  let current = pageUrl;
  for (let redirects = 0; redirects <= 3; redirects++) {
    if (!isPublicImageUrl(current)) {
      throw new Error("Ziel-URL zeigt (ggf. nach Weiterleitung) auf ein internes/privates Ziel.");
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), PAGE_TIMEOUT_MS);
    let res: Response;
    try {
      res = await fetch(current, {
        headers: { "User-Agent": USER_AGENT },
        redirect: "manual",
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }
    if ([301, 302, 303, 307, 308].includes(res.status)) {
      const location = res.headers.get("location");
      if (!location) throw new Error("Weiterleitung ohne Location-Header.");
      current = new URL(location, current).toString();
      continue;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const contentType = (res.headers.get("content-type") ?? "").toLowerCase();
    if (!contentType.includes("text/html") && !contentType.includes("application/xhtml")) {
      throw new Error(`Kein HTML-Inhalt (${contentType || "unbekannter Content-Type"}).`);
    }
    return await readBoundedHtml(res, MAX_HTML_BYTES);
  }
  throw new Error("Zu viele Weiterleitungen.");
}

/** Exportiert für officialSiteImageSearch.test.ts — arbeitet rein auf schon
 * geladenem HTML, kein Netzwerkzugriff. */
export function discoverSubpageLinks(html: string, pageUrl: string, siteHost: string): string[] {
  const found: string[] = [];
  const seen = new Set<string>();
  for (const match of html.matchAll(A_TAG_PATTERN)) {
    const href = match[1];
    const linkText = stripTags(match[2]);
    if (!SUBPAGE_KEYWORD_PATTERN.test(`${href} ${linkText}`)) continue;
    let resolved: URL;
    try {
      resolved = new URL(href, pageUrl);
    } catch {
      continue;
    }
    if (resolved.host !== siteHost) continue;
    if (resolved.protocol !== "http:" && resolved.protocol !== "https:") continue;
    const resolvedString = resolved.toString();
    if (resolvedString === pageUrl || seen.has(resolvedString)) continue;
    seen.add(resolvedString);
    found.push(resolvedString);
  }
  return found;
}

async function searchOfficialSiteForImagesInner(
  entityName: string,
  websiteUrl: string,
): Promise<OfficialSiteCrawlResult> {
  const errors: string[] = [];
  const pagesVisited: string[] = [];

  let siteHost: string;
  try {
    siteHost = new URL(websiteUrl).host;
  } catch {
    return { candidates: [], pagesVisited, errors: ["Ungültige Website-URL."] };
  }
  if (!isPublicImageUrl(websiteUrl)) {
    return {
      candidates: [],
      pagesVisited,
      errors: ["Website-URL zeigt auf ein internes/privates Ziel und wird aus Sicherheitsgründen nicht abgerufen."],
    };
  }

  const rawCandidates = new Map<string, RawCandidate>();
  const queue: Array<{ url: string; depth: number }> = [{ url: websiteUrl, depth: 0 }];
  const seenPages = new Set<string>([websiteUrl]);

  while (queue.length && pagesVisited.length < MAX_PAGES) {
    const next = queue.shift();
    if (!next) break;
    const { url: pageUrl, depth } = next;

    let html: string;
    try {
      if (!(await isAllowedByRobots(pageUrl))) {
        errors.push(`robots.txt verbietet den Zugriff auf ${pageUrl}.`);
        continue;
      }
      html = await fetchPageHtml(pageUrl);
    } catch (err) {
      errors.push(`Seite nicht abrufbar (${pageUrl}): ${err instanceof Error ? err.message : String(err)}`);
      continue;
    }
    pagesVisited.push(pageUrl);
    if (!html) continue;

    try {
      for (const candidate of extractCandidatesFromPage(html, pageUrl)) {
        if (!rawCandidates.has(candidate.url)) rawCandidates.set(candidate.url, candidate);
      }
    } catch (err) {
      errors.push(`Bildextraktion fehlgeschlagen (${pageUrl}): ${err instanceof Error ? err.message : String(err)}`);
    }

    if (depth < MAX_DEPTH && pagesVisited.length < MAX_PAGES) {
      try {
        for (const sub of discoverSubpageLinks(html, pageUrl, siteHost)) {
          if (seenPages.has(sub) || seenPages.size >= MAX_QUEUE_SIZE) continue;
          seenPages.add(sub);
          queue.push({ url: sub, depth: depth + 1 });
        }
      } catch {
        // Unterseiten-Erkennung ist best-effort, ein Fehler hier stoppt nicht den Lauf
      }
    }
  }

  const candidates = Array.from(rawCandidates.values())
    .filter((c) => !isDecorative(c))
    .map((c) => {
      const scored = scoreCandidate(c, { entityName, siteHost });
      const result: CrawledImageCandidate = {
        url: c.url,
        pageUrl: c.pageUrl,
        source: c.source,
        altText: c.altText,
        ...scored,
      };
      return result;
    })
    .sort((a, b) => b.score - a.score);

  return { candidates, pagesVisited, errors };
}

/** Durchsucht die offizielle Website einer Entität nach Bildkandidaten —
 * wirft NIE (siehe Datei-Kommentar), jeder unerwartete Fehler liefert ein
 * leeres Ergebnis mit Fehlermeldung statt die aufrufende Recherche-Kaskade
 * abzubrechen. `entityName` steuert nur das Namens-Matching im Scoring
 * (scoreCandidate), nicht die Suche selbst. */
export async function searchOfficialSiteForImages(
  entityName: string,
  websiteUrl: string,
): Promise<OfficialSiteCrawlResult> {
  try {
    return await searchOfficialSiteForImagesInner(entityName, websiteUrl);
  } catch (err) {
    return {
      candidates: [],
      pagesVisited: [],
      errors: [`Unerwarteter Fehler bei der Website-Recherche: ${err instanceof Error ? err.message : String(err)}`],
    };
  }
}
