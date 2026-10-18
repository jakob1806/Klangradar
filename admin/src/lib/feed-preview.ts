// Self-Service-Import im Veranstalterportal: erkennt aus dem Inhalt einer
// Feed-Adresse den Quelltyp (passend zu den Parsern in ingest-source) und
// liefert eine kleine Vorschau, damit Veranstalter vor dem Einreichen sehen,
// ob ihre Termine überhaupt gelesen werden können.

export type FeedType = "ical" | "rss" | "schema_org";
export type FeedPreview = { type: FeedType; count: number; samples: { title: string; start: string | null }[] };

/** RFC 5545: Fortsetzungszeilen beginnen mit Leerzeichen/Tab. */
function unfoldIcs(text: string): string[] {
  return text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "").split("\n");
}

function unescapeIcs(value: string): string {
  return value.replace(/\\n/gi, " ").replace(/\\([,;\\])/g, "$1").trim();
}

/** DTSTART:20261024T193000 / DTSTART;TZID=Europe/Berlin:20261024T193000 / VALUE=DATE:20261024 */
function icsDate(value: string): string | null {
  const m = value.match(/(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2}))?/);
  if (!m) return null;
  return m[4] ? `${m[1]}-${m[2]}-${m[3]} ${m[4]}:${m[5]}` : `${m[1]}-${m[2]}-${m[3]}`;
}

function previewIcs(text: string): FeedPreview {
  const samples: FeedPreview["samples"] = [];
  let count = 0;
  let current: { title: string; start: string | null } | null = null;
  for (const line of unfoldIcs(text)) {
    if (line.startsWith("BEGIN:VEVENT")) current = { title: "", start: null };
    else if (line.startsWith("END:VEVENT") && current) {
      count++;
      if (samples.length < 5) samples.push({ ...current, title: current.title || "(ohne Titel)" });
      current = null;
    } else if (current && /^SUMMARY[;:]/.test(line)) current.title = unescapeIcs(line.slice(line.indexOf(":") + 1));
    else if (current && /^DTSTART[;:]/.test(line)) current.start = icsDate(line.slice(line.indexOf(":") + 1));
  }
  return { type: "ical", count, samples };
}

function decodeXml(value: string): string {
  return value
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .trim();
}

function previewRss(text: string): FeedPreview {
  const items = text.match(/<(item|entry)\b[\s\S]*?<\/\1>/gi) ?? [];
  const samples = items.slice(0, 5).map((item) => {
    const title = item.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i)?.[1];
    const date = item.match(/<(pubDate|published|updated|dc:date)\b[^>]*>([\s\S]*?)<\/\1>/i)?.[2];
    return { title: title ? decodeXml(title) : "(ohne Titel)", start: date ? decodeXml(date) : null };
  });
  return { type: "rss", count: items.length, samples };
}

type JsonLd = Record<string, unknown>;

function collectEvents(node: unknown, out: JsonLd[]): void {
  if (Array.isArray(node)) return node.forEach((n) => collectEvents(n, out));
  if (!node || typeof node !== "object") return;
  const obj = node as JsonLd;
  const type = obj["@type"];
  const types = Array.isArray(type) ? type : [type];
  if (types.some((t) => typeof t === "string" && /Event$/.test(t))) out.push(obj);
  if (obj["@graph"]) collectEvents(obj["@graph"], out);
  if (obj.itemListElement) collectEvents(obj.itemListElement, out);
  if (obj.item) collectEvents(obj.item, out);
}

function previewSchemaOrg(text: string): FeedPreview | null {
  const events: JsonLd[] = [];
  for (const m of text.matchAll(/<script[^>]+application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      collectEvents(JSON.parse(m[1]), events);
    } catch {
      // Kaputtes JSON-LD einzelner Blöcke ignorieren.
    }
  }
  if (!events.length) return null;
  return {
    type: "schema_org",
    count: events.length,
    samples: events.slice(0, 5).map((e) => ({
      title: typeof e.name === "string" ? e.name : "(ohne Titel)",
      start: typeof e.startDate === "string" ? e.startDate.replace("T", " ").slice(0, 16) : null,
    })),
  };
}

/** null = kein lesbares Format (Veranstalter bekommt einen Hinweis). */
export function previewFeed(text: string): FeedPreview | null {
  const head = text.slice(0, 2000);
  if (/BEGIN:VCALENDAR/.test(head)) return previewIcs(text);
  if (/<rss\b|<feed\b|<rdf:RDF\b/i.test(head)) return previewRss(text);
  return previewSchemaOrg(text);
}

/** Nur öffentliche http(s)-Adressen, keine internen Hosts. */
export function isAllowedFeedUrl(raw: string): URL | null {
  let url: URL;
  try {
    url = new URL(raw.trim().replace(/^webcal:\/\//i, "https://"));
  } catch {
    return null;
  }
  if (!["http:", "https:"].includes(url.protocol)) return null;
  const host = url.hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal")) return null;
  if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host) || host.startsWith("[")) return null;
  return url;
}
