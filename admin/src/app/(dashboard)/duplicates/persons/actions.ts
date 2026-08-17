"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

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

  // Ein einziger DB-Aufruf ist entscheidend: dort werden kollidierende
  // Event-/Favoriten-Zeilen zuerst dedupliziert und der gesamte Merge laeuft
  // in einer Transaktion. Ein Fehler kann daher keinen halben Merge mehr
  // hinterlassen.
  const { error: mergeError } = await supabase.rpc("merge_person_duplicate_candidate", {
    p_candidate_id: candidateId,
    p_keep_person_id: keepPersonId,
  });
  if (mergeError) throw new Error(mergeError.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "person_duplicate_candidate",
    entityId: candidateId,
    action: "merged",
    actor: user?.email ?? user?.id ?? "unknown",
    before: { deleted_person_id: deletePersonId, kept_person_id: keepPersonId, alias_added: deletedPerson?.full_name },
  });

  revalidatePath("/duplicates");
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

  revalidatePath("/duplicates");
}

/** Mehrfachauswahl-Variante für die konsolidierte Duplikate-Seite (/duplicates,
 * Reiter Personen) — siehe resolveDuplicatesAsDistinct in ../actions.ts für
 * die Begründung, warum nur "als unterschiedlich markieren" bulkfähig ist. */
export async function resolvePersonDuplicatesAsDistinct(candidateIds: string[]): Promise<{ completed: number }> {
  const uniqueIds = [...new Set(candidateIds)].slice(0, 200);
  if (uniqueIds.length === 0) return { completed: 0 };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("person_duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .in("id", uniqueIds)
    .eq("status", "pending")
    .select("id");
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  for (const row of data ?? []) {
    await logSystemAction(supabase, {
      entityType: "person_duplicate_candidate",
      entityId: row.id,
      action: "dismissed",
      actor: user?.email ?? user?.id ?? "unknown",
    });
  }

  revalidatePath("/duplicates");
  return { completed: data?.length ?? 0 };
}
