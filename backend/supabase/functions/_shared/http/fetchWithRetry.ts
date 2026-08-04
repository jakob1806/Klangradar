// ingest-source's Haupt-Quellabruf (core.ts) hatte als einzige zentrale
// Netzwerkstelle im Ingestion-Pfad weder Timeout noch Retry — ein
// hängender Request band einen Worker-Slot in run-all-sources' begrenztem
// Pool für die volle Laufzeit, ein einzelner Netzwerk-Hänger ließ den
// ganzen Quellen-Lauf scheitern. Bewusst schlank: EIN Retry, nur bei
// echtem Netzwerkfehler (fetch() wirft) oder 5xx — nie bei 4xx (die Quelle
// hat geantwortet, ein erneuter Versuch würde nur denselben Fehler
// wiederholen) und nie bei 304 (bedeutungstragend, kein Fehler).

const DEFAULT_TIMEOUT_MS = 20_000;

export interface FetchWithRetryOptions {
  timeoutMs?: number;
  retries?: number;
  /** Wartezeit vor dem Retry — konstant statt exponentiell, weil es bei
   * genau einem Retry keinen Unterschied macht und so einfacher bleibt. */
  retryDelayMs?: number;
}

/** Wie fetch(), aber mit AbortController-Timeout und einem optionalen
 * Retry bei Netzwerkfehler/5xx. Wirft wie fetch() bei endgültigem
 * Fehlschlag (Timeout zählt als Netzwerkfehler), liefert sonst die
 * Response — auch bei 4xx/304, das entscheidet weiterhin der Aufrufer. */
export async function fetchWithRetry(
  url: string,
  init: RequestInit = {},
  options: FetchWithRetryOptions = {},
): Promise<Response> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const retries = options.retries ?? 1;
  const retryDelayMs = options.retryDelayMs ?? 1_000;

  let lastError: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(url, { ...init, signal: controller.signal });
      clearTimeout(timer);
      if (res.status >= 500 && attempt < retries) {
        lastError = new Error(`HTTP ${res.status}`);
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
        continue;
      }
      return res;
    } catch (err) {
      clearTimeout(timer);
      lastError = err;
      if (attempt < retries) {
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
        continue;
      }
    }
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError));
}
