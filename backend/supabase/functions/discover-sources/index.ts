// Architektur-Dokument Abschnitt 9: "discover-sources als eigene Function,
// nicht in enrich-event-references mitlaufend" — bewusste Trennung, weil
// enrich-event-references einen bekannten Kandidaten (einen im Event-Text
// genannten Namen) anreichert, während diese Function AKTIV nach bisher
// unbekannten Veranstaltern/Institutionen sucht, die als künftige
// sources-Kandidaten infrage kämen. Unterschiedliches Risikoprofil: eine
// aktive Suche kann viel mehr Rauschen/Fehltreffer produzieren als das
// Bestätigen eines im Kontext bereits genannten Namens.
//
// Bewusst NUR manuell auslösbar (kein Cron-Eintrag) — jeder Lauf kostet
// echte Tavily-/LLM-Credits, und die Ergebnisqualität hängt stark vom
// Suchbegriff ab. Legt NICHTS automatisch in sources/organizers an,
// sondern ausschließlich entity_candidates(entity_type='organizer') zur
// redaktionellen Freigabe (identisches Muster wie
// enrich-event-references/flagEntityCandidate) — der bestehende
// Kandidaten-Review-Flow (admin/entity-candidates) deckt damit auch
// Discovery-Funde ab, statt einen zweiten Freigabe-Mechanismus zu
// erfinden. Aus einem freigegebenen Kandidaten macht der Admin danach ganz
// normal über /sources/new (+ probe-source zur Typ-Erkennung) eine echte
// Quelle - das Anlegen einer sources-Zeile bleibt bewusst ein manueller
// Schritt (siehe Architektur-Dokument Abschnitt 5).
//
// Aufruf: POST { query: string, region_id?: string } — query ist der
// Freitext-Suchbegriff (z.B. "klassische Konzerte Kammermusik München
// Veranstalter"), region_id verlinkt gefundene Kandidaten optional mit
// einer bekannten Region für spätere Filterung im Review.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { searchTavily, type TavilyResult } from "../_shared/tavily.ts";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";

const MAX_SEARCH_RESULTS = 8;
const FUZZY_AUTO_SKIP_THRESHOLD = 0.85; // >= das gilt als "kennen wir schon", kein Kandidat nötig
const FUZZY_FLAG_THRESHOLD = 0.5;

interface CandidateOrganizer {
  name: string;
  website_url: string | null;
  reasoning: string;
}

const EXTRACTION_FUNCTION: AiFunctionDeclaration = {
  name: "extract_organizer_candidates",
  description:
    "Extrahiert aus Websuche-Ergebnissen eine Liste von Veranstaltern/Institutionen für klassische Musik " +
    "(Konzertreihen, Kammermusik-Vereine, Kirchenmusik, kleine Festivals) — keine einzelnen Konzert-Events, " +
    "keine großen bereits etablierten Häuser (Oper, Philharmonie), sondern Institutionen, die eine eigene " +
    "Website/einen eigenen Spielplan haben könnten.",
  parameters: {
    type: "object",
    properties: {
      candidates: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string", description: "Name des Veranstalters/der Institution" },
            website_url: { type: ["string", "null"], description: "Offizielle Website, falls erkennbar" },
            reasoning: { type: "string", description: "Ein Satz: warum das ein plausibler neuer Veranstalter ist" },
          },
          required: ["name", "reasoning"],
        },
      },
    },
    required: ["candidates"],
  },
};

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  let body: { query?: unknown; region_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid JSON body" }, 400);
  }

  const query = typeof body.query === "string" ? body.query.trim() : null;
  if (!query) return jsonResponse({ error: "query is required" }, 400);
  const regionId = typeof body.region_id === "string" ? body.region_id : null;

  if (!hasAnyAiProviderConfigured()) {
    return jsonResponse({ error: "kein AI-Provider konfiguriert (siehe _shared/ai/router.ts)" }, 500);
  }
  const tavilyKey = Deno.env.get("TAVILY_API_KEY");
  if (!tavilyKey) {
    return jsonResponse({ error: "TAVILY_API_KEY nicht gesetzt" }, 500);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const searchResults = await searchTavily(tavilyKey, query, MAX_SEARCH_RESULTS);
  if (!searchResults || searchResults.length === 0) {
    return jsonResponse({ query, candidates_found: 0, created: 0, skipped_known: 0, note: "keine Suchtreffer" });
  }

  const extracted = await extractCandidates(query, searchResults);
  if (!extracted || extracted.length === 0) {
    return jsonResponse({
      query,
      candidates_found: 0,
      created: 0,
      skipped_known: 0,
      note: "LLM-Extraktion lieferte keine Kandidaten",
    });
  }

  let created = 0;
  let skippedKnown = 0;
  let skippedDuplicatePending = 0;

  for (const candidate of extracted) {
    const { data: existing } = await supabase
      .from("organizers")
      .select("id")
      .ilike("name", candidate.name)
      .maybeSingle();
    if (existing) {
      skippedKnown++;
      continue;
    }

    const { data: fuzzyMatches } = await supabase.rpc("find_matching_organizer", { p_name: candidate.name });
    const bestMatch = fuzzyMatches?.[0] as { id: string; name: string; similarity: number } | undefined;
    if (bestMatch && bestMatch.similarity >= FUZZY_AUTO_SKIP_THRESHOLD) {
      skippedKnown++;
      continue;
    }

    const { data: existingCandidate } = await supabase
      .from("entity_candidates")
      .select("id")
      .eq("entity_type", "organizer")
      .ilike("name", candidate.name)
      .eq("status", "pending")
      .maybeSingle();
    if (existingCandidate) {
      skippedDuplicatePending++;
      continue;
    }

    const { error } = await supabase.from("entity_candidates").insert({
      entity_type: "organizer",
      name: candidate.name,
      source_url: candidate.website_url,
      discovery_context: {
        source: "discover-sources",
        search_query: query,
        region_id: regionId,
        reasoning: candidate.reasoning,
        ...(bestMatch && bestMatch.similarity >= FUZZY_FLAG_THRESHOLD
          ? { possible_match: { id: bestMatch.id, name: bestMatch.name, similarity: bestMatch.similarity } }
          : {}),
      },
    });
    if (error) {
      console.error(`discover-sources: insert failed for "${candidate.name}": ${error.message}`);
      continue;
    }
    created++;
  }

  return jsonResponse({
    query,
    candidates_found: extracted.length,
    created,
    skipped_known: skippedKnown,
    skipped_duplicate_pending: skippedDuplicatePending,
  });
});

async function extractCandidates(
  query: string,
  results: TavilyResult[],
): Promise<CandidateOrganizer[] | null> {
  const context = results
    .map((r, i) => `[${i + 1}] ${r.title}\nURL: ${r.url}\n${r.content}`)
    .join("\n\n");

  const system =
    "Du analysierst Websuche-Ergebnisse, um neue Veranstalter klassischer Musik zu identifizieren, die " +
    "noch nicht als Datenquelle erfasst sind. Sei konservativ: nur eindeutig als Institution/Reihe erkennbare " +
    "Treffer aufnehmen, keine Einzel-Konzerttermine, keine Presseartikel über bereits bekannte große Häuser.";
  const user = `Suchanfrage: "${query}"\n\nErgebnisse:\n\n${context}`;

  const result = await callAiFunction(system, user, EXTRACTION_FUNCTION);
  if (!result) return null;

  const candidates = result.args.candidates;
  if (!Array.isArray(candidates)) return null;

  return candidates
    .filter((c): c is Record<string, unknown> => c != null && typeof c === "object")
    .map((c) => ({
      name: String(c.name ?? "").trim(),
      website_url: typeof c.website_url === "string" && c.website_url.trim() ? c.website_url.trim() : null,
      reasoning: typeof c.reasoning === "string" ? c.reasoning : "",
    }))
    .filter((c) => c.name.length > 0);
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
