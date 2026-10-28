import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { USER_AGENT } from "../_shared/robots.ts";
import { json, mapLimit } from "../_shared/eventParticipantResolution.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { musikvereinId } from "../_shared/musikvereinDetail.ts";
import {
  brChorSubscriptions, BRSO_CALENDAR_URL, brsoCalendarIndex, brsoKey, brsoSubscriptions, gaertnerplatzSeries, type GaertnerplatzSeries, gaertnerplatzSubscriptions,
  linkEventSubscriptions, mkoSubscriptions, mphilSubscriptions, musikvereinSubscriptions, rundfunkorchesterSubscriptions,
  seasonFor, type SubscriptionCandidate, wienerSymphonikerSubscriptions,
} from "../_shared/subscriptions.ts";

// Erstellt von Claude Code (26.10.2026): Ordnet kommende Termine ihren Abos
// bzw. Zyklen zu (Grundlage für Abo-Anzeige, Abo-Erkennung und Saisonplaner).
// Eigene Funktion statt Teil der hydrate-Pipelines, damit alle Veranstalter
// an einer Stelle und mit einer Sync-Spalte laufen.
const DOMAINS = [
  "mphil.de/", "brso.de/konzerte", "musikverein.at/konzert", "wienersymphoniker.at/konzert",
  "rundfunkorchester.de/konzerte", "br-chor.de/konzerte", "m-k-o.eu/event-detail", "gaertnerplatztheater.de/de/produktionen",
];

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 30, 1), 60);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url,external_id,start_datetime")
    .or(DOMAINS.flatMap((d) => [`website_url.ilike.%${d}%`, `external_id.ilike.%${d}%`]).join(","))
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("subscriptions_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  // Gärtnerplatztheater: eine Abo-Seite je Saison mit allen Serien und Terminen –
  // pro Lauf nur einmal laden.
  const gptPages = new Map<string, Promise<GaertnerplatzSeries[]>>();
  const gptSeries = (start: string) => {
    const season = seasonFor(start).replace("/", "-20"); // "2026/27" -> "2026-2027"
    if (!gptPages.has(season)) {
      gptPages.set(season, fetch(`https://www.gaertnerplatztheater.de/de/seiten/abos-${season}.html`, { headers: { "User-Agent": USER_AGENT } })
        .then(async (res) => res.ok ? gaertnerplatzSeries(await res.text()) : [])
        .catch(() => []));
    }
    return gptPages.get(season)!;
  };

  // BRSO: Konzertkalender mit Abo je Termin – ebenfalls nur einmal pro Lauf.
  let brsoIndex: Promise<Map<string, SubscriptionCandidate[]> | null> | null = null;
  const brsoCalendar = () => brsoIndex ??= fetch(BRSO_CALENDAR_URL, {
    method: "POST",
    headers: { "User-Agent": USER_AGENT, "Content-Type": "application/x-www-form-urlencoded" },
    body: "pagination=1&director=all&location=0&abo=0&presented_by=",
  }).then(async (res) => res.ok ? brsoCalendarIndex(await res.json()) : null).catch(() => null);

  // deno-lint-ignore no-explicit-any
  const results = await mapLimit(events ?? [], 4, async (event: any) => {
    const urls = [event.external_id, event.website_url].filter((u): u is string => typeof u === "string" && u.startsWith("http"));
    const url = urls.find((u) => DOMAINS.some((d) => u.includes(d))) ?? urls[0];
    try {
      let subs: SubscriptionCandidate[] = [];
      const mvId = musikvereinId(url);
      if (url.includes("gaertnerplatztheater.de")) {
        const season = seasonFor(event.start_datetime).replace("/", "-20");
        subs = gaertnerplatzSubscriptions(await gptSeries(event.start_datetime), event.start_datetime,
          `https://www.gaertnerplatztheater.de/de/seiten/abos-${season}.html`);
      } else if (url.includes("brso.de")) {
        const index = await brsoCalendar();
        if (index && index.size > 0) subs = index.get(brsoKey(url, event.start_datetime)) ?? [];
        else {
          const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
          if (res.ok) subs = brsoSubscriptions(await res.text(), event.start_datetime);
        }
      } else if (url.includes("m-k-o.eu")) {
        subs = mkoSubscriptions(url, event.title ?? "");
      } else if (mvId) {
        const res = await fetch(`https://spielplan.musikverein.at/e/${mvId}.json`, { headers: { "User-Agent": USER_AGENT } });
        if (res.ok) subs = musikvereinSubscriptions(await res.json());
      } else {
        const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
        if (res.ok) {
          const html = await res.text();
          if (url.includes("mphil.de")) subs = mphilSubscriptions(html);
          else if (url.includes("wienersymphoniker.at")) subs = wienerSymphonikerSubscriptions(html);
          else if (url.includes("rundfunkorchester.de")) subs = rundfunkorchesterSubscriptions(html);
          else if (url.includes("br-chor.de")) subs = brChorSubscriptions(html);
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
