// Erstellt von Claude Code (Nutzerwunsch 24.10.2026): Werkeinführung und
// recherchierte Satzfolge.
//
// Quelle ist der passende Wikipedia-Artikel (de, sonst en), gesucht mit
// Komponist + Titel + Werkverzeichnisnummer. Die KI fasst ihn auf Deutsch
// zusammen (3–5 Sätze, nur Inhalte aus dem Text). Die Satzfolge kommt aus
// dem Artikel; fehlt sie dort, darf die KI sie nur bei sicher bekannten
// Standardwerken ergänzen ("high" confidence) – markiert als
// movements_source = 'ai_knowledge', damit die Redaktion sie erkennt.
//
// Aufrufe:
//   intern (Cron): POST { limit } → Werke kommender Konzerte zuerst
//   App:           POST { work_id } → einzelnes Werk, Ergebnis zurück
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchWikipediaExtract } from "../_shared/wikipediaExtract.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";

const FN: AiFunctionDeclaration = {
  name: "work_introduction",
  description: "Werkeinführung und Satzfolge eines klassischen Musikwerks.",
  parameters: {
    type: "object",
    properties: {
      introduction: {
        type: "string",
        description: "3–5 Sätze auf Deutsch für Konzertbesucher:innen: Entstehung, Charakter, Besonderheit. NUR aus dem Quelltext; leer, wenn der Text nicht passt.",
      },
      sourceMatches: { type: "boolean", description: "true, wenn der Quelltext eindeutig genau dieses Werk beschreibt." },
      movements: {
        type: "array",
        items: { type: "string" },
        description: "Sätze in Reihenfolge mit Tempobezeichnung (z. B. 'I. Allegro moderato'). Leer bei einsätzigen Werken oder wenn unbekannt.",
      },
      movementsFromSource: { type: "boolean", description: "true, wenn die Satzfolge im Quelltext steht." },
      movementsConfidence: { type: "string", enum: ["high", "medium", "low"], description: "Sicherheit der Satzfolge." },
    },
    required: ["sourceMatches", "movements", "movementsConfidence"],
  },
};

const SYSTEM =
  "Du bist Musikdramaturg:in. Schreibe sachlich, lebendig und ohne Superlative. Erfinde nichts: " +
  "Werkeinführung nur aus dem gegebenen Quelltext. Satzfolgen nur angeben, wenn sie im Text stehen oder es sich um " +
  "ein sehr bekanntes Standardwerk handelt, dessen Sätze du sicher kennst.";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// deno-lint-ignore no-explicit-any
async function processWork(supabase: any, work: any) {
  const composer = work.composer?.full_name ?? "";
  const query = [composer, work.title, work.catalog_number].filter(Boolean).join(" ");
  const extract = await fetchWikipediaExtract(query).catch(() => null);
  const user = `Werk: ${work.title}\nKomponist:in: ${composer}\nWerkverzeichnis: ${work.catalog_number ?? "–"}\n\n` +
    (extract ? `Quelltext (${extract.pageUrl}):\n${extract.text.slice(0, 9000)}` : "Kein Quelltext gefunden.");
  const result = await callAiFunction(SYSTEM, user, FN);
  const args = result?.args ?? {};

  const update: Record<string, unknown> = { introduction_checked_at: new Date().toISOString() };
  const intro = typeof args.introduction === "string" ? args.introduction.trim() : "";
  if (extract && args.sourceMatches && intro.length > 60) {
    update.introduction_de = intro;
    update.introduction_source_url = extract.pageUrl;
  }
  const movements = Array.isArray(args.movements) ? args.movements.map(String).map((m: string) => m.trim()).filter(Boolean) : [];
  const fromSource = Boolean(args.movementsFromSource) && Boolean(extract && args.sourceMatches);
  const hasMovements = Array.isArray(work.movements) && work.movements.length > 1;
  if (!hasMovements && movements.length > 1 && (fromSource || args.movementsConfidence === "high")) {
    update.movements = movements.slice(0, 12);
    update.movements_source = fromSource ? "wikipedia" : "ai_knowledge";
  }
  await supabase.from("works").update(update).eq("id", work.id);
  return { id: work.id, introduction: update.introduction_de ?? work.introduction_de ?? null, sourceUrl: update.introduction_source_url ?? null, movements: update.movements ?? work.movements ?? [] };
}

const SELECT = "id,title,catalog_number,movements,introduction_de,introduction_checked_at,composer:persons(full_name)";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  // Einzelnes Werk aus der App: ohne internes Secret erlaubt, aber nur, wenn
  // es noch nie (bzw. vor > 30 Tagen) geprüft wurde – begrenzt KI-Kosten.
  if (typeof body.work_id === "string") {
    const { data: work } = await supabase.from("works").select(SELECT).eq("id", body.work_id).maybeSingle();
    if (!work) return json({ error: "not found" }, 404);
    const fresh = work.introduction_checked_at && Date.now() - Date.parse(work.introduction_checked_at) < 30 * 86_400_000;
    if (work.introduction_de || fresh) {
      return json({ id: work.id, introduction: work.introduction_de, movements: work.movements ?? [] });
    }
    return json(await processWork(supabase, work));
  }

  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const limit = Math.min(Math.max(Number(body.limit) || 8, 1), 20);
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
  const results = [];
  for (const work of works) results.push(await processWork(supabase, work).catch((e) => ({ id: work.id, error: String(e) })));
  return json({ processed: results.length, results });
});
