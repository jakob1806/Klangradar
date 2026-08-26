import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseMkoEventDetail } from "../_shared/mkoDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants } from "../_shared/eventParticipantResolution.ts";

// Fünfte Quelle mit eigener Termin-Detailseiten-Pipeline nach Staatsoper,
// BRSO, Münchner Philharmoniker und Gasteig (Nutzeranfrage: "das sollen
// auch andere websites können"). m-k-o.eu blockt normale Fetches nicht.
// Kein Eventfoto nötig (bereits über die bestehende
// coverImageDetection.ts-Kaskade abgedeckt, siehe mkoDetail.ts) — nur die
// strukturierte Besetzung.
import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url")
    .ilike("website_url", "%m-k-o.eu/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("mko_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 3, async (event: any) => {
    try {
      const res = await fetch(event.website_url, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) return { id: event.id, error: `HTTP ${res.status}` };
      const detail = parseMkoEventDetail(await res.text());
      const participantsAdded = await replaceEventParticipants(supabase, event.id, detail.participants);

      await supabase.from("events").update({
        mko_detail_synced_at: new Date().toISOString(),
        mko_detail_sync_error: null,
      }).eq("id", event.id);
      return { id: event.id, participantsFound: detail.participants.length, participantsAdded };
    } catch (err) {
      await supabase.from("events").update({
        mko_detail_synced_at: new Date().toISOString(),
        mko_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
