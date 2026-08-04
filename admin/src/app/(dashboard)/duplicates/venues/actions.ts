"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { repointFieldProvenance } from "@/lib/merge-provenance";
import { logSystemAction } from "@/lib/system-log";

// Analog zu duplicates/persons/actions.ts FK_REFS — alle Tabellen mit einer
// echten venue_id-Fremdschlüsselspalte (siehe Migrationen 20260715000008/
// 20260715000009/20260715000006/20260715000011/20260722000001/
// 20260818000004). user_favorite_venues/profile_interest_venues haben ein
// zusammengesetztes (user_id, venue_id)-Primärschlüssel — bei einer Person,
// die BEIDE Venues bereits favorisiert hat, kann das Update hier wie beim
// bestehenden Personen-Merge kollidieren (nicht abgefangen, gleiche
// akzeptierte Einschränkung wie dort).
const FK_REFS: Array<{ table: string; column: string }> = [
  { table: "events", column: "venue_id" },
  { table: "sources", column: "venue_id" },
  { table: "ensembles", column: "home_venue_id" },
  { table: "user_favorite_venues", column: "venue_id" },
  { table: "profile_interest_venues", column: "venue_id" },
  { table: "entity_candidates", column: "suggested_venue_id" },
];

export async function resolveVenueDuplicateAsMerged(candidateId: string, keepVenueId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("venue_duplicate_candidates")
    .select("venue_a_id, venue_b_id")
    .eq("id", candidateId)
    .maybeSingle();
  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Venue-Duplikat-Kandidat nicht gefunden");
  }
  if (keepVenueId !== candidate.venue_a_id && keepVenueId !== candidate.venue_b_id) {
    throw new Error("Ausgewählte Venue gehört nicht zu diesem Kandidaten");
  }
  const deleteVenueId = keepVenueId === candidate.venue_a_id ? candidate.venue_b_id : candidate.venue_a_id;

  const { data: deletedVenue } = await supabase
    .from("venues")
    .select("name")
    .eq("id", deleteVenueId)
    .maybeSingle();

  for (const { table, column } of FK_REFS) {
    const { error } = await supabase.from(table).update({ [column]: keepVenueId }).eq(column, deleteVenueId);
    if (error) throw new Error(`Repoint ${table}.${column} fehlgeschlagen: ${error.message}`);
  }

  // Bilder/Provenienz sind polymorph (origin_type/entity_type + id), keine
  // deklarierte FK — manuelles Umbiegen statt FK_REFS-Loop.
  await supabase.from("images").update({ origin_id: keepVenueId }).eq("origin_type", "venue").eq("origin_id", deleteVenueId);
  await repointFieldProvenance(supabase, "venue", keepVenueId, deleteVenueId);

  if (deletedVenue?.name) {
    await supabase
      .from("entity_aliases")
      .insert({ entity_type: "venue", entity_id: keepVenueId, alias: deletedVenue.name })
      .select("id")
      .maybeSingle(); // best effort — Alias existiert ggf. schon
  }

  const { error: candidateUpdateError } = await supabase
    .from("venue_duplicate_candidates")
    .update({ status: "merged", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (candidateUpdateError) throw new Error(candidateUpdateError.message);

  const { error: deleteError } = await supabase.from("venues").delete().eq("id", deleteVenueId);
  if (deleteError) throw new Error(deleteError.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "venue_duplicate_candidate",
    entityId: candidateId,
    action: "merged",
    actor: user?.email ?? user?.id ?? "unknown",
    before: { deleted_venue_id: deleteVenueId, kept_venue_id: keepVenueId, alias_added: deletedVenue?.name },
  });

  revalidatePath("/duplicates/venues");
}

export async function resolveVenueDuplicateAsDistinct(candidateId: string) {
  const supabase = await createClient();

  const { error } = await supabase
    .from("venue_duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "venue_duplicate_candidate",
    entityId: candidateId,
    action: "dismissed",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/duplicates/venues");
}
