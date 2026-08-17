"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

export async function resolveEnsembleDuplicateAsMerged(candidateId: string, keepEnsembleId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("ensemble_duplicate_candidates")
    .select("ensemble_a_id, ensemble_b_id")
    .eq("id", candidateId)
    .maybeSingle();
  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Ensemble-Duplikat-Kandidat nicht gefunden");
  }
  if (keepEnsembleId !== candidate.ensemble_a_id && keepEnsembleId !== candidate.ensemble_b_id) {
    throw new Error("Ausgewähltes Ensemble gehört nicht zu diesem Kandidaten");
  }
  const deleteEnsembleId =
    keepEnsembleId === candidate.ensemble_a_id ? candidate.ensemble_b_id : candidate.ensemble_a_id;

  const { data: deletedEnsemble } = await supabase
    .from("ensembles")
    .select("name")
    .eq("id", deleteEnsembleId)
    .maybeSingle();

  const { error: mergeError } = await supabase.rpc("merge_ensemble_duplicate_candidate", {
    p_candidate_id: candidateId,
    p_keep_ensemble_id: keepEnsembleId,
  });
  if (mergeError) throw new Error(mergeError.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "ensemble_duplicate_candidate",
    entityId: candidateId,
    action: "merged",
    actor: user?.email ?? user?.id ?? "unknown",
    before: { deleted_ensemble_id: deleteEnsembleId, kept_ensemble_id: keepEnsembleId, alias_added: deletedEnsemble?.name },
  });

  revalidatePath("/duplicates");
}

export async function resolveEnsembleDuplicateAsDistinct(candidateId: string) {
  const supabase = await createClient();

  const { error } = await supabase
    .from("ensemble_duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "ensemble_duplicate_candidate",
    entityId: candidateId,
    action: "dismissed",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/duplicates");
}

/** Mehrfachauswahl-Variante für die konsolidierte Duplikate-Seite. */
export async function resolveEnsembleDuplicatesAsDistinct(candidateIds: string[]): Promise<{ completed: number }> {
  const uniqueIds = [...new Set(candidateIds)].slice(0, 200);
  if (uniqueIds.length === 0) return { completed: 0 };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ensemble_duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .in("id", uniqueIds)
    .eq("status", "pending")
    .select("id");
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  for (const row of data ?? []) {
    await logSystemAction(supabase, {
      entityType: "ensemble_duplicate_candidate",
      entityId: row.id,
      action: "dismissed",
      actor: user?.email ?? user?.id ?? "unknown",
    });
  }

  revalidatePath("/duplicates");
  return { completed: data?.length ?? 0 };
}
