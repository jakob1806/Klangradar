import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseBrsoEventDetail } from "../_shared/brsoDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants } from "../_shared/eventParticipantResolution.ts";

// Zweite Quelle mit eigener Termin-Detailseiten-Pipeline nach Staatsoper
// (Nutzeranfrage: "das sollen auch andere websites können"). brso.de blockt
// normale Fetches NICHT (anders als staatsoper.de) — kein r.jina.ai-Reader
// nötig, siehe brsoDetail.ts für die live verifizierte Seitenstruktur.
import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url,image_urls")
    .ilike("website_url", "%brso.de/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("brso_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 3, async (event: any) => {
    try {
      const res = await fetch(event.website_url, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) return { id: event.id, error: `HTTP ${res.status}` };
      const detail = parseBrsoEventDetail(await res.text());

      let imageAdded = false;
      if (detail.imageUrl) {
        // Gleiches Vorgehen wie hydrate-staatsoper-events: Bestands-Backfill
        // ohne WASM-Bildkonvertierung, image_urls ist der produktive
        // Lesepfad aller Apps.
        await supabase.from("events").update({
          image_urls: [detail.imageUrl, ...(event.image_urls ?? []).filter((u: string) => u !== detail.imageUrl)],
        }).eq("id", event.id);
        imageAdded = true;
      }

      // BRSO-Detailseiten liefern (anders als Staatsoper) kein strukturiertes
      // Programm mit Werktiteln, nur die Besetzung — event_works bleibt
      // deshalb unangetastet.
      const participantsAdded = await replaceEventParticipants(supabase, event.id, detail.participants);

      await supabase.from("events").update({
        brso_detail_synced_at: new Date().toISOString(),
        brso_detail_sync_error: null,
      }).eq("id", event.id);
      return { id: event.id, imageAdded, participantsFound: detail.participants.length, participantsAdded };
    } catch (err) {
      await supabase.from("events").update({
        brso_detail_synced_at: new Date().toISOString(),
        brso_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
