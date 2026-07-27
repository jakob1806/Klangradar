// Wikidata als zusätzliche, kostenlose Bildquelle (P18-Eigenschaft "Bild") —
// letzter Fallback in enrich-entity-images, NACH Wikipedia-Infobox (Personen)
// bzw. Wikimedia-Commons-Volltextsuche (Venues/Ensembles/Festivals). Manche
// Entitäten haben keinen (Wikipedia-)Artikel mit Infobox-Bild, aber ein
// eigenständiges Wikidata-Item mit strukturiert verknüpftem Bild — oder die
// Commons-Volltextsuche rankt die richtige Datei nicht hoch genug. Wikidata
// selbst liefert nur den Dateinamen (kein Lizenz-Metadatum), die eigentliche
// Lizenzprüfung läuft über denselben Commons-Direkt-Lookup wie bei jedem
// anderen Commons-Fund (getCommonsFileInfoByTitle, siehe wikimediaCommons.ts).
// Kein API-Key nötig — dieselbe Art öffentlicher, unauthentifizierter
// Wikimedia-API wie die beiden anderen Quellen.

import { getCommonsFileInfoByTitle, type CommonsImageCandidate } from "./wikimediaCommons.ts";

const WIKIDATA_API = "https://www.wikidata.org/w/api.php";
const USER_AGENT = "KlassikMuenchenBot/1.0 (redaktionelle Bilderrecherche)";

async function fetchWikidataApi(
  params: Record<string, string>,
  // deno-lint-ignore no-explicit-any
): Promise<any | null> {
  const url = new URL(WIKIDATA_API);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  url.searchParams.set("format", "json");
  url.searchParams.set("origin", "*");
  try {
    const res = await fetch(url.toString(), { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

async function findEntityId(query: string, lang: "de" | "en"): Promise<string | null> {
  const data = await fetchWikidataApi({
    action: "wbsearchentities",
    search: query,
    language: lang,
    limit: "1",
  });
  const id = data?.search?.[0]?.id;
  return typeof id === "string" ? id : null;
}

/** P18 ("image") ist eine Standard-Eigenschaft für so gut wie jede Person/
 * Institution/jedes Bauwerk mit Foto auf Commons — der Wert ist direkt der
 * Dateiname (ohne "File:"-Präfix). */
async function getP18Filename(entityId: string): Promise<string | null> {
  const data = await fetchWikidataApi({
    action: "wbgetclaims",
    entity: entityId,
    property: "P18",
  });
  const filename = data?.claims?.P18?.[0]?.mainsnak?.datavalue?.value;
  return typeof filename === "string" ? filename : null;
}

/** Sucht `name` (optional mit Kontext, z. B. "München" gegen
 * Namensgleichheiten) auf Wikidata (erst de, dann en) und löst ein
 * gefundenes P18-Bild über Commons zu einem lizenzgeprüften Kandidaten auf.
 * Liefert null bei jedem Fehler/keinem Treffer — nie werfen, Aufrufer
 * behandeln das als "kein zusätzlicher Fallback verfügbar". */
export async function searchWikidataImage(
  name: string,
  queryContext?: string,
): Promise<CommonsImageCandidate | null> {
  const query = queryContext ? `${name} ${queryContext}` : name;
  for (const lang of ["de", "en"] as const) {
    const entityId = await findEntityId(query, lang);
    if (!entityId) continue;
    const filename = await getP18Filename(entityId);
    if (!filename) continue;
    const candidate = await getCommonsFileInfoByTitle(filename);
    if (candidate) return candidate;
  }
  return null;
}
