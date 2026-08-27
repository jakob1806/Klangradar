// Holt eine Seite gerendert über Browserless (https://www.browserless.io/)
// statt eines rohen HTTP-GET — für Quellen, deren Event-Kalender per
// JavaScript nachgeladen wird (React/Vue-SPA-Kalender), wo ein normaler
// fetch() nur eine leere Hülle liefert (siehe docs/12-city-expansion-import.md,
// Abschnitt "Geprüft, aber technisch nicht umsetzbar").
//
// Nur für Quellen mit config.renderJs === true (siehe ingest-source/core.ts)
// -- alle anderen Quellen laufen unverändert über den bestehenden
// fetchWithRetry()-Pfad. robots.txt wird VOR diesem Aufruf geprüft (siehe
// core.ts, isAllowedByRobots()), unverändert -- Browserless ist nur ein
// anderer Transportweg für denselben (bereits erlaubten) Abruf, kein Weg,
// eine Sperre zu umgehen.

export class RenderedFetchError extends Error {}

/**
 * Rendert `url` per Browserless (JS-Ausführung inklusive) und liefert das
 * fertige HTML zurück. `waitForTimeoutMs` gibt der Seite Zeit, ihren
 * Kalender nach dem initialen Laden per JS zu befüllen -- die meisten
 * geprüften Quellen brauchen 3-8s (siehe einzelne Quellen-Migrationen).
 */
export async function fetchRendered(
  url: string,
  { waitForTimeoutMs = 6000, timeoutMs = 45000 }: { waitForTimeoutMs?: number; timeoutMs?: number } = {},
): Promise<string> {
  const token = Deno.env.get("BROWSERLESS_API_TOKEN");
  if (!token) {
    throw new RenderedFetchError(
      "BROWSERLESS_API_TOKEN ist nicht gesetzt -- config.renderJs=true kann ohne dieses Secret nicht bedient werden.",
    );
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`https://production-sfo.browserless.io/content?token=${token}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        url,
        gotoOptions: { waitUntil: "networkidle2" },
        waitForTimeout: waitForTimeoutMs,
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      throw new RenderedFetchError(`Browserless-Fehler: HTTP ${res.status} ${res.statusText}`);
    }
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}
