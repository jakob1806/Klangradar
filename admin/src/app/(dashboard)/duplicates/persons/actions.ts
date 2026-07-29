"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { repointFieldProvenance } from "@/lib/merge-provenance";
import { logSystemAction } from "@/lib/system-log";

// Gleiche FK-Liste wie backend/supabase/functions/resolve-person-
// duplicates/index.ts (FK_REFS) — kein gemeinsamer Modul-Raum zwischen
// Edge Functions (Deno) und der Next.js-Admin-App, siehe dortigen
// Kommentar zu slugify() für dasselbe Muster.
const FK_REFS: Array<{ table: string; column: string }> = [
  { table: "works", column: "composer_id" },
  { table: "event_participants", column: "person_id" },
  { table: "user_favorite_persons", column: "person_id" },
  { table: "sources", column: "person_id" },
  { table: "entity_candidates", column: "created_person_id" },
];

/** Nutzeranfrage: "man soll auswählen können, welche Version genommen
 * werden soll — generell bei Zusammenführen". keepPersonId ist deshalb
 * Pflicht-Parameter statt eines impliziten Gewinners. Der verworfene Name
 * wird als Alias auf die behaltene Person gespeichert (gleiche Konvention
 * wie mergeEntityCandidate, entity-candidates/actions.ts), damit er bei
 * der Suche weiter auffindbar bleibt. */
export async function resolvePersonDuplicateAsMerged(candidateId: string, keepPersonId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("person_duplicate_candidates")
    .select("person_a_id, person_b_id")
    .eq("id", candidateId)
    .maybeSingle();
  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Personen-Duplikat-Kandidat nicht gefunden");
  }
  if (keepPersonId !== candidate.person_a_id && keepPersonId !== candidate.person_b_id) {
    throw new Error("Ausgewählte Person gehört nicht zu diesem Kandidaten");
  }
  const deletePersonId = keepPersonId === candidate.person_a_id ? candidate.person_b_id : candidate.person_a_id;

  const { data: deletedPerson } = await supabase
    .from("persons")
    .select("full_name")
    .eq("id", deletePersonId)
    .maybeSingle();

  for (const { table, column } of FK_REFS) {
    const { error } = await supabase.from(table).update({ [column]: keepPersonId }).eq(column, deletePersonId);
    if (error) throw new Error(`Repoint ${table}.${column} fehlgeschlagen: ${error.message}`);
  }

  await repointFieldProvenance(supabase, "person", keepPersonId, deletePersonId);

  if (deletedPerson?.full_name) {
    await supabase
      .from("entity_aliases")
      .insert({ entity_type: "person", entity_id: keepPersonId, alias: deletedPerson.full_name })
      .select("id")
      .maybeSingle(); // best effort — Alias existiert ggf. schon
  }

  const { error: candidateUpdateError } = await supabase
    .from("person_duplicate_candidates")
    .update({ status: "merged", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (candidateUpdateError) throw new Error(candidateUpdateError.message);

  const { error: deleteError } = await supabase.from("persons").delete().eq("id", deletePersonId);
  if (deleteError) throw new Error(deleteError.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "person_duplicate_candidate",
    entityId: candidateId,
    action: "merged",
    actor: user?.email ?? user?.id ?? "unknown",
    before: { deleted_person_id: deletePersonId, kept_person_id: keepPersonId, alias_added: deletedPerson?.full_name },
  });

  revalidatePath("/duplicates/persons");
}

export async function resolvePersonDuplicateAsDistinct(candidateId: string) {
  const supabase = await createClient();

  const { error } = await supabase
    .from("person_duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "person_duplicate_candidate",
    entityId: candidateId,
    action: "dismissed",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/duplicates/persons");
}
