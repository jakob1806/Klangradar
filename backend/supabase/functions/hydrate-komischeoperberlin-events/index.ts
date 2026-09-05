import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { castCrewEndpoint, extractCastCrewRef, parseCastCrewResponse } from "../_shared/komischeOperBerlinDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit, replaceEventParticipants } from "../_shared/eventParticipantResolution.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";

// Erste Termin-Detailseiten-Pipeline der Multi-City-Erweiterung (Nutzer-
// anfrage: "mache venue-spezifische Hydration-Parser wie bei München" für
// Hamburg/Berlin/Wien/Frankfurt) — gleiches Muster wie hydrate-brso-events:
// nur event_participants, kein event_works (das Stück IST das Event, siehe
// event.title, keine separate Programmliste auf dieser Quelle).
Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url")
    .ilike("website_url", "%komische-oper-berlin.de/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("komischeoperberlin_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 3, async (event: { id: string; title: string; website_url: string }) => {
    try {
      const pageRes = await fetch(event.website_url, { headers: { "User-Agent": USER_AGENT } });
      if (!pageRes.ok) return { id: event.id, error: `HTTP ${pageRes.status}` };
      const ref = extractCastCrewRef(await pageRes.text());
      if (!ref) {
        // Führungen/Sonderformate ohne Besetzung (z.B. "Führung Baustelle
        // Stammhaus") haben diesen Marker nicht — kein Fehler, einfach
        // nichts zu holen.
        await supabase.from("events").update({
          komischeoperberlin_detail_synced_at: new Date().toISOString(),
          komischeoperberlin_detail_sync_error: null,
        }).eq("id", event.id);
        return { id: event.id, participantsFound: 0 };
      }

      const castRes = await fetch(castCrewEndpoint(ref), { headers: { "User-Agent": USER_AGENT } });
      if (!castRes.ok) return { id: event.id, error: `cast-and-crew HTTP ${castRes.status}` };
      const participants = parseCastCrewResponse(await castRes.text());
      const participantsAdded = await replaceEventParticipants(supabase, event.id, participants);

      await supabase.from("events").update({
        komischeoperberlin_detail_synced_at: new Date().toISOString(),
        komischeoperberlin_detail_sync_error: null,
      }).eq("id", event.id);
      return { id: event.id, participantsFound: participants.length, participantsAdded };
    } catch (err) {
      await supabase.from("events").update({
        komischeoperberlin_detail_synced_at: new Date().toISOString(),
        komischeoperberlin_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
