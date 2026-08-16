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

/** Blockiert lokale, private und link-local Ziele. Die Prüfung wird von der
 * Download-Pipeline bei jedem Redirect erneut durchgeführt. */
export function isPublicImageUrl(value: string): boolean {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return false;
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (
    host === "localhost" || host.endsWith(".localhost") ||
    host.endsWith(".local")
  ) return false;
  if (
    host === "::1" || host === "0.0.0.0" || host.startsWith("fe80:") ||
    host.startsWith("fc") || host.startsWith("fd")
  ) return false;
  const parts = host.split(".").map(Number);
  if (
    parts.length === 4 &&
    parts.every((part) => Number.isInteger(part) && part >= 0 && part <= 255)
  ) {
    const [a, b] = parts;
    if (
      a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || a >= 224
    ) return false;
  }
  return true;
}

export interface ImageCheckResult {
  reachable: boolean;
  contentType: string | null;
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
): Promise<Response> {
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
  if (!isPublicImageUrl(url)) {
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

/** Erkennt offensichtlich generische Bilder (Site-weite Standard-og:image,
 * Logos, Banner, Platzhalter) anhand des Dateinamens — auf Nutzerfeedback:
 * mehrere Ticketportale (muenchenmusik.de, muenchenevent.de,
 * hoertnagel.de) liefern für JEDE Veranstaltungsseite, die selbst kein
 * eigenes og:image setzt, dasselbe site-weite Fallback-Bild
 * ("default--og-image--mm.jpg" o. ä.) aus — das sah aus wie ein
 * generisches Portal-/Veranstalter-Logo statt eines echten Event-Bilds und
 * wurde (vor diesem Fix zusätzlich durch einen Duplikat-Check-Bug
 * begünstigt) für viele verschiedene Events übernommen. Kein Ersatz für
 * eine echte Bildinhaltsprüfung, nur ein Filter gegen die offensichtlichsten
 * Fälle anhand des URL-Musters. */
export function isLikelyGenericImage(url: string): boolean {
  const path = url.toLowerCase();
  // .svg zusätzlich zur URL-Muster-Erkennung: in der Praxis (siehe
  // officialSiteImageSearch.ts/isDecorative und readerProxyImage.ts, die
  // beide unabhängig auf dieselbe Regel kamen) sind SVGs auf diesen Seiten
  // praktisch nie echte Event-/Personenfotos, sondern Icons/Logos/
  // Illustrationen — z.B. mphil.de setzt für JEDE Konzertseite dasselbe
  // generische ".../Icons/Logos/default.svg" als og:image, das die reinen
  // Namensmuster unten (kein "logo" als eigenes Wort) nicht fangen.
  if (/\.svg(?:[?#]|$)/.test(path)) return true;
  return /default[-_]*[-_]og[-_]image|og[-_]image[-_]*default|\blogo\b|logo[-_.]|[-_.]logo\b|placeholder|\bbanner\b/
    .test(path);
}
