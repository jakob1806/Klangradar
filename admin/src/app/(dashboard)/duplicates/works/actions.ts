"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

// work_a_id ist immer das ältere/bereits existierende Werk, work_b_id das
// neu angelegte — siehe die Kandidaten-Anlage in enrich-event-references/
// index.ts. "Zusammenführen" behält work_a, biegt alle Referenzen auf
// work_b um und löscht work_b danach (gleiche Reihenfolge wie beim
// FK-Repointing in resolve-person-duplicates: erst umbiegen, dann löschen).
export async function resolveWorkDuplicateAsMerged(candidateId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("work_duplicate_candidates")
    .select("work_a_id, work_b_id")
    .eq("id", candidateId)
    .maybeSingle();

  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Werk-Duplikat-Kandidat nicht gefunden");
  }
  const { work_a_id: workAId, work_b_id: workBId } = candidate;

  // event_works hat PK (event_id, work_id, position) — ein Umbiegen auf
  // work_a_id kann kollidieren, wenn dasselbe Event work_a bereits (an
  // irgendeiner Position) verlinkt hat. In dem Fall die work_b-Verlinkung
  // stattdessen löschen, statt einen PK-Konflikt zu riskieren.
  const { data: workBLinks } = await supabase
    .from("event_works")
    .select("event_id, position")
    .eq("work_id", workBId);

  for (const link of workBLinks ?? []) {
    const { data: existing } = await supabase
      .from("event_works")
      .select("event_id")
      .eq("event_id", link.event_id)
      .eq("work_id", workAId)
      .maybeSingle();

    if (existing) {
      await supabase
        .from("event_works")
        .delete()
        .eq("event_id", link.event_id)
        .eq("work_id", workBId)
        .eq("position", link.position);
    } else {
      await supabase
        .from("event_works")
        .update({ work_id: workAId })
        .eq("event_id", link.event_id)
        .eq("work_id", workBId)
        .eq("position", link.position);
    }
  }

  // program_items hat eine eigene id als PK, kein Kollisionsrisiko.
  const { error: programItemsError } = await supabase
    .from("program_items")
    .update({ work_id: workAId })
    .eq("work_id", workBId);
  if (programItemsError) throw new Error(programItemsError.message);

  // field_provenance referenziert generisch über (entity_type, entity_id),
  // kein FK — muss beim Merge separat mitgezogen werden.
  const { error: provenanceError } = await supabase
    .from("field_provenance")
    .update({ entity_id: workAId })
    .eq("entity_type", "work")
    .eq("entity_id", workBId);
  if (provenanceError) throw new Error(provenanceError.message);

  const { error: candidateUpdateError } = await supabase
    .from("work_duplicate_candidates")
    .update({ status: "merged", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (candidateUpdateError) throw new Error(candidateUpdateError.message);

  const { error: deleteError } = await supabase.from("works").delete().eq("id", workBId);
  if (deleteError) throw new Error(deleteError.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "work_duplicate_candidate",
    entityId: candidateId,
    action: "merged",
    actor: user?.email ?? user?.id ?? "unknown",
    before: { deleted_work_id: workBId, kept_work_id: workAId },
  });

  revalidatePath("/duplicates/works");
}

export async function resolveWorkDuplicateAsDistinct(candidateId: string) {
  const supabase = await createClient();

  const { error } = await supabase
    .from("work_duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "work_duplicate_candidate",
    entityId: candidateId,
    action: "dismissed",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/duplicates/works");
}
