// Extrahiert ein Bild von der Seite einer KONKRETEN Veranstaltung, an der
// eine Person/ein Ensemble mitwirkt — auf Nutzerfeedback: die bisherige
// Wikimedia-Blindsuche nach bloßem Namen lieferte für Personen zu viele
// falsche Treffer (Namensgleichheiten, z. B. "Lazarova" traf ein völlig
// anderes Wikimedia-Motiv). Eine Konzertprogramm-Seite, auf der diese
// Person/dieses Ensemble tatsächlich als Mitwirkende:r aufgeführt ist, ist
// ein weit präziserer Kontext als eine Namensvolltextsuche über alle
// Wikimedia-Commons-Dateien hinweg.
//
// Heuristik (bewusst konservativ — lieber nichts finden als ein falsches
// Bild): sucht <img alt="...Name...">, dann <figure><figcaption>...Name...
// </figcaption><img></figure>. Kein Treffer = null, nie eine Vermutung
// "das könnte trotzdem passen".
//
// Eine dritte Stufe ("nächstgelegenes <img> zu einem Textknoten mit dem
// Namen, unabhängig von alt/figcaption") wurde bewusst NICHT gebaut bzw.
// nach einem Live-Test wieder entfernt: auf einer Konzert-Listing-Seite
// (bellarte-muenchen.de) fing sie wiederholt dasselbe generische
// "Tickets kaufen"-Icon statt eines Porträts ein, weil das Icon zufällig
// im selben Listen-Item wie der Name stand. Ohne alt/figcaption-Bezug gibt
// es keine verlässliche Garantie, dass ein strukturell "nahes" Bild
// tatsächlich DAS Bild dieser Person ist — lieber ein Treffer weniger als
// wieder ein falsches/generisches Bild.
//
// WICHTIG: anders als die eigene offizielle Website der Entität selbst ist
// das hier die Seite eines DRITTEN (Veranstalter/Venue/Ticketanbieter) —
// keine Lizenzinformation bekannt, daher landet ein Treffer immer in der
// manuellen Review-Queue, nie automatisch übernommen (siehe index.ts).

import { parseHTML } from "npm:linkedom@0.18.4";
import { isAllowedByRobots, USER_AGENT } from "./robots.ts";

function normalize(text: string): string {
  return text.toLowerCase().replace(/\s+/g, " ").trim();
}

function resolveUrl(value: string | null, baseUrl: string): string | null {
  if (!value) return null;
  try {
    return new URL(value, baseUrl).toString();
  } catch {
    return null;
  }
}

/** Lädt `pageUrl` (robots.txt-geprüft) und sucht ein Bild, das erkennbar zu
 * `name` gehört. Gibt null bei robots.txt-Sperre, jedem Fetch-/Parse-Fehler
 * oder fehlendem Treffer zurück. */
export async function extractImageNearName(
  pageUrl: string,
  name: string,
): Promise<string | null> {
  if (!(await isAllowedByRobots(pageUrl))) return null;

  let html: string;
  try {
    const res = await fetch(pageUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return null;
    html = await res.text();
  } catch {
    return null;
  }

  const needle = normalize(name);
  if (!needle) return null;

  // linkedom liefert in der Deno-Runtime ein document, deklariert seinen
  // Rückgabewert aber als Window ohne DOM-lib-Typen.
  // deno-lint-ignore no-explicit-any
  let document: any;
  try {
    // deno-lint-ignore no-explicit-any
    document = (parseHTML(html) as any).document;
  } catch {
    return null;
  }

  // 1) <img alt="...Name...">
  // deno-lint-ignore no-explicit-any
  for (const img of Array.from(document.querySelectorAll("img")) as any[]) {
    const alt = img.getAttribute("alt");
    if (alt && normalize(alt).includes(needle)) {
      const src = img.getAttribute("src");
      const resolved = resolveUrl(src, pageUrl);
      if (resolved && !isLikelyDecorativeAsset(resolved)) return resolved;
    }
  }

  // 2) <figure> mit <figcaption>, die den Namen enthält
  // deno-lint-ignore no-explicit-any
  for (const figure of Array.from(document.querySelectorAll("figure")) as any[]) {
    const caption = figure.querySelector("figcaption");
    if (!caption) continue;
    if (!normalize(caption.textContent ?? "").includes(needle)) continue;
    const img = figure.querySelector("img");
    const src = img?.getAttribute("src");
    const resolved = resolveUrl(src, pageUrl);
    if (resolved && !isLikelyDecorativeAsset(resolved)) return resolved;
  }

  return null;
}

/** Grobe Zweitsicherung gegen offensichtlich generische Grafiken (Icons,
 * Buttons, Logos, Spacer) — auch ein alt/figcaption-Treffer kann auf einer
 * schlampig ausgezeichneten Seite zufällig auf sowas landen. Kein
 * Ersatz für eine echte Bildinhaltsprüfung, nur ein Filter gegen die
 * offensichtlichsten Fehltreffer. */
function isLikelyDecorativeAsset(url: string): boolean {
  const path = url.toLowerCase();
  return /ticket|logo|icon|button|btn[-_.]|spacer|pixel|arrow|share|social|placeholder|sprite|banner/
    .test(path);
}
