// Erstellt von Claude Code (26.10.2026): Recherche-Cron für offizielle
// Social-Media-Konten (Instagram, Facebook, X, YouTube, TikTok, …) von
// Personen, Ensembles und Spielstätten über Wikidata. Füllt nur fehlende
// Plattformen auf, überschreibt nie redaktionell gepflegte Links.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { json } from "../_shared/eventParticipantResolution.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { findSocialLinks, RateLimited, type SocialEntityType } from "../_shared/wikidataSocial.ts";

const TABLES: Record<SocialEntityType, { table: string; name: string }> = {
  person: { table: "persons", name: "full_name" },
  ensemble: { table: "ensembles", name: "name" },
  venue: { table: "venues", name: "name" },
};

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 25, 1), 60);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const started = Date.now();
  const results: unknown[] = [];

  // Ensembles und Orte zuerst (wenige, hohe Sichtbarkeit), dann Personen.
  for (const type of ["ensemble", "venue", "person"] as SocialEntityType[]) {
    const { table, name } = TABLES[type];
    const { data: rows } = await supabase.from(table)
      .select(`id,${name},social_links,website_url`)
      .is("social_links_checked_at", null)
      .order("created_at")
      .limit(limit - results.length);
    // deno-lint-ignore no-explicit-any
    for (const row of (rows ?? []) as any[]) {
      if (Date.now() - started > 110_000) return json({ processed: results.length, stopped: "time", results });
      try {
        const found = await findSocialLinks(type, row[name]);
        const existing = row.social_links ?? {};
        const merged = { ...(found?.links ?? {}), ...Object.fromEntries(Object.entries(existing).filter(([, v]) => v)) };
        await supabase.from(table).update({
          social_links: merged,
          ...(found?.website && !row.website_url ? { website_url: found.website } : {}),
          wikidata_id: found?.qid ?? null,
          social_links_checked_at: new Date().toISOString(),
        }).eq("id", row.id);
        results.push({ type, id: row.id, qid: found?.qid ?? null, added: Object.keys(found?.links ?? {}) });
      } catch (err) {
        if (err instanceof RateLimited) return json({ processed: results.length, stopped: "rate_limited", results });
        await supabase.from(table).update({ social_links_checked_at: new Date().toISOString() }).eq("id", row.id);
        results.push({ type, id: row.id, error: err instanceof Error ? err.message : String(err) });
      }
      await new Promise((r) => setTimeout(r, 1100));
    }
    if (results.length >= limit) break;
  }
  return json({ processed: results.length, results });
});
