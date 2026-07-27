// Findet wahrscheinliche Unterseiten (Presse/Ueber-uns/Kontakt/Ensemble)
// einer Entitaets-Website, wenn die Startseite selbst kein brauchbares
// Bild liefert (coverImageDetection.ts prueft nur EINE Seite, meistens
// die Startseite). Manche Vereine/Ensembles/Venues haben eine
// text-lastige Startseite ohne Foto, aber ein Foto auf einer "Ueber
// uns"/Presse-Unterseite. Nur derselbe Host wie die Ausgangs-URL (keine
// externen Presseverzeichnisse/Social-Links), robots.txt wird wie bei
// jedem anderen Fetch respektiert.

import { isAllowedByRobots, USER_AGENT } from "./robots.ts";

const SUBPAGE_KEYWORD_PATTERN =
  /presse|press|about|über-?uns|ueber-?uns|kontakt|contact|team|geschichte|history|profil|portrait|ensemble|orchester/i;

const A_TAG_PATTERN = /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a\s*>/gi;

function stripTags(html: string): string {
  return html.replace(/<[^>]*>/g, " ").trim();
}

/** Liefert bis zu `max` Unterseiten-URLs derselben Domain, deren Link-Text
 * oder href auf typische "Ueber uns"/Presse-/Kontakt-Inhalte hindeutet —
 * oder eine leere Liste bei robots.txt-Sperre, Fetch-Fehler oder keinem
 * Treffer. Nie werfen. */
export async function findLikelySubpages(pageUrl: string, max = 2): Promise<string[]> {
  if (!(await isAllowedByRobots(pageUrl))) return [];

  let html: string;
  try {
    const res = await fetch(pageUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return [];
    html = await res.text();
  } catch {
    return [];
  }

  let baseHost: string;
  try {
    baseHost = new URL(pageUrl).host;
  } catch {
    return [];
  }

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
    if (resolved.host !== baseHost) continue;
    const resolvedString = resolved.toString();
    if (resolvedString === pageUrl || seen.has(resolvedString)) continue;

    seen.add(resolvedString);
    found.push(resolvedString);
    if (found.length >= max) break;
  }
  return found;
}
