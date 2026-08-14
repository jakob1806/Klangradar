import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseStaatsoperDetail, type StaatsoperParticipant } from "../_shared/staatsoperDetail.ts";
import { USER_AGENT } from "../_shared/robots.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 20, 1), 30);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const { data: events, error } = await supabase.from("events")
    .select("id,title,website_url,image_urls,primary_image_id,start_datetime,program_extraction_status")
    .ilike("website_url", "%staatsoper.de/%")
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .is("staatsoper_detail_synced_at", null)
    .order("start_datetime").order("id")
    .limit(limit);
  if (error) return json({ error: error.message }, 500);

  const results = await mapLimit(events ?? [], 2, async (event: any) => {
    try {
      const reader = await fetchReaderWithRetry(event.website_url);
      if (!reader.ok) return { id: event.id, error: `reader HTTP ${reader.status}` };
      const detail = parseStaatsoperDetail(await reader.text());
      let imageAdded = false;
      if (detail.imageUrl) {
        // Bestands-Backfill bewusst ohne WASM-Bildkonvertierung: hunderte
        // Events in einem Lauf überschreiten sonst das Edge-Compute-Limit.
        // image_urls ist der produktive Lesepfad aller Apps; neue Importe
        // verarbeiten dasselbe Bild weiterhin über ingest-source.
        await supabase.from("events").update({
          image_urls: [detail.imageUrl, ...(event.image_urls ?? []).filter((u: string) => u !== detail.imageUrl)],
        }).eq("id", event.id);
        imageAdded = true;
      }

      let participantsAdded = 0;
      // Die offizielle terminbezogene Besetzung ist hier maßgeblich. Alte
      // KI-Verknüpfungen enthielten nachweislich Regie-Namen und Personen
      // anderer Termine; nur bei tatsächlich vorhandener Besetzungssektion
      // vollständig ersetzen, nie bei einer unvollständig geladenen Seite.
      if (detail.hasCastSection && detail.participants.length > 0) {
        await supabase.from("event_participants").delete().eq("event_id", event.id);
      }
      for (const [index, participant] of detail.participants.entries()) {
        const entityIds = participant.type === "person"
          ? [await resolvePerson(supabase, participant)].filter((id): id is string => id !== null)
          : await resolveEnsembles(supabase, participant.name);
        if (entityIds.length === 0) continue;
        const column = participant.type === "person" ? "person_id" : "ensemble_id";
        for (const [resolvedIndex, entityId] of entityIds.entries()) {
          const { data: existing } = await supabase.from("event_participants").select("id")
            .eq("event_id", event.id).eq(column, entityId).maybeSingle();
          if (existing) {
            await supabase.from("event_participants").update({ role: participant.role, display_order: index + resolvedIndex }).eq("id", existing.id);
          } else {
            const { error: insertError } = await supabase.from("event_participants").insert({
              event_id: event.id,
              person_id: participant.type === "person" ? entityId : null,
              ensemble_id: participant.type === "ensemble" ? entityId : null,
              role: participant.role,
              display_order: index + resolvedIndex,
            });
            if (!insertError) participantsAdded++;
          }
        }
      }
      let worksAdded = 0;
      if (detail.works.length > 0) {
        await supabase.from("event_works").delete().eq("event_id", event.id);
        for (const work of detail.works) {
          const composerId = work.composerName ? await resolveComposer(supabase, work.composerName) : null;
          const workId = await resolveWork(supabase, work.title, composerId);
          if (!workId) continue;
          const { error: workError } = await supabase.from("event_works").insert({
            event_id: event.id, work_id: workId, position: work.position, after_intermission: false,
          });
          if (!workError) worksAdded++;
        }
      }
      await supabase.from("events").update({
        staatsoper_detail_synced_at: new Date().toISOString(),
        staatsoper_detail_sync_error: null,
        program_extraction_status: detail.works.length > 0 ? "complete" : event.program_extraction_status,
      }).eq("id", event.id);
      return { id: event.id, imageAdded, participantsFound: detail.participants.length, participantsAdded, worksFound: detail.works.length, worksAdded };
    } catch (err) {
      // Fehlerhafte Einzelzeile darf die Queue nicht dauerhaft am Anfang
      // blockieren. Sie wird als versucht markiert und über das Fehlerfeld
      // gezielt in einem späteren Retry-Pass zurückgesetzt.
      await supabase.from("events").update({
        staatsoper_detail_synced_at: new Date().toISOString(),
        staatsoper_detail_sync_error: err instanceof Error ? err.message : String(err),
      }).eq("id", event.id);
      return { id: event.id, error: err instanceof Error ? err.message : String(err) };
    }
  });
  return json({ processed: results.length, remaining: results.length === limit, results });
});

async function resolveComposer(supabase: any, name: string): Promise<string | null> {
  const { data: matches } = await supabase.rpc("find_matching_person", { p_name: name, p_result_limit: 1 });
  if (matches?.[0]?.similarity >= 0.85) return matches[0].id;
  return await resolvePerson(supabase, { name, profileUrl: null, role: "komponist", type: "person" });
}

async function resolveWork(supabase: any, title: string, composerId: string | null): Promise<string | null> {
  let query = supabase.from("works").select("id").ilike("title", title);
  query = composerId ? query.eq("composer_id", composerId) : query.is("composer_id", null);
  const { data: exact } = await query.limit(1).maybeSingle();
  if (exact) return exact.id;
  const { data: matches } = await supabase.rpc("find_matching_work", {
    p_title: title,
    p_composer_id: composerId,
    p_result_limit: 1,
  });
  if (matches?.[0]?.similarity >= 0.9) {
    await supabase.from("entity_aliases").upsert(
      { entity_type: "work", entity_id: matches[0].id, alias: title },
      { onConflict: "entity_type,entity_id,alias_normalized" },
    );
    return matches[0].id;
  }
  const { data: created } = await supabase.from("works").insert({ title, composer_id: composerId }).select("id").single();
  return created?.id ?? null;
}

async function fetchReaderWithRetry(pageUrl: string): Promise<Response> {
  let response = await fetch(`https://r.jina.ai/${pageUrl}`, { headers: { "User-Agent": USER_AGENT } });
  for (let attempt = 1; response.status === 429 && attempt <= 4; attempt++) {
    const retryAfter = Math.min(Number(response.headers.get("retry-after") ?? 0) || attempt * 3, 15);
    await new Promise((resolve) => setTimeout(resolve, retryAfter * 1000));
    response = await fetch(`https://r.jina.ai/${pageUrl}`, { headers: { "User-Agent": USER_AGENT } });
  }
  return response;
}

async function resolvePerson(supabase: any, participant: StaatsoperParticipant): Promise<string | null> {
  const { data: aliasMatches } = await supabase.rpc("resolve_entity_alias", {
    p_entity_type: "person",
    p_name: participant.name,
  });
  const aliasMatch = aliasMatches?.[0];
  if (aliasMatch) {
    const { data: person } = await supabase.from("persons").select("id,roles,website_url").eq("id", aliasMatch.id).single();
    const roles: string[] = person?.roles ?? [];
    const wanted = participant.role ?? "solist";
    await supabase.from("persons").update({
      roles: roles.includes(wanted) ? roles : [...roles, wanted],
      website_url: person?.website_url ?? participant.profileUrl,
    }).eq("id", aliasMatch.id);
    return aliasMatch.id;
  }
  const { data: exact } = await supabase.from("persons").select("id,roles,website_url").ilike("full_name", participant.name).maybeSingle();
  if (exact) {
    const roles: string[] = exact.roles ?? [];
    const wanted = participant.role ?? "solist";
    await supabase.from("persons").update({
      roles: roles.includes(wanted) ? roles : [...roles, wanted],
      website_url: exact.website_url ?? participant.profileUrl,
    }).eq("id", exact.id);
    return exact.id;
  }
  const { data: matches } = await supabase.rpc("find_matching_person", { p_name: participant.name, p_result_limit: 1 });
  if (matches?.[0]?.similarity >= 0.9) {
    await supabase.from("entity_aliases").upsert(
      { entity_type: "person", entity_id: matches[0].id, alias: participant.name },
      { onConflict: "entity_type,entity_id,alias_normalized" },
    );
    return matches[0].id;
  }
  const { data: created } = await supabase.from("persons").insert({
    full_name: participant.name,
    slug: await uniqueSlug(supabase, "persons", participant.name),
    roles: [participant.role ?? "solist"],
    website_url: participant.profileUrl,
    is_verified: false,
  }).select("id").single();
  return created?.id ?? null;
}

// Zweite, unabhängige Absicherung gegen fehlerhafte Ensemble-Anlagen wie
// "**Chor**" (live im Bestand aufgefallen, Nutzer-Meldung "solche Ensembles
// dürfen nicht vorkommen") — zusätzlich zur Bereinigung in
// staatsoperDetail.ts, falls resolveEnsemble künftig auch mit Namen aus
// einer anderen, noch ungeprüften Quelle aufgerufen wird.
const GENERIC_ENSEMBLE_NAMES = new Set(["chor", "chöre", "orchester", "ballett", "ensemble", "choreographie", "choreografie"]);

async function resolveEnsembles(supabase: any, rawName: string): Promise<string[]> {
  const name = rawName.replace(/[*_~`]+/g, "").replace(/\s+/g, " ").trim();
  if (name.length < 3 || GENERIC_ENSEMBLE_NAMES.has(name.toLocaleLowerCase("de"))) return [];
  const { data: resolved } = await supabase.rpc("resolve_ensemble_entities", { p_name: name });
  if (resolved?.some((row: { resolution: string }) => ["ignore", "ambiguous"].includes(row.resolution))) return [];
  const resolvedIds = (resolved ?? []).map((row: { id: string | null }) => row.id)
    .filter((id: string | null): id is string => id !== null);
  if (resolvedIds.length > 0) return resolvedIds;
  const { data: exact } = await supabase.from("ensembles").select("id").ilike("name", name).maybeSingle();
  if (exact) return [exact.id];
  const { data: matches } = await supabase.rpc("find_matching_ensemble", { p_name: name, p_result_limit: 1 });
  if (matches?.[0]?.similarity >= 0.85) {
    await supabase.from("entity_aliases").upsert(
      { entity_type: "ensemble", entity_id: matches[0].id, alias: name },
      { onConflict: "entity_type,entity_id,alias_normalized" },
    );
    return [matches[0].id];
  }
  const type = /chor/i.test(name) ? "chor" : /orchester/i.test(name) ? "orchester" : "sonstiges";
  const { data: created } = await supabase.from("ensembles").insert({
    name, slug: await uniqueSlug(supabase, "ensembles", name), type, is_verified: false,
  }).select("id").single();
  return created?.id ? [created.id] : [];
}

async function uniqueSlug(supabase: any, table: string, name: string): Promise<string> {
  const base = name.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/ß/g, "ss").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 70) || "eintrag";
  for (let i = 0; i < 30; i++) {
    const slug = i ? `${base}-${i + 1}` : base;
    const { data } = await supabase.from(table).select("id").eq("slug", slug).maybeSingle();
    if (!data) return slug;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

async function mapLimit<T, R>(items: T[], concurrency: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const output = new Array<R>(items.length);
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      output[index] = await fn(items[index]);
    }
  }));
  return output;
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
