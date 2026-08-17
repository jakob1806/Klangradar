// Venue-/Event-Matching für den Ingestion-Worker. Wrappt die zwei
// pg_trgm-basierten RPCs aus der Migration 20260802000001.

import type { RawEvent } from "./types.ts";

interface SourceRow {
  id: string;
  venue_id: string | null;
  person_id?: string | null;
  ensemble_id?: string | null;
}

const MUNICH_PATTERN = /münchen|munich|muenchen/i;

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

  // München-Filter für externe Quellen ohne feste venue_id (z.B. ein
  // Solist:innen-Tourkalender mit Terminen in mehreren Städten): venues
  // enthält ausschließlich Münchner Spielstätten, ein Name-Fuzzy-Match kann
  // also nie eine andere Stadt "treffen" — das Restrisiko ist ein falscher
  // Positiv-Treffer, wenn ein generischer Venue-Name (z.B. "Konzerthaus")
  // zufällig zu einer Münchner Venue passt, obwohl das Event laut Quelle
  // tatsächlich in einer anderen Stadt stattfindet. Wenn die Quelle eine
  // venueAddress mitliefert, die eindeutig NICHT München erwähnt, ist das
  // ein stärkeres Signal als der Name-Match allein — dann lieber ablehnen
  // (Event wird nicht angelegt) statt fälschlich einer Münchner Venue
  // zuzuordnen.
  if (raw.venueAddress && !MUNICH_PATTERN.test(raw.venueAddress)) {
    return {
      error:
        `venueAddress '${raw.venueAddress}' does not mention München/Munich — refusing to match against a Munich-only venue list`,
    };
  }

  const { data, error } = await supabase.rpc("find_matching_venue", {
    p_name: raw.venueName,
  });

  if (error) {
    return { error: `find_matching_venue RPC failed: ${error.message}` };
  }

  const best = (data ?? [])[0];
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
