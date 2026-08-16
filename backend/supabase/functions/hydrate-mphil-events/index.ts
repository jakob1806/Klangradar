import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseMphilEventDetail } from "../_shared/mphilDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants } from "../_shared/eventParticipantResolution.ts";

// Dritte Quelle mit eigener Termin-Detailseiten-Pipeline nach Staatsoper und
// BRSO (Nutzeranfrage: "das sollen auch andere websites können"). mphil.de
// blockt normale Fetches nicht — kein r.jina.ai-Reader nötig. Anders als
// staatsoper.de/brso.de gibt es hier kein eigenes Eventfoto (og:image ist
// überall dasselbe generische Logo, siehe mphilDetail.ts) — der Mehrwert
// ist die Bio-Link-Rückverlinkung für Dirigent:innen/Solist:innen.
Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url")
    .ilike("website_url", "%mphil.de/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("mphil_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 3, async (event: any) => {
    try {
      const res = await fetch(event.website_url, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) return { id: event.id, error: `HTTP ${res.status}` };
      const detail = parseMphilEventDetail(await res.text(), event.website_url);
      const participantsAdded = await replaceEventParticipants(supabase, event.id, detail.participants);

      await supabase.from("events").update({
        mphil_detail_synced_at: new Date().toISOString(),
        mphil_detail_sync_error: null,
      }).eq("id", event.id);
      return { id: event.id, participantsFound: detail.participants.length, participantsAdded };
    } catch (err) {
      await supabase.from("events").update({
        mphil_detail_synced_at: new Date().toISOString(),
        mphil_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
