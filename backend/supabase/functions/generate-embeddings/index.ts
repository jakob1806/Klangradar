// Berechnet Embeddings für Events ohne embedding (Architektur-Dokument
// Abschnitt 2.2/11) — Grundlage für find_similar_events_by_embedding()
// (20260819000009_embeddings.sql). Gleiches Batch-Muster wie
// enrich-event-references: POST { limit? } verarbeitet bis zu `limit`
// (Default 20) Events pro Aufruf, mehrfacher Aufruf nötig für alle Events
// (Edge Function Zeitlimit).
//
// Text für das Embedding: Titel + Beschreibung + (falls vorhanden) Venue-
// Name — bewusst kein Volltext aus Programmpunkten/Mitwirkenden, um das
// Embedding auf "worum geht es thematisch" statt auf einzelne Namen zu
// fokussieren (Namen sind über die bestehenden Fuzzy-Match-RPCs bereits
// abgedeckt).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { embedText } from "../_shared/ai/embeddings.ts";

interface EventRow {
  id: string;
  title: string;
  description_de: string | null;
  venues: { name: string } | null;
}

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (!Deno.env.get("GEMINI_API_KEY")) {
    return new Response(JSON.stringify({ error: "GEMINI_API_KEY nicht gesetzt" }), { status: 500 });
  }

  let body: { limit?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0 ? Math.min(body.limit, 50) : 20;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: candidates, error: fetchError } = await supabase
    .from("events")
    .select("id, title, description_de, venues(name)")
    .eq("status", "scheduled")
    .is("embedding", null)
    .order("id")
    .limit(limit)
    .returns<EventRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!candidates || candidates.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine Events ohne Embedding mehr übrig." }));
  }

  let embedded = 0;
  const errors: string[] = [];

  for (const event of candidates) {
    const text = [event.title, event.description_de, event.venues?.name].filter(Boolean).join("\n");
    const vector = await embedText(text);
    if (!vector) {
      errors.push(`"${event.title}": Embedding-Aufruf fehlgeschlagen`);
      continue;
    }

    const { error: updateError } = await supabase.from("events").update({ embedding: vector }).eq("id", event.id);
    if (updateError) {
      errors.push(`"${event.title}": ${updateError.message}`);
      continue;
    }
    embedded++;
  }

  return new Response(
    JSON.stringify({
      processed: candidates.length,
      embedded,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
