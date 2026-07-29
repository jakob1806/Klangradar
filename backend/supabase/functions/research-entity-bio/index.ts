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
import { researchBiography, type BioEntityType } from "../_shared/bioResearch.ts";

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

Deno.serve(async (req) => {
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
    .select(`${nameColumn}${entityType === "person" ? ", roles" : ""}`)
    .eq("id", entityId)
    .maybeSingle();

  if (fetchError || !entity) {
    return jsonResponse({ error: fetchError?.message ?? "Entität nicht gefunden" }, 404);
  }

  const entityRecord = entity as unknown as Record<string, unknown>;
  const name = entityRecord[nameColumn] as string;
  const roles = entityType === "person" ? (entityRecord.roles as string[] | null) : null;
  const context = roles && roles.length > 0 ? roles.join(", ") : null;

  const result = await researchBiography(entityType, name, context);
  if (!result) {
    return jsonResponse({ found: false });
  }

  return jsonResponse({ found: true, biography: result.biography, sourceUrl: result.sourceUrl });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
