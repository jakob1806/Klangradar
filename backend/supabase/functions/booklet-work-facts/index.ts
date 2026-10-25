// Erstellt von Claude Code (25.10.2026): Werkangaben aus Programmheften und
// Veranstalter-Beschreibungen übernehmen (_shared/bookletFacts.ts).
//   * Satzfolge: aus dem Heft, wenn dort mehr Sätze stehen als bekannt
//   * Dauer: aus dem Heft, wenn noch leer
//   * Einführung: NUR für Werke ohne (Wikipedia-)Einführung – kurzer Auszug
//     aus dem Heft bzw. aus der Konzertbeschreibung, mit Quellen-Link.
// Aufruf (intern/Cron): POST { limit? }
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { factsForWork, pdfText } from "../_shared/bookletFacts.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { USER_AGENT } from "../_shared/robots.ts";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function bookletText(url: string): Promise<string | null> {
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return null;
    const type = res.headers.get("content-type") ?? "";
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (bytes.length > 25_000_000) return null;
    if (type.includes("pdf") || /\.pdf(\?|$)/i.test(url)) return await pdfText(bytes);
    // HTML-Programmheft (z. B. mphil.de/…/programmheft): Text ohne Markup.
    let html = new TextDecoder().decode(bytes);
    let previous: string;
    do { previous = html; html = html.replace(/<(script|style)[^<]*>[^<]*<\/\1>/gi, "").replace(/<[^<>]*>/g, " "); } while (html !== previous);
    return html.replace(/[<>]/g, " ").replace(/&nbsp;/g, " ").replace(/\s+/g, " ");
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 12, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events } = await supabase.from("events")
    .select("id,website_url,program_booklet_url,description_de,program_notes_de,event_works(works(id,title,movements,movements_source,duration_minutes,introduction_de,composer:persons(full_name)))")
    .is("booklet_facts_checked_at", null)
    .gte("start_datetime", new Date(Date.now() - 14 * 86_400_000).toISOString())
    .order("start_datetime")
    .limit(limit);

  let updated = 0;
  const started = Date.now();
  const queue = [...(events ?? [])];
  await Promise.all(Array.from({ length: 3 }, async () => {
    while (queue.length && Date.now() - started < 110_000) {
      const event = queue.shift();
      if (!event) break;
      // deno-lint-ignore no-explicit-any
      const works = (event.event_works ?? []).map((ew: any) => ew.works).filter(Boolean);
      const booklet = event.program_booklet_url ? await bookletText(event.program_booklet_url) : null;
      const description = [event.description_de, event.program_notes_de].filter(Boolean).join(" ");
      // deno-lint-ignore no-explicit-any
      const surnames = works.map((w: any) => (w.composer?.full_name ?? "").split(/\s+/).pop()).filter(Boolean);
      for (const work of works) {
        const composer = work.composer?.full_name ?? null;
        const own = (composer ?? "").split(/\s+/).pop();
        const others = surnames.filter((s: string) => s !== own);
        const update: Record<string, unknown> = {};
        if (booklet) {
          const facts = factsForWork(booklet, work.title, composer, others);
          if (work.movements_source !== "redaktion" && facts.movements.length > Math.max(work.movements?.length ?? 0, 1)) {
            update.movements = facts.movements;
            update.movements_source = "programmheft";
          }
          if (!work.duration_minutes && facts.durationMinutes) update.duration_minutes = facts.durationMinutes;
          if (!work.introduction_de && facts.excerpt) {
            update.introduction_de = facts.excerpt;
            update.introduction_source_url = event.program_booklet_url;
            update.introduction_source = "programmheft";
          }
        }
        if (!work.introduction_de && !update.introduction_de && description.length > 200) {
          const facts = factsForWork(description, work.title, composer, others);
          if (facts.excerpt) {
            update.introduction_de = facts.excerpt;
            update.introduction_source_url = event.website_url;
            update.introduction_source = "veranstalter";
          }
        }
        if (Object.keys(update).length) {
          await supabase.from("works").update(update).eq("id", work.id);
          updated++;
        }
      }
      await supabase.from("events").update({ booklet_facts_checked_at: new Date().toISOString() }).eq("id", event.id);
    }
  }));
  return json({ processed: (events?.length ?? 0) - queue.length, updated });
});
