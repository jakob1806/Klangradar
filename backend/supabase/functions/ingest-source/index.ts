// Supabase Edge Function: manueller/geplanter Ingestion-Lauf für eine
// einzelne Quelle. Aufgerufen mit { source_id } — vom Admin-Dashboard
// "Jetzt ausführen"-Button und vom run-all-sources-Orchestrator (der die
// Kernlogik allerdings in-process über core.ts aufruft, nicht per HTTP).
//
// SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY werden von der Supabase-
// Runtime automatisch in jede Edge Function injiziert — kein manuell
// hinterlegtes Secret nötig. service_role, weil dieser Lauf nicht an eine
// eingeloggte Nutzersession gebunden ist und RLS bewusst umgehen muss, um
// events/ingestion_runs/duplicate_candidates zu schreiben.
//
// Die eigentliche Ingestion-Logik lebt in core.ts, NICHT hier — core.ts hat
// bewusst KEIN top-level Deno.serve(), damit run-all-sources sie importieren
// kann, ohne diesen Datei-eigenen Handler als Nebeneffekt mit zu registrieren
// (siehe core.ts-Kommentar für den Bug, den das verursacht hat).

// esm.sh (not npm:) — this is the pattern Supabase's own Edge Function
// docs/templates use, and the one most likely to be pre-cached/validated
// in the actual Supabase Edge Runtime rather than vanilla Deno.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { runIngestion } from "./core.ts";

Deno.serve(async (req) => {
  let body: { source_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid JSON body" }, 400);
  }

  const sourceId = typeof body.source_id === "string" ? body.source_id : null;
  if (!sourceId) {
    return jsonResponse({ error: "source_id is required" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { httpStatus, body: responseBody } = await runIngestion(supabase, sourceId);
  return jsonResponse(responseBody, httpStatus);
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
