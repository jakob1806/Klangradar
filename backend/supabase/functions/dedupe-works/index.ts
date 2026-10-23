// Erstellt von Claude Code. Führt doppelt angelegte Werke zusammen
// (Nutzerfeedback: Stücke im Programm doppelt, weil sich ein Wort
// unterscheidet). Identität wie im Import (workIdentity.ts), nur innerhalb
// eines Komponisten. Cron täglich 04:40 (run_dedupe_works). POST
// {"dryRun": true} zeigt nur den Plan.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { planMerges, type WorkRow } from "./plan.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dryRun === true;
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const works: WorkRow[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db.from("works").select("id, title, composer_id, catalog_number, event_works(count)").not("composer_id", "is", null).range(from, from + 999);
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    for (const row of data ?? []) {
      // deno-lint-ignore no-explicit-any
      const r = row as any;
      works.push({ id: r.id, title: r.title, composer_id: r.composer_id, catalog_number: r.catalog_number, uses: r.event_works?.[0]?.count ?? 0 });
    }
    if (!data || data.length < 1000) break;
  }

  const merges = planMerges(works);
  let merged = 0;
  const errors: string[] = [];
  if (!dryRun) {
    for (const m of merges.slice(0, 500)) {
      const { error } = await db.rpc("merge_works", { p_keep: m.keep, p_drop: m.drop });
      if (error) errors.push(`${m.reason}: ${error.message}`);
      else merged++;
    }
  }
  return new Response(JSON.stringify({ works: works.length, planned: merges.length, merged, dryRun, examples: merges.slice(0, 30).map((m) => m.reason), errors: errors.slice(0, 20) }), { headers: { "Content-Type": "application/json" } });
});
