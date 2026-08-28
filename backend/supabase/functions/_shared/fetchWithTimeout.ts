// Live beobachteter Bug: mehrere fetch()-Aufrufe in diesem Projekt (Event-
// Titelbild-Seite in coverImageDetection.ts, robots.txt in robots.ts) hatten
// KEIN eigenes Timeout — anders als imageValidation.ts's checkImageUrl(),
// das dafür bereits einen eigenen AbortController nutzt. Eine einzelne
// nie antwortende Fremdseite (kein Fehler, kein HTTP-Timeout, einfach
// endlos hängend) blockierte dadurch unbegrenzt den kompletten Worker in
// enrichEventCovers() — bei EVENT_CONCURRENCY=4 reichte EIN hängender
// Termin, um den gesamten Batch-Lauf nie zurückkehren zu lassen (Symptom:
// "Bildsuche fehlgeschlagen: The operation was aborted due to timeout"
// UND null neue Bilder, weil der betroffene Worker nie beim nächsten
// Termin ankam). Gemeinsame Utility statt pro Datei eine eigene Kopie.
export async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs = 12_000,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}
