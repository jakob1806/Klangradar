// Gemeinsame Entitäts-Auflösung für alle "hydrate-<quelle>-events"-Funktionen
// (bisher nur hydrate-staatsoper-events, jetzt zusätzlich hydrate-brso-
// events) — Nutzeranfrage: "das sollen auch andere websites können" (mehr
// Quellen sollen wie die Staatsoper eine eigene Termin-Detailseiten-Pipeline
// bekommen). Extrahiert aus hydrate-staatsoper-events/index.ts, wo diese
// Logik zuerst entstand, statt sie für jede weitere Quelle zu duplizieren.

import { assessEnsembleName } from "./entityNameValidation.ts";

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

export interface EventParticipantCandidate {
  name: string;
  profileUrl: string | null;
  role: string | null;
  type: "person" | "ensemble";
}

export async function resolveComposer(supabase: SupabaseClient, name: string): Promise<string | null> {
  const { data: matches } = await supabase.rpc("find_matching_person", { p_name: name, p_result_limit: 1 });
  if (matches?.[0]?.similarity >= 0.85) return matches[0].id;
  return await resolvePerson(supabase, { name, profileUrl: null, role: "komponist", type: "person" });
}

export async function resolveWork(supabase: SupabaseClient, title: string, composerId: string | null): Promise<string | null> {
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
  const { data: created, error: insertError } = await supabase.from("works").insert({ title, composer_id: composerId }).select("id").single();
  if (created?.id) return created.id;
  // Gleiche Race-Absicherung wie resolvePerson()/resolveEnsembles() oben.
  if (insertError) {
    let retryQuery = supabase.from("works").select("id").ilike("title", title);
    retryQuery = composerId ? retryQuery.eq("composer_id", composerId) : retryQuery.is("composer_id", null);
    const { data: retry } = await retryQuery.limit(1).maybeSingle();
    if (retry) return retry.id;
  }
  return null;
}

export async function resolvePerson(supabase: SupabaseClient, participant: EventParticipantCandidate): Promise<string | null> {
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
  const { data: created, error: insertError } = await supabase.from("persons").insert({
    full_name: participant.name,
    slug: await uniqueSlug(supabase, "persons", participant.name),
    roles: [participant.role ?? "solist"],
    website_url: participant.profileUrl,
    is_verified: false,
  }).select("id").single();
  if (created?.id) return created.id;
  // Race mit einem GLEICHZEITIG laufenden resolvePerson()-Aufruf für
  // dieselbe neue Person — z.B. dieselbe Solistin tritt am selben Tag in
  // mehreren parallel verarbeiteten Events auf (mapLimit-Nebenläufigkeit in
  // den hydrate-*-events-Funktionen). Der "exact match"-Check oben lief
  // dann noch vor dem Commit des anderen Aufrufs und fand nichts; dessen
  // Zeile existiert inzwischen aber. Live beobachtet (Gasteig/MKO,
  // 2026-08-14/15: "Jörg Widmann"/"Carolin Widmann" fehlten sporadisch in
  // event_participants trotz erfolgreicher Namensauflösung). Einmal erneut
  // suchen, statt den Kandidaten stillschweigend zu verlieren.
  if (insertError) {
    const { data: retry } = await supabase.from("persons").select("id").ilike("full_name", participant.name).maybeSingle();
    if (retry) return retry.id;
  }
  return null;
}

// Verhindert fehlerhafte Ensemble-Anlagen wie "**Chor**" oder ein
// alleinstehendes "Orchester" (live im Bestand aufgefallen, Nutzer-Meldung
// "solche Ensembles dürfen nicht vorkommen") — quellenunabhängig, da JEDE
// hydrate-*-events-Funktion Ensemble-Namen aus Fremdtext übernimmt.
const GENERIC_ENSEMBLE_NAMES = new Set(["chor", "chöre", "orchester", "ballett", "ensemble", "choreographie", "choreografie"]);

export async function resolveEnsembles(supabase: SupabaseClient, rawName: string): Promise<string[]> {
  const assessment = assessEnsembleName(rawName);
  const name = assessment.cleaned;
  if (!assessment.safe || GENERIC_ENSEMBLE_NAMES.has(name.toLocaleLowerCase("de"))) return [];
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
  const { data: created, error: insertError } = await supabase.from("ensembles").insert({
    name, slug: await uniqueSlug(supabase, "ensembles", name), type, is_verified: false,
  }).select("id").single();
  if (created?.id) return [created.id];
  // Race mit einem gleichzeitigen resolveEnsembles()-Aufruf für dasselbe
  // Hausensemble — passiert besonders oft beim allerersten Sync-Lauf einer
  // Quelle, wenn mehrere Events mit demselben Hausorchester (z.B. "Münchener
  // Kammerorchester" bei jedem MKO-Event) gleichzeitig verarbeitet werden.
  // Siehe gleiche Absicherung in resolvePerson() oben.
  if (insertError) {
    const { data: retry } = await supabase.from("ensembles").select("id").ilike("name", name).maybeSingle();
    if (retry) return [retry.id];
  }
  return [];
}

export async function uniqueSlug(supabase: SupabaseClient, table: string, name: string): Promise<string> {
  const base = name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/ß/g, "ss").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 70) || "eintrag";
  for (let i = 0; i < 30; i++) {
    const slug = i ? `${base}-${i + 1}` : base;
    const { data } = await supabase.from(table).select("id").eq("slug", slug).maybeSingle();
    if (!data) return slug;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

/** Ersetzt event_participants für ein Event vollständig durch die frisch
 * geparsten Kandidaten — nur wenn tatsächlich Kandidaten vorhanden sind (nie
 * bei einer unvollständig geladenen Seite alte, aber korrekte Daten löschen).
 * Gibt die Anzahl neu eingefügter Zeilen zurück. */
export async function replaceEventParticipants(
  supabase: SupabaseClient,
  eventId: string,
  participants: EventParticipantCandidate[],
): Promise<number> {
  if (participants.length === 0) return 0;
  await supabase.from("event_participants").delete().eq("event_id", eventId);
  let added = 0;
  for (const [index, participant] of participants.entries()) {
    const entityIds = participant.type === "person"
      ? [await resolvePerson(supabase, participant)].filter((id): id is string => id !== null)
      : await resolveEnsembles(supabase, participant.name);
    if (entityIds.length === 0) continue;
    const column = participant.type === "person" ? "person_id" : "ensemble_id";
    for (const [resolvedIndex, entityId] of entityIds.entries()) {
      // Guard gegen doppelte Kandidaten INNERHALB desselben Parse-Durchlaufs
      // (z.B. dieselbe Person zweimal genannt) — ohne diesen Check könnte ein
      // zweiter Insert an einem Unique-Constraint (event_id, person_id/
      // ensemble_id) scheitern, statt die bestehende Zeile zu aktualisieren.
      const { data: existing } = await supabase.from("event_participants").select("id")
        .eq("event_id", eventId).eq(column, entityId).maybeSingle();
      if (existing) {
        await supabase.from("event_participants").update({ role: participant.role, display_order: index + resolvedIndex }).eq("id", existing.id);
        continue;
      }
      const { error: insertError } = await supabase.from("event_participants").insert({
        event_id: eventId,
        person_id: participant.type === "person" ? entityId : null,
        ensemble_id: participant.type === "ensemble" ? entityId : null,
        role: participant.role,
        display_order: index + resolvedIndex,
      });
      if (!insertError) added++;
    }
  }
  return added;
}

export async function mapLimit<T, R>(items: T[], concurrency: number, fn: (item: T) => Promise<R>): Promise<R[]> {
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

export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
