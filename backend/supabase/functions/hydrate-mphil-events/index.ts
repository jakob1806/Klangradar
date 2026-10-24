import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { saveProgramBooklet } from "../_shared/programBooklet.ts";
import { parseMphilEventDetail } from "../_shared/mphilDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants, resolveComposer, resolveWork } from "../_shared/eventParticipantResolution.ts";

// Dritte Quelle mit eigener Termin-Detailseiten-Pipeline nach Staatsoper und
// BRSO (Nutzeranfrage: "das sollen auch andere websites können"). mphil.de
// blockt normale Fetches nicht — kein r.jina.ai-Reader nötig. Anders als
// staatsoper.de/brso.de gibt es hier kein eigenes Eventfoto (og:image ist
// überall dasselbe generische Logo, siehe mphilDetail.ts) — der Mehrwert
// ist die Bio-Link-Rückverlinkung für Dirigent:innen/Solist:innen.
import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url,external_id,venue_id,start_datetime")
    // Beim Zusammenführen mit Aggregatoren (concerti, in-muenchen) wird
    // website_url überschrieben; die mphil-URL bleibt in external_id.
    .or("website_url.ilike.%mphil.de/%,external_id.ilike.%mphil.de/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("mphil_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 3, async (event: any) => {
    try {
      const pageUrl = /mphil\.de\//.test(event.external_id ?? "") ? event.external_id : event.website_url;
      const res = await fetch(pageUrl, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) return { id: event.id, error: `HTTP ${res.status}` };
      const html = await res.text();
      const detail = parseMphilEventDetail(html, pageUrl);
      await saveProgramBooklet(supabase, event.id, html, pageUrl);
      const participantsAdded = await replaceEventParticipants(supabase, event.id, detail.participants);

      // Offizielles Programm ersetzt die KI-Extraktion vollständig, aber nur
      // wenn die Seite tatsächlich eine Werkliste hatte.
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

      const duplicatesHidden = await hideSameSlotDuplicates(supabase, event);

      await supabase.from("events").update({
        website_url: pageUrl,
        mphil_detail_synced_at: new Date().toISOString(),
        mphil_detail_sync_error: null,
        ...(detail.works.length > 0 ? { program_extraction_status: "complete" } : {}),
      }).eq("id", event.id);
      return { id: event.id, participantsFound: detail.participants.length, participantsAdded, duplicatesHidden, worksFound: detail.works.length, worksAdded };
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

// Dasselbe Konzert kommt zusätzlich über Aggregatoren (gasteig.de, concerti,
// in-muenchen) mit schlechterem Programm/Besetzung herein. Gleicher Saal,
// Beginn ±20 Min. und "Philharmoniker" im Titel = Dublette: als abgelehnter
// Entwurf ausblenden (nicht löschen, Redaktion kann es zurückholen).
// deno-lint-ignore no-explicit-any
async function hideSameSlotDuplicates(supabase: any, event: any): Promise<number> {
  if (!event.venue_id || !event.start_datetime) return 0;
  const start = new Date(event.start_datetime).getTime();
  const { data } = await supabase.from("events")
    .select("id")
    .eq("venue_id", event.venue_id)
    .neq("id", event.id)
    .ilike("title", "%philharmoniker%")
    .in("status", ["scheduled", "sold_out"])
    .gte("start_datetime", new Date(start - 20 * 60_000).toISOString())
    .lte("start_datetime", new Date(start + 20 * 60_000).toISOString());
  const ids = (data ?? []).map((row: { id: string }) => row.id);
  if (ids.length === 0) return 0;
  await supabase.from("events").update({ status: "draft", review_status: "rejected" }).in("id", ids);
  return ids.length;
}
