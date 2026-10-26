import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit } from "../_shared/eventParticipantResolution.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { musikvereinId } from "../_shared/musikvereinDetail.ts";
import {
  brsoSubscriptions, linkEventSubscriptions, mphilSubscriptions, musikvereinSubscriptions,
  type SubscriptionCandidate, wienerSymphonikerSubscriptions,
} from "../_shared/subscriptions.ts";

// Erstellt von Claude Code (26.10.2026): Ordnet kommende Termine ihren Abos
// bzw. Zyklen zu (Grundlage für Abo-Anzeige, Abo-Erkennung und Saisonplaner).
// Eigene Funktion statt Teil der hydrate-Pipelines, damit alle Veranstalter
// an einer Stelle und mit einer Sync-Spalte laufen.
const DOMAINS = ["mphil.de/", "brso.de/konzerte", "musikverein.at/konzert", "wienersymphoniker.at/konzert"];

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 30, 1), 60);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,website_url,external_id,start_datetime")
    .or(DOMAINS.flatMap((d) => [`website_url.ilike.%${d}%`, `external_id.ilike.%${d}%`]).join(","))
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("subscriptions_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  // deno-lint-ignore no-explicit-any
  const results = await mapLimit(events ?? [], 4, async (event: any) => {
    const urls = [event.external_id, event.website_url].filter((u): u is string => typeof u === "string" && u.startsWith("http"));
    const url = urls.find((u) => DOMAINS.some((d) => u.includes(d))) ?? urls[0];
    try {
      let subs: SubscriptionCandidate[] = [];
      const mvId = musikvereinId(url);
      if (mvId) {
        const res = await fetch(`https://spielplan.musikverein.at/e/${mvId}.json`, { headers: { "User-Agent": USER_AGENT } });
        if (res.ok) subs = musikvereinSubscriptions(await res.json());
      } else {
        const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
        if (res.ok) {
          const html = await res.text();
          if (url.includes("mphil.de")) subs = mphilSubscriptions(html);
          else if (url.includes("brso.de")) subs = brsoSubscriptions(html, event.start_datetime);
          else if (url.includes("wienersymphoniker.at")) subs = wienerSymphonikerSubscriptions(html);
        }
      }
      const linked = await linkEventSubscriptions(supabase, event.id, event.start_datetime, subs);
      await supabase.from("events").update({ subscriptions_synced_at: new Date().toISOString() }).eq("id", event.id);
      return { id: event.id, linked };
    } catch (err) {
      await supabase.from("events").update({ subscriptions_synced_at: new Date().toISOString() }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});
