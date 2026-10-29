// Erstellt von Claude Code (Nutzerwunsch 24.10.2026): Werkeinführung und
// Satzfolge. Seit 25.10.2026 ohne KI direkt aus Wikipedia (de, sonst en),
// siehe _shared/workWikiFacts.ts: Einleitung des Werkartikels als Einführung,
// Satzfolge aus Überschriften/Abschnitt "Sätze"/englischem Artikel, mit
// Quell-Link (CC BY-SA). Kein Treffer → keine Einführung statt einer
// falschen.
//
// Aufrufe:
//   intern (Cron): POST { limit } → Werke kommender Konzerte zuerst
//   App:           POST { work_id } → einzelnes Werk, Ergebnis zurück
//   Diagnose:      POST { diagnose: true } → Status der KI-Anbieter
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { fetchWorkWikiFacts } from "../_shared/workWikiFacts.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// deno-lint-ignore no-explicit-any
async function processWork(supabase: any, work: any) {
  // Seit 25.10.2026 ohne KI: Einleitung + Satzfolge direkt aus Wikipedia
  // (_shared/workWikiFacts.ts). Die KI-Anbieter lieferten wiederholt keine
  // Antwort ("ai_unavailable"); Wikipedia ist zuverlässig, schnell und
  // nennt die Quelle.
  const facts = await fetchWorkWikiFacts(work.title, work.composer?.full_name ?? null, work.catalog_number ?? null, work.composer?.wikidata_id ?? null).catch(() => null);
  const update: Record<string, unknown> = { introduction_checked_at: new Date().toISOString() };
  // Von der Redaktion geschriebene Einführungen/Satzfolgen nie überschreiben.
  if (facts?.introduction && work.introduction_source !== "redaktion") {
    update.introduction_de = facts.introduction;
    update.introduction_source_url = facts.pageUrl;
    update.introduction_source = "wikipedia";
  }
  // Recherchierte Satzfolge ersetzt eine kürzere/fehlende (Quelle der
  // Daten oft nur die Veranstalterseite mit unvollständigen Sätzen).
  const existing = Array.isArray(work.movements) ? work.movements.length : 0;
  if (work.movements_source !== "redaktion" && (facts?.movements.length ?? 0) > Math.max(existing, 1)) {
    update.movements = facts!.movements.slice(0, 20);
    update.movements_source = "wikipedia";
  }
  await supabase.from("works").update(update).eq("id", work.id);
  return {
    id: work.id,
    introduction: update.introduction_de ?? work.introduction_de ?? null,
    sourceUrl: update.introduction_source_url ?? null,
    movements: update.movements ?? work.movements ?? [],
    source: facts?.pageUrl ?? null,
  };
}

const SELECT = "id,title,catalog_number,movements,movements_source,introduction_de,introduction_source,introduction_checked_at,composer:persons(full_name,wikidata_id)";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  // Diagnose: ruft jeden KI-Anbieter direkt mit einer Mini-Anfrage auf und
  // meldet nur Statuscode + gekürzten Fehlertext (keine Schlüssel, keine
  // Nutzerdaten) – um Ausfälle wie "ai_unavailable" einzugrenzen.
  if (body.diagnose === true) return json(await diagnoseProviders());

  // Einzelnes Werk aus der App: ohne internes Secret erlaubt, aber nur, wenn
  // es noch nie (bzw. vor > 30 Tagen) geprüft wurde – begrenzt KI-Kosten.
  if (typeof body.work_id === "string") {
    const { data: work } = await supabase.from("works").select(SELECT).eq("id", body.work_id).maybeSingle();
    if (!work) return json({ error: "not found" }, 404);
    // "force" (Redaktion: "Automatisch recherchieren") nur mit internem Secret.
    const force = body.force === true && !(await requireInternalAuth(req));
    const fresh = work.introduction_checked_at && Date.now() - Date.parse(work.introduction_checked_at) < 7 * 86_400_000;
    if (fresh && !force) {
      return json({ id: work.id, introduction: work.introduction_de, movements: work.movements ?? [] });
    }
    return json(await processWork(supabase, work));
  }

  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const limit = Math.min(Math.max(Number(body.limit) || 25, 1), 40);
  // Werke kommender Konzerte zuerst (nächste 60 Tage), noch nie geprüft.
  const { data: rows } = await supabase
    .from("event_works")
    .select(`work_id, events!inner(start_datetime,status), works!inner(${SELECT})`)
    .gte("events.start_datetime", new Date().toISOString())
    .lte("events.start_datetime", new Date(Date.now() + 60 * 86_400_000).toISOString())
    .is("works.introduction_checked_at", null)
    .limit(200);
  const seen = new Set<string>();
  // deno-lint-ignore no-explicit-any
  const works = (rows ?? []).map((r: any) => r.works).filter((w: any) => w && !seen.has(w.id) && seen.add(w.id)).slice(0, limit);
  // Danach alle übrigen Werke der Datenbank (Redaktions-Wunsch 25.10.2026:
  // für alle vorhandenen Werke recherchieren).
  if (works.length < limit) {
    const { data: rest } = await supabase.from("works").select(SELECT)
      .is("introduction_checked_at", null).order("id").limit(limit - works.length + 10);
    // deno-lint-ignore no-explicit-any
    for (const w of rest ?? []) if (!seen.has((w as any).id) && works.length < limit) { seen.add((w as any).id); works.push(w); }
  }
  // Parallel (6 gleichzeitig) und mit Zeitbudget: nacheinander schaffte ein
  // Lauf vor dem 150-s-Limit der Edge Functions nur ~6 Werke.
  const started = Date.now();
  const results: unknown[] = [];
  const queue = [...works];
  await Promise.all(Array.from({ length: 6 }, async () => {
    while (queue.length && Date.now() - started < 110_000) {
      const work = queue.shift();
      if (!work) break;
      results.push(await processWork(supabase, work).catch(() => ({ id: work.id, error: "Fehler beim Abruf" })));
    }
  }));
  return json({ processed: results.length, results });
});

async function diagnoseProviders() {
  const fn = { name: "ping", description: "Antwort", parameters: { type: "object", properties: { ok: { type: "boolean" } }, required: ["ok"] } };
  const results: Record<string, unknown> = {};
  const openAi = [
    ["cerebras", "CEREBRAS_API_KEY", "https://api.cerebras.ai/v1/chat/completions", "gpt-oss-120b"],
    ["nvidia", "NVIDIA_API_KEY", "https://integrate.api.nvidia.com/v1/chat/completions", "meta/llama-3.3-70b-instruct"],
  ];
  for (const [name, env, url, model] of openAi) {
    const key = Deno.env.get(env);
    if (!key) { results[name] = "kein Schlüssel"; continue; }
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
        body: JSON.stringify({ model, messages: [{ role: "user", content: "Sag ok." }], tools: [{ type: "function", function: fn }], tool_choice: { type: "function", function: { name: "ping" } } }),
      });
      results[name] = { status: res.status, body: (await res.text()).slice(0, 300) };
    } catch { results[name] = "Netzwerkfehler"; }
  }
  const gKey = Deno.env.get("GEMINI_API_KEY");
  if (!gKey) results.gemini = "kein Schlüssel";
  else {
    try {
      const res = await fetch("https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent", {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": gKey },
        body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: "Sag ok." }] }] }),
      });
      results.gemini = { status: res.status, body: (await res.text()).slice(0, 300) };
    } catch { results.gemini = "Netzwerkfehler"; }
  }
  return results;
}
