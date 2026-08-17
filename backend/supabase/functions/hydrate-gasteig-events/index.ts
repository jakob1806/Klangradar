import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseGasteigEventDetail } from "../_shared/gasteigDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants } from "../_shared/eventParticipantResolution.ts";

// Vierte Quelle mit eigener Termin-Detailseiten-Pipeline nach Staatsoper,
// BRSO und Münchner Philharmoniker (Nutzeranfrage: "das sollen auch andere
// websites können"). gasteig.de blockt normale Fetches nicht. Anders als
// die anderen drei Quellen liefert diese Pipeline kein Eventfoto (bereits
// über die bestehende coverImageDetection.ts-Kaskade abgedeckt, siehe
// gasteigDetail.ts) — nur die strukturierte Besetzung.
Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url")
    .ilike("website_url", "%gasteig.de/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("gasteig_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 3, async (event: any) => {
    try {
      const res = await fetch(event.website_url, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) return { id: event.id, error: `HTTP ${res.status}` };
      const detail = parseGasteigEventDetail(await res.text());
      const participantsAdded = await replaceEventParticipants(supabase, event.id, detail.participants);

      await supabase.from("events").update({
        gasteig_detail_synced_at: new Date().toISOString(),
        gasteig_detail_sync_error: null,
      }).eq("id", event.id);
      return { id: event.id, participantsFound: detail.participants.length, participantsAdded };
    } catch (err) {
      await supabase.from("events").update({
        gasteig_detail_synced_at: new Date().toISOString(),
        gasteig_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
