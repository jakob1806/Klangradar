// Schneller, quellenunabhängiger Biografie-Backfill für Personen.
// Anders als enrich-person-profile wartet dieser Worker nicht erst auf
// Website-/Wikipedia-Abrufe, sondern stellt dieselbe Wissensfrage, die eine
// Redaktion direkt in Gemini oder einem anderen LLM stellen würde. Er
// schreibt ausschließlich LEERE Biografien und kennzeichnet die Provenienz
// ausdrücklich als KI-Wissen ohne Webbeleg.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hasAnyAiProviderConfigured } from "../_shared/ai/router.ts";
import { researchBiographyFromKnowledge } from "../_shared/bioResearch.ts";
import { recordFieldSource } from "../_shared/provenance.ts";
import { logSystemAction } from "../_shared/systemLog.ts";

interface PersonRow {
  id: string;
  full_name: string;
  roles: string[] | null;
  instrument: string | null;
  nationality: string | null;
  birth_date: string | null;
  death_date: string | null;
}

const DEFAULT_LIMIT = 16;
const CONCURRENCY = 4;

function personContext(person: PersonRow, eventContext: string[]): string | null {
  const parts: string[] = [];
  if (person.roles?.length) parts.push(`Rollen: ${person.roles.join(", ")}`);
  if (person.instrument) parts.push(`Instrument/Stimmfach: ${person.instrument}`);
  if (person.nationality) parts.push(`Nationalität: ${person.nationality}`);
  if (person.birth_date) parts.push(`Geburtsdatum: ${person.birth_date}`);
  if (person.death_date) parts.push(`Sterbedatum: ${person.death_date}`);
  if (eventContext.length) parts.push(`Verknüpfte Programme: ${eventContext.join(" | ")}`);
  return parts.length ? parts.join("; ") : null;
}

Deno.serve(async (req) => {
  if (!hasAnyAiProviderConfigured()) {
    return jsonResponse({ error: "Kein AI-Provider-Secret gesetzt" }, 500);
  }

  let body: { limit?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0
    ? Math.min(body.limit, 40)
    : DEFAULT_LIMIT;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const { data, error } = await supabase.rpc("claim_person_ai_biographies", {
    p_limit: limit,
  });
  if (error) return jsonResponse({ error: error.message }, 500);
  const persons = (Array.isArray(data) ? data : []) as PersonRow[];

  let generated = 0;
  let notKnown = 0;
  const errors: string[] = [];

  async function processPerson(person: PersonRow) {
    try {
      const { data: appearances } = await supabase
        .from("event_participants")
        .select("role, events(title)")
        .eq("person_id", person.id)
        .limit(4);
      type AppearanceRow = { role: string | null; events: Array<{ title: string }> | { title: string } | null };
      const eventContext = ((appearances ?? []) as unknown as AppearanceRow[]).map((row) => {
        const event = Array.isArray(row.events) ? row.events[0] : row.events;
        return `${event?.title ?? "Veranstaltung"}${row.role ? ` (${row.role})` : ""}`;
      });
      const result = await researchBiographyFromKnowledge(
        "person",
        person.full_name,
        personContext(person, eventContext),
      );
      const biography = result?.biography?.trim() ?? "";
      if (!biography || biography.length < 80) {
        notKnown++;
        await supabase.from("persons").update({
          ai_biography_status: "not_known",
          ai_biography_checked_at: new Date().toISOString(),
          ai_biography_error: null,
        }).eq("id", person.id);
        return;
      }

      const { data: updated, error: updateError } = await supabase
        .from("persons")
        .update({
          biography_de: biography,
          ai_biography_status: "generated",
          ai_biography_checked_at: new Date().toISOString(),
          ai_biography_error: null,
        })
        .eq("id", person.id)
        // Die Queue behandelt neben NULL auch historisch gespeicherte leere
        // Strings als fehlend. Deshalb muss der atomare Schreibschutz beide
        // Fälle zulassen; nur echte redaktionelle Texte dürfen einen
        // zwischenzeitlich fertig gewordenen KI-Lauf blockieren.
        .or("biography_de.is.null,biography_de.eq.")
        .select("id")
        .maybeSingle();
      if (updateError) throw new Error(updateError.message);
      if (!updated) return; // inzwischen redaktionell befüllt
      generated++;
      await recordFieldSource(supabase, {
        entityType: "person",
        entityId: person.id,
        fieldName: "biography_de",
        sourceUrl: null,
        sourceName: "KI-Wissen (automatische Hintergrundrecherche, ohne Webabruf)",
        confidence: "likely",
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push(`„${person.full_name}“: ${message}`);
      await supabase.from("persons").update({
        ai_biography_status: "error",
        ai_biography_checked_at: new Date().toISOString(),
        ai_biography_error: message.slice(0, 1000),
      }).eq("id", person.id);
    }
  }

  for (let offset = 0; offset < persons.length; offset += CONCURRENCY) {
    await Promise.all(persons.slice(offset, offset + CONCURRENCY).map(processPerson));
  }

  await logSystemAction(supabase, "persons", null, "ai_biography_background_batch", {
    claimed: persons.length,
    generated,
    notKnown,
    errorCount: errors.length,
  });

  return jsonResponse({
    processed: persons.length,
    generated,
    notKnown,
    errorCount: errors.length,
    errors: errors.slice(0, 10),
  });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
