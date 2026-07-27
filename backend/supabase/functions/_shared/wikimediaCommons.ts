// Bildersuche über die Wikimedia-Commons-API — bewusst statt einer
// allgemeinen Bildersuche/Websuche gewählt, weil Commons pro Datei
// maschinenlesbare Lizenzmetadaten liefert (siehe extmetadata.License unten)
// und schon bei der ursprünglichen Excel-Stammdaten-Recherche als Bildquelle
// genutzt wurde (siehe 20260817000002_import_excel_stammdaten.sql). Keine
// API-Key nötig, im Gegensatz zu Tavily (_shared/tavily.ts, das für
// Text-/Kontext-Suche genutzt wird, nicht für Bilder mit Lizenzangabe).
//
// WICHTIG: ein "freies" License-Feld hier bedeutet NICHT automatisch
// freigegeben — images.needs_review bleibt in jedem Fall true (siehe
// 20260819000003_images_and_tags.sql), das hier ist nur ein Vorfilter gegen
// eindeutig ungeeignete Treffer (z. B. "All Rights Reserved"-Digitalisate in
// einer sonst freien Kategorie) und eine Arbeitshilfe für die Redaktion
// (licenseNotes).

const COMMONS_API = "https://commons.wikimedia.org/w/api.php";

// Lizenz-Werte, wie Commons sie in extmetadata.License.value schreibt
// (klein geschrieben, Bindestriche/Punkte variieren je nach Lizenz-Template).
// Bewusst KEIN GFDL: dessen Bedingungen (u. a. vollständiger Lizenztext bei
// jeder Weiterverwendung) passen schlecht zu einer mobilen App-Nutzung ohne
// redaktionelle Einzelprüfung des genauen Wortlauts.
const ACCEPTED_LICENSE_PATTERN =
  /^(cc0|cc-by(-sa)?-[\d.]+|public domain|pd-|cc-zero)/i;

export interface CommonsImageCandidate {
  url: string;
  pageUrl: string;
  license: string;
  artist: string | null;
  attributionRequired: boolean;
}

interface CommonsQueryPage {
  title?: string;
  imageinfo?: Array<{
    url?: string;
    descriptionurl?: string;
    extmetadata?: {
      License?: { value?: string };
      LicenseShortName?: { value?: string };
      Artist?: { value?: string };
    };
  }>;
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]*>/g, "").trim();
}

/** Gemeinsame Extraktion für beide Abfrageformen unten (Volltextsuche via
 * generator=search und Direkt-Lookup via titles=) — beide liefern dieselbe
 * `query.pages`-Form zurück. Nimmt den ersten Treffer mit einer erkennbar
 * freien Lizenz. */
function extractFirstAcceptableCandidate(
  pages: Record<string, CommonsQueryPage> | undefined,
): CommonsImageCandidate | null {
  if (!pages) return null;

  for (const page of Object.values(pages)) {
    const info = page.imageinfo?.[0];
    if (!info?.url) continue;
    const licenseValue = info.extmetadata?.License?.value ?? "";
    if (!ACCEPTED_LICENSE_PATTERN.test(licenseValue.trim())) continue;

    const licenseName = info.extmetadata?.LicenseShortName?.value ?? licenseValue;
    const artistRaw = info.extmetadata?.Artist?.value;
    return {
      url: info.url,
      pageUrl: info.descriptionurl ?? info.url,
      license: licenseName,
      artist: artistRaw ? stripHtml(artistRaw) || null : null,
      // CC0/Public-Domain-Varianten verlangen keine Namensnennung, alles
      // andere in unserer Allowlist (CC-BY, CC-BY-SA) schon.
      attributionRequired: !/^(cc0|public domain|pd-|cc-zero)/i.test(licenseValue.trim()),
    };
  }

  return null;
}

async function fetchCommonsQuery(
  params: Record<string, string>,
): Promise<Record<string, CommonsQueryPage> | undefined> {
  const url = new URL(COMMONS_API);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  url.searchParams.set("format", "json");
  url.searchParams.set("origin", "*");

  let res: Response;
  try {
    res = await fetch(url.toString(), {
      headers: { "User-Agent": "KlassikMuenchenBot/1.0 (redaktionelle Bilderrecherche)" },
    });
  } catch {
    return undefined;
  }
  if (!res.ok) return undefined;

  // deno-lint-ignore no-explicit-any
  let data: any;
  try {
    data = await res.json();
  } catch {
    return undefined;
  }
  return data?.query?.pages as Record<string, CommonsQueryPage> | undefined;
}

/** Sucht bis zu `limit` Bilddateien zu `query` auf Wikimedia Commons und gibt
 * den ersten Treffer mit einer erkennbar freien Lizenz zurück, oder null bei
 * jedem Fehler/keinem geeigneten Treffer — Aufrufer behandeln null als
 * "keine automatische Anreicherung möglich", kein Werfen. */
export async function searchCommonsImage(
  query: string,
  limit = 5,
): Promise<CommonsImageCandidate | null> {
  const pages = await fetchCommonsQuery({
    action: "query",
    generator: "search",
    gsrsearch: query,
    gsrnamespace: "6", // File:-Namespace
    gsrlimit: String(limit),
    prop: "imageinfo",
    iiprop: "url|extmetadata",
  });
  return extractFirstAcceptableCandidate(pages);
}

/** Direkter Lookup einer bekannten Commons-Datei nach Dateiname (kein
 * Ranking/Volltextsuche) — für Fälle, in denen der Dateiname bereits aus
 * einer anderen strukturierten Quelle bekannt ist (z. B. Wikidatas
 * P18-Bildeigenschaft, siehe wikidataImage.ts), statt zu raten, ob die
 * Volltextsuche dieselbe Datei hoch genug rankt. */
export async function getCommonsFileInfoByTitle(filename: string): Promise<CommonsImageCandidate | null> {
  const title = filename.startsWith("File:") || filename.startsWith("Datei:") ? filename : `File:${filename}`;
  const pages = await fetchCommonsQuery({
    action: "query",
    titles: title,
    prop: "imageinfo",
    iiprop: "url|extmetadata",
  });
  return extractFirstAcceptableCandidate(pages);
}
