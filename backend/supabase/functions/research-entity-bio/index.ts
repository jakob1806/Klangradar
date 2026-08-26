// Recherchiert EINE Biografie/Beschreibung für EINE Entität und gibt sie
// zurück, OHNE sie zu speichern — bewusster Unterschied zu allen anderen
// Auto-Anreicherungs-Functions in diesem Projekt (die bei ausreichender
// Konfidenz direkt in die DB schreiben). Nutzeranfrage: "mehrere auswählen
// und mithilfe von KI nach einer Bio suchen und diese dann nacheinander
// (mit Option auf Bearbeitung) hinzufügen" — der Redakteurin muss der Text
// vor dem Übernehmen vorgelegt werden, ein biografischer Fließtext ist zu
// fehleranfällig (Namensvetter, veraltete/falsche Fakten) für blindes
// Auto-Save wie z. B. bei einem einzelnen Bool'schen Fakt.
//
// Aufruf: POST { entityType: 'person'|'ensemble'|'venue', entityId: string }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hasAnyAiProviderConfigured } from "../_shared/ai/router.ts";
import { researchBiography, type BioEntityType, type KnownFacts } from "../_shared/bioResearch.ts";

const TABLE_FOR_TYPE: Record<BioEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  venue: "venues",
};

const NAME_COLUMN_FOR_TYPE: Record<BioEntityType, string> = {
  person: "full_name",
  ensemble: "name",
  venue: "name",
};

// Zusätzliche Spalten je Entitätstyp — verbessern sowohl die Wikipedia-
// Trefferqualität (als Freitext-Kontext) als auch, für Personen, den
// deterministischen Lebensdaten-Gegencheck in bioResearch.ts.
const EXTRA_COLUMNS_FOR_TYPE: Record<BioEntityType, string> = {
  person: ", roles, instrument, nationality, birth_date, death_date",
  ensemble: ", type, founded_year",
  venue: ", venue_type, district",
};

function yearOf(dateStr: unknown): number | undefined {
  if (typeof dateStr !== "string") return undefined;
  const year = parseInt(dateStr.slice(0, 4), 10);
  return Number.isFinite(year) ? year : undefined;
}

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (!hasAnyAiProviderConfigured()) {
    return jsonResponse({ error: "Kein AI-Provider-Secret gesetzt (siehe _shared/ai/router.ts)" }, 500);
  }

  let body: { entityType?: unknown; entityId?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Ungültiger Request-Body" }, 400);
  }

  const entityType = body.entityType as BioEntityType;
  const entityId = typeof body.entityId === "string" ? body.entityId : null;
  if (!entityId || !TABLE_FOR_TYPE[entityType]) {
    return jsonResponse({ error: "entityType (person|ensemble|venue) und entityId erforderlich" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const table = TABLE_FOR_TYPE[entityType];
  const nameColumn = NAME_COLUMN_FOR_TYPE[entityType];
  const { data: entity, error: fetchError } = await supabase
    .from(table)
    .select(`${nameColumn}${EXTRA_COLUMNS_FOR_TYPE[entityType]}`)
    .eq("id", entityId)
    .maybeSingle();

  if (fetchError || !entity) {
    return jsonResponse({ error: fetchError?.message ?? "Entität nicht gefunden" }, 404);
  }

  const entityRecord = entity as unknown as Record<string, unknown>;
  const name = entityRecord[nameColumn] as string;

  // Freitext-Kontext für die Wikipedia-Suche/den LLM-Vergleich — je mehr
  // bekannte Anhaltspunkte, desto besser kann sowohl die Suche selbst als
  // auch die "confident"-Einschätzung der KI einen Namensvetter erkennen.
  const contextParts: string[] = [];
  if (entityType === "person") {
    const roles = entityRecord.roles as string[] | null;
    if (roles?.length) contextParts.push(roles.join(", "));
    if (entityRecord.instrument) contextParts.push(String(entityRecord.instrument));
    if (entityRecord.nationality) contextParts.push(String(entityRecord.nationality));
  } else if (entityType === "ensemble") {
    if (entityRecord.type) contextParts.push(String(entityRecord.type));
    if (entityRecord.founded_year) contextParts.push(`gegründet ${entityRecord.founded_year}`);
  } else {
    if (entityRecord.venue_type) contextParts.push(String(entityRecord.venue_type));
    if (entityRecord.district) contextParts.push(String(entityRecord.district));
  }
  const context = contextParts.length > 0 ? contextParts.join(", ") : null;

  const knownFacts: KnownFacts | undefined = entityType === "person"
    ? { birthYear: yearOf(entityRecord.birth_date), deathYear: yearOf(entityRecord.death_date) }
    : undefined;

  const result = await researchBiography(entityType, name, context, knownFacts);
  if (!result) {
    return jsonResponse({ found: false });
  }

  return jsonResponse({
    found: true,
    biography: result.biography,
    sourceUrl: result.sourceUrl,
    source: result.source,
  });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
