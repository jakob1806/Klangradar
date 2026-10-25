import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { musikvereinId, parseMusikvereinDetail } from "../_shared/musikvereinDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants, resolveComposer, resolveWork } from "../_shared/eventParticipantResolution.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";

// Erstellt von Claude Code (25.10.2026): Musikverein-Termine mit der
// offiziellen Spielplan-JSON anreichern (Werke in Reihenfolge inkl. Pause,
// Mitwirkende mit Instrument, Langtext). Bisher enthielt die Beschreibung nur
// die zusammengeklebten Kopfzeilen der Listenansicht.
Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 40);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,website_url,external_id")
    .or("website_url.ilike.%musikverein.at/konzert%,external_id.ilike.%musikverein.at/konzert%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("musikverein_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  // deno-lint-ignore no-explicit-any
  const results = await mapLimit(events ?? [], 4, async (event: any) => {
    const mark = (err: string | null) => supabase.from("events").update({
      musikverein_detail_synced_at: new Date().toISOString(), musikverein_detail_sync_error: err,
    }).eq("id", event.id);
    try {
      const id = musikvereinId(event.external_id) ?? musikvereinId(event.website_url);
      if (!id) { await mark("keine Musikverein-ID"); return { id: event.id, error: "no id" }; }
      const res = await fetch(`https://spielplan.musikverein.at/e/${id}.json`, { headers: { "User-Agent": USER_AGENT, Accept: "application/json" } });
      if (!res.ok) { await mark(`HTTP ${res.status}`); return { id: event.id, error: `HTTP ${res.status}` }; }
      const detail = parseMusikvereinDetail(await res.json());

      const participantsAdded = detail.participants.length
        ? await replaceEventParticipants(supabase, event.id, detail.participants) : 0;

      let worksAdded = 0;
      if (detail.works.length > 0) {
        await supabase.from("event_works").delete().eq("event_id", event.id);
        for (const work of detail.works) {
          const composerId = work.composerName ? await resolveComposer(supabase, work.composerName) : null;
          const workId = await resolveWork(supabase, work.title, composerId);
          if (!workId) continue;
          const { error: workError } = await supabase.from("event_works").insert({
            event_id: event.id, work_id: workId, position: work.position, after_intermission: work.afterIntermission,
          });
          if (!workError) worksAdded++;
        }
      }

      await supabase.from("events").update({
        ...(detail.description ? { description_de: detail.description } : {}),
        ...(worksAdded > 0 ? { program_extraction_status: "complete" } : {}),
        musikverein_detail_synced_at: new Date().toISOString(),
        musikverein_detail_sync_error: null,
      }).eq("id", event.id);
      return { id: event.id, worksFound: detail.works.length, worksAdded, participantsAdded, description: !!detail.description };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      await mark(message);
      return { id: event.id, error: message };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
