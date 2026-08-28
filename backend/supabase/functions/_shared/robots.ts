// Geteilte robots.txt-Prüfung + User-Agent für alle Ingestion-Connectoren
// (ingest-source's scrape-Typ, extract-event-from-url). War ursprünglich
// nur in ingest-source/index.ts, hierher gezogen als extract-event-from-url
// dieselbe Logik für beliebige Admin-eingegebene URLs brauchte.

import { fetchWithTimeout } from "./fetchWithTimeout.ts";

export const USER_AGENT = "KlassikMuenchenBot/1.0 (+event discovery app; contact via source venue)";

/** Bestes-Bemühen robots.txt-Check: nur "Disallow"-Präfixe unter
 * "User-agent: *", keine Wildcards/Regex-Muster, kein Crawl-Delay. Deckt den
 * Normalfall ab; bei Fetch-Fehler wird konservativ NICHT blockiert (fehlende
 * robots.txt heißt "alles erlaubt"), aber ein echter Fund einer verbotenen
 * Regel blockiert zuverlässig. */
export async function isAllowedByRobots(targetUrl: string): Promise<boolean> {
  let robotsUrl: string;
  let path: string;
  try {
    const u = new URL(targetUrl);
    robotsUrl = `${u.origin}/robots.txt`;
    path = u.pathname || "/";
  } catch {
    return true;
  }

  let text: string;
  try {
    const res = await fetchWithTimeout(robotsUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return true;
    text = await res.text();
  } catch {
    return true;
  }

  let inWildcardGroup = false;
  const disallows: string[] = [];
  for (const rawLine of text.split("\n")) {
    const line = rawLine.split("#")[0].trim();
    if (!line) continue;
    const [field, ...rest] = line.split(":");
    const value = rest.join(":").trim();
    const key = field.trim().toLowerCase();
    if (key === "user-agent") {
      inWildcardGroup = value === "*";
    } else if (key === "disallow" && inWildcardGroup && value) {
      disallows.push(value);
    }
  }

  return !disallows.some((rule) => path.startsWith(rule));
}
