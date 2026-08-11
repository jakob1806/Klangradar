// Das Gärtnerplatztheater rendert den Spielplan ausschließlich über eine
// paginierte POST-AJAX-Kette. Offset 1 ist die erste Inhaltsseite; jede
// Antwort liefert in .letzterTermin den Cursor für die nächste Seite.

import { parseHTML } from "npm:linkedom@0.18.4";
import { USER_AGENT } from "../../_shared/robots.ts";

export async function fetchGaertnerplatzSchedule(url: string, maxPages = 80): Promise<string> {
  const chunks: string[] = [];
  let cursor = "0";
  for (let offset = 1; offset <= Math.min(Math.max(maxPages, 1), 100); offset++) {
    const pageUrl = new URL(url);
    pageUrl.searchParams.set("ajax", "1");
    pageUrl.searchParams.set("offset", String(offset));
    pageUrl.searchParams.set("letzterTermin", cursor);
    const res = await fetch(pageUrl, {
      method: "POST",
      headers: { "User-Agent": USER_AGENT, "Referer": url },
    });
    if (!res.ok) throw new Error(`Gärtnerplatz pagination ${offset}: HTTP ${res.status}`);
    const html = await res.text();
    if (!html.trim() || html.trim() === "ende erreicht.") break;
    chunks.push(html);
    const { document } = parseHTML(html) as any;
    const nextCursor = document.querySelector(".letzterTermin")?.textContent?.trim();
    if (!nextCursor || nextCursor === cursor) break;
    cursor = nextCursor;
  }
  return chunks.join("\n");
}
