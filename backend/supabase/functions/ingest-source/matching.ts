// Venue-/Event-Matching für den Ingestion-Worker. Wrappt die zwei
// pg_trgm-basierten RPCs aus der Migration 20260802000001.

import type { RawEvent } from "./types.ts";

interface SourceRow {
  id: string;
  venue_id: string | null;
  person_id?: string | null;
  ensemble_id?: string | null;
  city_id?: string | null;
}

// Adress-Plausibilitätscheck pro Stadt (regions.slug). Quellen ohne city_id
// stammen aus der Zeit vor der Mehrstädte-Erweiterung und sind München.
const CITY_ADDRESS_PATTERNS: Record<string, RegExp> = {
  munich: /münchen|munich|muenchen/i,
  berlin: /berlin/i,
  hamburg: /hamburg/i,
  frankfurt: /frankfurt/i,
  vienna: /wien|vienna/i,
};

const citySlugCache = new Map<string, string | null>();
let munichIdCache: string | null | undefined;

// deno-lint-ignore no-explicit-any
async function munichCityId(supabase: any): Promise<string | null> {
  if (munichIdCache === undefined) {
    const { data } = await supabase.from("regions").select("id").eq("type", "city").eq("slug", "munich").maybeSingle();
    munichIdCache = data?.id ?? null;
  }
  return munichIdCache ?? null;
}

// deno-lint-ignore no-explicit-any
async function citySlugFor(supabase: any, cityId: string | null | undefined): Promise<string> {
  if (!cityId) return "munich";
  if (!citySlugCache.has(cityId)) {
    const { data } = await supabase.from("regions").select("slug").eq("id", cityId).maybeSingle();
    citySlugCache.set(cityId, data?.slug ?? null);
  }
  return citySlugCache.get(cityId) ?? "munich";
}

export async function resolveVenue(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  source: SourceRow,
  raw: RawEvent,
): Promise<{ venueId: string; viaFixedSourceVenue: boolean } | { error: string }> {
  if (source.venue_id) {
    // Explicitly configured on the source — always trusted, no city check.
    // Every source we run is either dedicated to one specific (Munich)
    // venue this way, or has no venue_id and relies on the fuzzy path below.
    return { venueId: source.venue_id, viaFixedSourceVenue: true };
  }

  if (!raw.venueName) {
    return { error: "no venue_id on source and RawEvent has no venueName to match against" };
  }

  // Stadt-Filter für Quellen ohne feste venue_id (z.B. ein Tourkalender mit
  // Terminen in mehreren Städten): Seit der Mehrstädte-Erweiterung enthält
  // venues Spielstätten aus fünf Städten, ein generischer Name wie
  // "Konzerthaus" würde sonst über Stadtgrenzen hinweg treffen. Liefert die
  // Quelle eine venueAddress, die eindeutig NICHT ihre Stadt erwähnt, wird
  // abgelehnt (bisher war das fest auf München verdrahtet und hat dadurch
  // jedes Event aller Berliner/Wiener/... Quellen verworfen).
  const citySlug = await citySlugFor(supabase, source.city_id);
  const cityPattern = CITY_ADDRESS_PATTERNS[citySlug];
  if (raw.venueAddress && cityPattern && !cityPattern.test(raw.venueAddress)) {
    return {
      error:
        `venueAddress '${raw.venueAddress}' does not mention the source's city (${citySlug}) — refusing to match against another city's venues`,
    };
  }

  const { data, error } = await supabase.rpc("find_matching_venue", {
    p_name: raw.venueName,
    p_result_limit: 25,
  });

  if (error) {
    return { error: `find_matching_venue RPC failed: ${error.message}` };
  }

  let candidates = data ?? [];
  if (candidates.length > 0) {
    const { data: cityRows } = await supabase
      .from("venues")
      .select("id, city_id")
      .in("id", candidates.map((c: { id: string }) => c.id));
    const cityById = new Map((cityRows ?? []).map((v: { id: string; city_id: string | null }) => [v.id, v.city_id]));
    const munichId = await munichCityId(supabase);
    const wantedCity = source.city_id ?? munichId;
    candidates = candidates.filter((c: { id: string }) => {
      const venueCity = cityById.get(c.id) ?? null;
      // Ältere Venues ohne city_id gelten als München.
      return wantedCity == null || (venueCity ?? munichId) === wantedCity;
    });
  }

  const best = candidates[0];
  if (!best || best.similarity < 0.5) {
    return { error: `no venue match for '${raw.venueName}'` };
  }

  return { venueId: best.id, viaFixedSourceVenue: false };
}

export async function findEventMatch(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  title: string,
  venueId: string,
  startDateTime: string,
  castNames?: string[] | null,
): Promise<{ id: string; similarity: number } | null> {
  // Nutzerfeedback: "ich habe das gefühl, dass nach wie vor einige
  // duplikate entstehen. auch durch quellen wie concerti oder IN münchen,
  // die gesammelte konzertdaten zur verfügung bereitstellen." Konkret
  // nachvollzogen: die zwei venuelosen Aggregator-Quellen "Concerti
  // München" und "IN-Muenchen (nur Klassik)" formulieren Titel oft
  // komplett anders als die Original-Quelle des Veranstaltungsorts (z.B.
  // ein einzelnes Programmwerk statt des Konzerttitels) — die
  // Kandidaten brauchen ein inhaltliches Signal. Die frühere Schwelle 0
  // gab jedes Event desselben Venues im +/-2h-Fenster zurück; dadurch
  // wurden parallele Vorstellungen und aufeinanderfolgende Führungen als
  // vermeintliche Duplikate angezeigt. Die RPC kombiniert Titel,
  // Teilstring und Besetzung und liefert erst ab 0.35 einen Kandidaten.
  const { data, error } = await supabase.rpc("find_matching_event", {
    p_title: title,
    p_venue_id: venueId,
    p_start_datetime: startDateTime,
    p_cast_names: castNames && castNames.length > 0 ? castNames : null,
    p_similarity_threshold: 0.35,
  });

  if (error) {
    // Matching is best-effort — a failed lookup should fall through to
    // "no match" (create as new) rather than abort the whole event.
    console.error(`find_matching_event RPC failed: ${error.message}`);
    return null;
  }

  const best = (data ?? [])[0];
  return best ? { id: best.id, similarity: best.similarity } : null;
}
