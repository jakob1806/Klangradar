// Websuche über Geminis "Grounding with Google Search"-Tool statt einer
// separaten Such-API — auf Nutzervorschlag, nachdem sowohl Tavily
// (Gratiskontingent ausgeschöpft) als auch die Google Custom Search JSON
// API (die Funktion "auf das gesamte Web durchsuchen" wurde von Google für
// Programmable Search Engine eingestellt) nicht mehr nutzbar waren.
// Braucht keinen zusätzlichen Key — nutzt denselben GEMINI_API_KEY, der in
// diesem Projekt schon für generate-embeddings/enrich-event-references
// gesetzt ist.
//
// Modell: dasselbe "gemini-flash-lite-latest" wie _shared/ai/providers/
// gemini.ts (eigener, großzügigerer Kontingent-Bucket als das volle
// Flash-Modell, siehe dortiger Kommentar) — Grounding-Anfragen laufen
// unter demselben Modell-Kontingent.
//
// WICHTIG (Kostenaspekt, da explizit gewünscht: nichts zahlen): Grounding
// mit Google Search hat bei Gemini ein separates Tageskontingent an
// kostenlosen Anfragen, danach wird es pro 1000 Anfragen abgerechnet.
// Das hier genutzte Volumen (siehe EVENT_URL_DISCOVERY_LIMIT in
// enrich-entity-images/index.ts, wenige Anfragen pro 15-Minuten-Lauf)
// sollte weit darunter bleiben, aber im Gegensatz zu einer reinen
// Text-Generierung ohne Tools ist das nicht mit 100%iger Sicherheit
// unabhängig von Googles aktueller Preistabelle kostenlos — bei
// Auffälligkeiten (z. B. 429/Kostenwarnung) prüfen, ob das Kontingent
// erreicht wurde.
//
// Die Antwort liefert unter groundingMetadata.groundingChunks[].web.uri
// strukturiert die tatsächlich für die Suche herangezogenen Quellen-URLs
// — das wird hier direkt ausgelesen, kein Freitext-Parsing der von Gemini
// generierten Antwort nötig.

const GEMINI_MODEL = "gemini-flash-lite-latest";
const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

export interface GeminiGroundedResult {
  url: string;
  title: string | null;
}

export interface GeminiGroundedResearch {
  text: string;
  sources: GeminiGroundedResult[];
  searchQueries: string[];
}

/** Lässt Gemini die Webrecherche selbst durchführen und behält – anders als
 * searchViaGeminiGrounding() – auch die auf Basis der Google-Treffer
 * erzeugte, belegte Rechercheantwort. Das ist für redaktionelle Fragen
 * wichtig: Ein bloßer URL-Fund plus eigener fetchPageText kann an
 * robots.txt, JavaScript-Seiten oder Paywalls scheitern, obwohl Gemini den
 * Suchtreffer bereits lesen und zusammenfassen konnte. */
export async function researchViaGeminiGrounding(
  apiKey: string,
  prompt: string,
): Promise<GeminiGroundedResearch | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);
  let res: Response;
  try {
    res = await fetch(`${GEMINI_API_BASE}/${GEMINI_MODEL}:generateContent`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        tools: [{ google_search: {} }],
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.1 },
      }),
      signal: controller.signal,
    });
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
  if (!res.ok) return null;
  // deno-lint-ignore no-explicit-any
  let data: any;
  try { data = await res.json(); } catch { return null; }
  const candidate = data?.candidates?.[0];
  const text = Array.isArray(candidate?.content?.parts)
    // deno-lint-ignore no-explicit-any
    ? candidate.content.parts.map((p: any) => typeof p?.text === "string" ? p.text : "").join("\n").trim()
    : "";
  const chunks = candidate?.groundingMetadata?.groundingChunks;
  const sources: GeminiGroundedResult[] = Array.isArray(chunks)
    // deno-lint-ignore no-explicit-any
    ? chunks.filter((c: any) => typeof c?.web?.uri === "string").map((c: any) => ({
      url: c.web.uri as string,
      title: typeof c.web.title === "string" ? c.web.title : null,
    }))
    : [];
  const searchQueries = Array.isArray(candidate?.groundingMetadata?.webSearchQueries)
    ? candidate.groundingMetadata.webSearchQueries.filter((q: unknown): q is string => typeof q === "string")
    : [];
  if (!text && sources.length === 0) return null;
  return { text, sources: [...new Map(sources.map((s) => [s.url, s])).values()], searchQueries };
}

/** Führt `query` über Geminis Google-Search-Grounding aus und gibt die
 * tatsächlich zitierten Quellen-URLs zurück (nicht die generierte
 * Textantwort), oder null bei jedem Fehler (Netzwerk, HTTP-Fehler,
 * fehlendes groundingMetadata) — Aufrufer behandeln null wie "keine
 * Anreicherung möglich", kein Werfen. */
export async function searchViaGeminiGrounding(
  apiKey: string,
  query: string,
): Promise<GeminiGroundedResult[] | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000);

  let res: Response;
  try {
    res = await fetch(`${GEMINI_API_BASE}/${GEMINI_MODEL}:generateContent`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        tools: [{ google_search: {} }],
        contents: [{ role: "user", parts: [{ text: query }] }],
      }),
      signal: controller.signal,
    });
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
  if (!res.ok) return null;

  // deno-lint-ignore no-explicit-any
  let data: any;
  try {
    data = await res.json();
  } catch {
    return null;
  }

  const chunks = data?.candidates?.[0]?.groundingMetadata?.groundingChunks;
  if (!Array.isArray(chunks)) return [];

  return chunks
    // deno-lint-ignore no-explicit-any
    .filter((c: any) => c?.web?.uri && typeof c.web.uri === "string")
    // deno-lint-ignore no-explicit-any
    .map((c: any) => ({ url: c.web.uri as string, title: typeof c.web.title === "string" ? c.web.title : null }));
}
