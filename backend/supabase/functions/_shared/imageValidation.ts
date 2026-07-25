// Prüft, ob eine Bild-URL tatsächlich erreichbar ist und ein Bild liefert,
// BEVOR sie in photo_url/image_urls geschrieben wird — auf expliziten
// Nutzerwunsch ("Vor dem Speichern prüfen, ob die Bild-URL erreichbar ist
// und tatsächlich ein Bild liefert. Keine kaputten URLs..."). Vorher wurde
// jede gefundene URL (og:image, Wikimedia-Fund) ungeprüft übernommen.
//
// HEAD zuerst (spart Bandbreite), aber manche Server unterstützen HEAD
// nicht zuverlässig für einzelne Assets (405/501 oder identisches Verhalten
// wie GET ohne Body-Optimierung) — dann Fallback auf GET mit Range-Header,
// damit trotzdem nur die ersten Bytes übertragen werden, nicht das ganze
// Bild. AbortController mit Timeout, damit ein einzelner langsamer Host
// nicht den gesamten Batch-Lauf blockiert.

const TIMEOUT_MS = 8_000;

export interface ImageCheckResult {
  reachable: boolean;
  contentType: string | null;
}

async function fetchWithTimeout(url: string, init: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

/** Liefert reachable=true nur wenn die URL mit einem 2xx-Status UND einem
 * "image/*"-Content-Type antwortet — eine 200-Fehlerseite (z. B. "Bild nicht
 * gefunden"-HTML einer CMS-Instanz) zählt bewusst NICHT als erreichbares
 * Bild. Jeder Netzwerkfehler/Timeout ergibt reachable=false, nie eine
 * geworfene Exception — Aufrufer behandeln das als "kein verlässliches
 * Bild", nicht als Fehlerfall. */
export async function checkImageUrl(url: string): Promise<ImageCheckResult> {
  try {
    new URL(url);
  } catch {
    return { reachable: false, contentType: null };
  }

  try {
    const headRes = await fetchWithTimeout(url, { method: "HEAD" });
    if (headRes.ok) {
      const contentType = headRes.headers.get("content-type");
      if (contentType?.toLowerCase().startsWith("image/")) {
        return { reachable: true, contentType };
      }
      // HEAD ok, aber kein Bild-Content-Type — kein zweiter GET nötig, das
      // Ergebnis wäre nicht anders (derselbe Server, dieselbe Ressource).
      return { reachable: false, contentType };
    }
    if (headRes.status !== 405 && headRes.status !== 501) {
      return { reachable: false, contentType: null };
    }
    // 405/501: Server lehnt HEAD grundsätzlich ab — GET-Fallback unten.
  } catch {
    // HEAD fehlgeschlagen (Netzwerk/Timeout) — GET-Fallback unten, manche
    // Server/CDNs blocken HEAD-Requests eigenständig ohne Standard-Fehlercode.
  }

  try {
    const getRes = await fetchWithTimeout(url, {
      method: "GET",
      headers: { Range: "bytes=0-2048" },
    });
    // 206 (Partial Content) oder 200 (Range ignoriert, ganze Datei) beide ok.
    if (!getRes.ok && getRes.status !== 206) {
      await getRes.body?.cancel().catch(() => {});
      return { reachable: false, contentType: null };
    }
    const contentType = getRes.headers.get("content-type");
    await getRes.body?.cancel().catch(() => {});
    return {
      reachable: contentType?.toLowerCase().startsWith("image/") ?? false,
      contentType,
    };
  } catch {
    return { reachable: false, contentType: null };
  }
}
