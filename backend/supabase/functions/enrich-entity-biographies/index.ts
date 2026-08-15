// Automatische KI-Biografien für Ensembles und Venues. Der schnelle
// Wissenspfad ist derselbe wie bei Personen; bestehende redaktionelle Texte
// werden niemals überschrieben.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hasAnyAiProviderConfigured } from "../_shared/ai/router.ts";
import { researchBiographyFromKnowledge } from "../_shared/bioResearch.ts";
import { recordFieldSource } from "../_shared/provenance.ts";
import { logSystemAction } from "../_shared/systemLog.ts";

type EntityType = "ensemble" | "venue";

interface EntityRow {
  id: string;
  name: string;
  type?: string | null;
  founded_year?: number | null;
  member_count?: number | null;
  address_city?: string | null;
  venue_type?: string | null;
  capacity?: number | null;
}

const CONFIG = {
  ensemble: {
    table: "ensembles",
    claimRpc: "claim_ensemble_ai_biographies",
    bioColumn: "description_de",
  },
  venue: {
    table: "venues",
    claimRpc: "claim_venue_ai_biographies",
    bioColumn: "description_de",
  },
} as const;

const DEFAULT_LIMIT = 8;
const CONCURRENCY = 3;

function entityContext(type: EntityType, entity: EntityRow, events: string[]): string | null {
  const parts: string[] = [];
  if (type === "ensemble") {
    if (entity.type) parts.push(`Ensembletyp: ${entity.type}`);
    if (entity.founded_year) parts.push(`Gründungsjahr: ${entity.founded_year}`);
    if (entity.member_count) parts.push(`Mitglieder: ${entity.member_count}`);
  } else {
    if (entity.venue_type) parts.push(`Spielstättentyp: ${entity.venue_type}`);
    if (entity.address_city) parts.push(`Ort: ${entity.address_city}`);
    if (entity.capacity) parts.push(`Kapazität: ${entity.capacity}`);
  }
  if (events.length) parts.push(`Verknüpfte Veranstaltungen: ${events.join(" | ")}`);
  return parts.length ? parts.join("; ") : null;
}

Deno.serve(async (req) => {
  if (!hasAnyAiProviderConfigured()) return json({ error: "Kein AI-Provider-Secret gesetzt" }, 500);
  let body: { type?: unknown; limit?: unknown; entityId?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    // Standardwerte verwenden.
  }
  if (body.type !== "venue" && body.type !== "ensemble") {
    return json({ error: "type muss ensemble oder venue sein" }, 400);
  }
  const entityType: EntityType = body.type;
  const limit = typeof body.limit === "number" && body.limit > 0 ? Math.min(body.limit, 20) : DEFAULT_LIMIT;
  const config = CONFIG[entityType];
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const entityId = typeof body.entityId === "string" && /^[0-9a-f-]{36}$/i.test(body.entityId)
    ? body.entityId
    : null;
  let entities: EntityRow[];
  if (entityId) {
    const { data: target, error: targetError } = await supabase.from(config.table).select("*")
      .eq("id", entityId).maybeSingle();
    if (targetError) return json({ error: targetError.message }, 500);
    if (!target || String(target[config.bioColumn] ?? "").trim()) {
      return json({ processed: 0, generated: 0, notKnown: 0, errorCount: 0, errors: [] });
    }
    await supabase.from(config.table).update({
      ai_biography_status: "processing",
      ai_biography_checked_at: new Date().toISOString(),
      ai_biography_error: null,
    }).eq("id", entityId);
    entities = [target as EntityRow];
  } else {
    const { data, error } = await supabase.rpc(config.claimRpc, { p_limit: limit });
    if (error) return json({ error: error.message }, 500);
    entities = (data ?? []) as EntityRow[];
  }
  let generated = 0;
  let notKnown = 0;
  const errors: string[] = [];

  async function processEntity(entity: EntityRow) {
    try {
      const eventsQuery = entityType === "ensemble"
        ? supabase.from("event_participants").select("events(title)").eq("ensemble_id", entity.id).limit(4)
        : supabase.from("events").select("title").eq("venue_id", entity.id).limit(4);
      const { data: linkedRows } = await eventsQuery;
      const events = ((linkedRows ?? []) as Array<Record<string, unknown>>).map((row) => {
        if (entityType === "venue") return String(row.title ?? "");
        const related = Array.isArray(row.events) ? row.events[0] : row.events;
        return typeof related === "object" && related ? String((related as { title?: unknown }).title ?? "") : "";
      }).filter(Boolean);

      const result = await researchBiographyFromKnowledge(
        entityType,
        entity.name,
        entityContext(entityType, entity, events),
      );
      const biography = result?.biography?.trim() ?? "";
      if (biography.length < 80) {
        notKnown++;
        await supabase.from(config.table).update({
          ai_biography_status: "not_known",
          ai_biography_checked_at: new Date().toISOString(),
          ai_biography_error: null,
        }).eq("id", entity.id);
        return;
      }

      const { data: updated, error: updateError } = await supabase.from(config.table).update({
        [config.bioColumn]: biography,
        ai_biography_status: "generated",
        ai_biography_checked_at: new Date().toISOString(),
        ai_biography_error: null,
      }).eq("id", entity.id).or(`${config.bioColumn}.is.null,${config.bioColumn}.eq.`).select("id").maybeSingle();
      if (updateError) throw new Error(updateError.message);
      if (!updated) return;
      generated++;
      await recordFieldSource(supabase, {
        entityType,
        entityId: entity.id,
        fieldName: config.bioColumn,
        sourceUrl: null,
        sourceName: "KI-Wissen (automatische Hintergrundrecherche, ohne Webabruf)",
        confidence: "likely",
      });
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : String(cause);
      errors.push(`„${entity.name}“: ${message}`);
      await supabase.from(config.table).update({
        ai_biography_status: "error",
        ai_biography_checked_at: new Date().toISOString(),
        ai_biography_error: message.slice(0, 1000),
      }).eq("id", entity.id);
    }
  }

  for (let offset = 0; offset < entities.length; offset += CONCURRENCY) {
    await Promise.all(entities.slice(offset, offset + CONCURRENCY).map(processEntity));
  }
  await logSystemAction(supabase, config.table, null, "ai_biography_background_batch", {
    entityType,
    claimed: entities.length,
    generated,
    notKnown,
    errorCount: errors.length,
  });
  return json({ processed: entities.length, generated, notKnown, errorCount: errors.length, errors: errors.slice(0, 10) });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
