import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseStaatsoperDetail } from "../_shared/staatsoperDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants, resolveComposer, resolveWork } from "../_shared/eventParticipantResolution.ts";

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url,image_urls,primary_image_id,start_datetime,program_extraction_status")
    .ilike("website_url", "%staatsoper.de/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("staatsoper_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 2, async (event: any) => {
    try {
      const reader = await fetchReaderWithRetry(event.website_url);
      if (!reader.ok) return { id: event.id, error: `reader HTTP ${reader.status}` };
      const detail = parseStaatsoperDetail(await reader.text());
      let imageAdded = false;
      if (detail.imageUrl) {
        // Bestands-Backfill bewusst ohne WASM-Bildkonvertierung: hunderte
        // Events in einem Lauf überschreiten sonst das Edge-Compute-Limit.
        // image_urls ist der produktive Lesepfad aller Apps; neue Importe
        // verarbeiten dasselbe Bild weiterhin über ingest-source.
        await supabase.from("events").update({
          image_urls: [detail.imageUrl, ...(event.image_urls ?? []).filter((u: string) => u !== detail.imageUrl)],
        }).eq("id", event.id);
        imageAdded = true;
      }

      // Die offizielle terminbezogene Besetzung ist hier maßgeblich. Alte
      // KI-Verknüpfungen enthielten nachweislich Regie-Namen und Personen
      // anderer Termine; replaceEventParticipants() ersetzt deshalb
      // vollständig, aber nur wenn tatsächlich Kandidaten geparst wurden —
      // nie bei einer unvollständig geladenen Seite (detail.participants
      // bleibt in dem Fall leer, siehe staatsoperDetail.ts).
      const participantsAdded = await replaceEventParticipants(supabase, event.id, detail.participants);
      let worksAdded = 0;
      if (detail.works.length > 0) {
        await supabase.from("event_works").delete().eq("event_id", event.id);
        for (const work of detail.works) {
          const composerId = work.composerName ? await resolveComposer(supabase, work.composerName) : null;
          const workId = await resolveWork(supabase, work.title, composerId);
          if (!workId) continue;
          const { error: workError } = await supabase.from("event_works").insert({
            event_id: event.id, work_id: workId, position: work.position, after_intermission: false,
          });
          if (!workError) worksAdded++;
        }
      }
      await supabase.from("events").update({
        staatsoper_detail_synced_at: new Date().toISOString(),
        staatsoper_detail_sync_error: null,
        program_extraction_status: detail.works.length > 0 ? "complete" : event.program_extraction_status,
      }).eq("id", event.id);
      return { id: event.id, imageAdded, participantsFound: detail.participants.length, participantsAdded, worksFound: detail.works.length, worksAdded };
    } catch (err) {
      // Fehlerhafte Einzelzeile darf die Queue nicht dauerhaft am Anfang
      // blockieren. Sie wird als versucht markiert und über das Fehlerfeld
      // gezielt in einem späteren Retry-Pass zurückgesetzt.
      await supabase.from("events").update({
        staatsoper_detail_synced_at: new Date().toISOString(),
        staatsoper_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});

async function fetchReaderWithRetry(pageUrl: string): Promise<Response> {
  let response = await fetch(`https://r.jina.ai/${pageUrl}`, { headers: { "User-Agent": USER_AGENT } });
  for (let attempt = 1; response.status === 429 && attempt <= 4; attempt++) {
    const retryAfter = Math.min(Number(response.headers.get("retry-after") ?? 0) || attempt * 3, 15);
    await new Promise((resolve) => setTimeout(resolve, retryAfter * 1000));
    response = await fetch(`https://r.jina.ai/${pageUrl}`, { headers: { "User-Agent": USER_AGENT } });
  }
  return response;
}
