// Extrahiert bereinigten sichtbaren Text einer Seite (nicht nur og:image
// wie _shared/ogImage.ts) — Fundament für die grundlegend erweiterte
// Datenanreicherung (Nutzeranfrage: "Recherchiere automatisch aus
// offiziellen, vertrauenswürdigen Quellen"). Ein Event-Programm, Besetzung,
// Einlasszeit, Opus/Werkverzeichnis stehen oft NUR im vollen Seitentext der
// offiziellen Quelle, nicht im knappen description_de, das die Ingestion
// bereits gesetzt hat.
//
// Bewusst simpel gehalten (kein echtes Readability-Parsing): <script>/
// <style> entfernen, verbleibende Tags durch Leerraum ersetzen, mehrfachen
// Whitespace zusammenfassen, auf MAX_CHARS begrenzen (Prompt-Größe/Kosten
// der AI-Provider-Kette kontrollieren, siehe _shared/ai/router.ts). Respekt
// vor robots.txt wie bei jedem anderen Fetch eines fremden Hosts in diesem
// Projekt (siehe _shared/robots.ts).

import { isAllowedByRobots, USER_AGENT } from "./robots.ts";

const MAX_CHARS = 6000;

/** Lädt `pageUrl` (robots.txt-geprüft) und liefert bereinigten sichtbaren
 * Text, oder null bei robots.txt-Sperre/jedem Fetch-Fehler — Aufrufer
 * behandeln null wie "kein zusätzlicher Kontext verfügbar", nie einen
 * Fehlerfall. */
export async function fetchPageText(pageUrl: string): Promise<string | null> {
  if (!(await isAllowedByRobots(pageUrl))) return null;

  let html: string;
  try {
    const res = await fetch(pageUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return null;
    html = await res.text();
  } catch {
    return null;
  }

  const withoutScripts = html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ");

  // Zeilenumbrüche vor dem Tag-Strip einfügen — sonst verschmilzt z. B.
  // eine "Komponist"-Zeile mit der direkt folgenden "Werktitel"-Zeile zu
  // einem ununterscheidbaren Fließtext-Strom. Live beobachtet: eine
  // Konzertprogramm-Seite mit Komponist/Werk je in eigenem <p> lieferte
  // dadurch für KEIN einziges Werk einen Komponisten (enrich-event-
  // references konnte Name und Titel nicht mehr paarweise zuordnen),
  // obwohl die Seite selbst die Zuordnung eindeutig zeigt. Betrifft alle
  // fetchPageText()-Aufrufer (auch enrich-person-profile/-venue-details/
  // -ensemble-profile) — mehr Zeilenstruktur ist für jede Extraktion aus
  // Fließtext eine reine Verbesserung, nie ein Nachteil.
  const withLineBreaks = withoutScripts.replace(
    /<br\s*\/?>|<\/(p|div|li|h[1-6]|tr|section|article)\s*>/gi,
    "\n",
  );

  const text = withLineBreaks
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&[a-z]+;/gi, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  return text ? text.slice(0, MAX_CHARS) : null;
}
