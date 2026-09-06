import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseWienerPhilharmonikerDetail } from "../_shared/wienerPhilharmonikerDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants, resolveComposer, resolveWork } from "../_shared/eventParticipantResolution.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";

// Dritte venue-spezifische Hydration-Pipeline der Multi-City-Erweiterung,
// zweite für Wien (Nutzeranfrage: "mache venue-spezifische Hydration-Parser
// wie bei München"). Einzige der drei neuen Quellen mit echtem, strukturier-
// tem Werkprogramm (siehe _shared/wienerPhilharmonikerDetail.ts) — deshalb
// wie hydrate-staatsoper-events sowohl event_works als auch
// event_participants.
Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url,program_extraction_status")
    .ilike("website_url", "%wienerphilharmoniker.at/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("wienerphilharmoniker_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 2, async (event: { id: string; title: string; website_url: string; program_extraction_status: string }) => {
    try {
      const res = await fetch(event.website_url, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) return { id: event.id, error: `HTTP ${res.status}` };
      const detail = parseWienerPhilharmonikerDetail(await res.text());

      const participantsAdded = await replaceEventParticipants(supabase, event.id,
        detail.participants.map((p) => ({ name: p.name, profileUrl: null, role: p.role, type: p.type })));

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
        wienerphilharmoniker_detail_synced_at: new Date().toISOString(),
        wienerphilharmoniker_detail_sync_error: null,
        program_extraction_status: detail.works.length > 0 ? "complete" : event.program_extraction_status,
      }).eq("id", event.id);
      return { id: event.id, participantsFound: detail.participants.length, participantsAdded, worksFound: detail.works.length, worksAdded };
    } catch (err) {
      await supabase.from("events").update({
        wienerphilharmoniker_detail_synced_at: new Date().toISOString(),
        wienerphilharmoniker_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
