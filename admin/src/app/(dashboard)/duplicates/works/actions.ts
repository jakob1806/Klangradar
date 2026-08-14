"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { repointFieldProvenance } from "@/lib/merge-provenance";
import { logSystemAction } from "@/lib/system-log";

// Nutzeranfrage: "man soll auswählen können, welche Version genommen
// werden soll — das soll generell bei einer Zusammenführen-Funktion
// gehen". work_a/work_b ist nur die technische Anlage-Reihenfolge (a =
// bereits vorhanden, b = neu angelegt, siehe enrich-event-references/
// index.ts) — welche der beiden Titel/Metadaten inhaltlich richtiger sind,
// weiß nur die Redaktion beim Ansehen. keepWorkId ist deshalb Pflicht-
// Parameter statt eines impliziten "a gewinnt immer".
export async function resolveWorkDuplicateAsMerged(candidateId: string, keepWorkId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("work_duplicate_candidates")
    .select("work_a_id, work_b_id")
    .eq("id", candidateId)
    .maybeSingle();

  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Werk-Duplikat-Kandidat nicht gefunden");
  }
  if (keepWorkId !== candidate.work_a_id && keepWorkId !== candidate.work_b_id) {
    throw new Error("Ausgewähltes Werk gehört nicht zu diesem Kandidaten");
  }
  const workAId = keepWorkId;
  const workBId = keepWorkId === candidate.work_a_id ? candidate.work_b_id : candidate.work_a_id;

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
  await repointFieldProvenance(supabase, "work", workAId, workBId);

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

  revalidatePath("/duplicates");
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

  revalidatePath("/duplicates");
}

/** Mehrfachauswahl-Variante für die konsolidierte Duplikate-Seite. */
export async function resolveWorkDuplicatesAsDistinct(candidateIds: string[]): Promise<{ completed: number }> {
  const uniqueIds = [...new Set(candidateIds)].slice(0, 200);
  if (uniqueIds.length === 0) return { completed: 0 };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("work_duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .in("id", uniqueIds)
    .eq("status", "pending")
    .select("id");
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  for (const row of data ?? []) {
    await logSystemAction(supabase, {
      entityType: "work_duplicate_candidate",
      entityId: row.id,
      action: "dismissed",
      actor: user?.email ?? user?.id ?? "unknown",
    });
  }

  revalidatePath("/duplicates");
  return { completed: data?.length ?? 0 };
}
