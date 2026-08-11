"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readEnsembleFields(formData: FormData) {
  return {
    slug: String(formData.get("slug") ?? "").trim(),
    name: String(formData.get("name") ?? "").trim(),
    type: String(formData.get("type") ?? "sonstiges"),
    description_de: String(formData.get("description_de") ?? "").trim() || null,
    founded_year: formData.get("founded_year") ? Number(formData.get("founded_year")) : null,
    member_count: formData.get("member_count") ? Number(formData.get("member_count")) : null,
    home_venue_id: String(formData.get("home_venue_id") ?? "") || null,
    parent_ensemble_id: String(formData.get("parent_ensemble_id") ?? "") || null,
    website_url: String(formData.get("website_url") ?? "").trim() || null,
    photo_url: String(formData.get("photo_url") ?? "").trim() || null,
    is_verified: formData.get("is_verified") === "on",
  };
}

export async function createEnsemble(formData: FormData) {
  const f = readEnsembleFields(formData);
  const supabase = await createClient();
  const { error } = await supabase.from("ensembles").insert(f);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
  redirect("/ensembles");
}

export async function updateEnsemble(ensembleId: string, formData: FormData) {
  const f = readEnsembleFields(formData);
  const supabase = await createClient();
  const { error } = await supabase
    .from("ensembles")
    .update({ ...f, updated_at: new Date().toISOString() })
    .eq("id", ensembleId);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
  redirect("/ensembles");
}

export interface EnsembleDeleteInfo {
  events: { id: string; title: string }[];
  sources: { id: string; name: string }[];
  candidateCount: number;
}

// event_participants.ensemble_id/sources.ensemble_id/
// entity_candidates.created_ensemble_id haben KEIN ON DELETE CASCADE
// (bewusst so in den jeweiligen Migrationen). Nutzerwunsch nach einem
// ersten Anlauf mit einer reinen Blockier-Fehlermeldung: "diese
// fehlermeldung soll es nicht geben, man soll sehen, was damit verknüpft
// ist, oder es trotzdem löschen dürfen" — Löschen ist jetzt IMMER möglich,
// aber erst nachdem die Redaktion gesehen hat, was mitbetroffen ist (siehe
// getEnsembleDeleteInfo, vom Client vor der finalen Bestätigung aufgerufen).
export async function getEnsembleDeleteInfo(ensembleId: string): Promise<EnsembleDeleteInfo> {
  const supabase = await createClient();
  const [{ data: participants }, { data: sources }, { count: candidateCount }] = await Promise.all([
    supabase
      .from("event_participants")
      .select("events(id, title)")
      .eq("ensemble_id", ensembleId)
      .returns<{ events: { id: string; title: string } | null }[]>(),
    supabase.from("sources").select("id, name").eq("ensemble_id", ensembleId).returns<{ id: string; name: string }[]>(),
    supabase
      .from("entity_candidates")
      .select("id", { count: "exact", head: true })
      .eq("created_ensemble_id", ensembleId),
  ]);

  const eventMap = new Map<string, string>();
  for (const p of participants ?? []) {
    if (p.events) eventMap.set(p.events.id, p.events.title);
  }

  return {
    events: Array.from(eventMap, ([id, title]) => ({ id, title })),
    sources: sources ?? [],
    candidateCount: candidateCount ?? 0,
  };
}

/** Löst alle Verweise auf dieses Ensemble, bevor es gelöscht wird —
 * event_participants-Zeilen werden entfernt (die Mitwirkenden-Angabe bei
 * den betroffenen Veranstaltungen verschwindet damit, das ist beim
 * bewussten Löschen eines Ensembles so gewollt), sources/entity_candidates
 * werden nur entkoppelt (ensemble_id/created_ensemble_id = null), nicht
 * gelöscht — die Datenquelle bzw. der Kandidaten-Log-Eintrag selbst bleibt
 * erhalten. */
async function detachEnsembleReferences(
  supabase: Awaited<ReturnType<typeof createClient>>,
  ensembleId: string,
) {
  await supabase.from("event_participants").delete().eq("ensemble_id", ensembleId);
  await supabase.from("sources").update({ ensemble_id: null }).eq("ensemble_id", ensembleId);
  await supabase.from("entity_candidates").update({ created_ensemble_id: null }).eq("created_ensemble_id", ensembleId);
}

export async function deleteEnsemble(ensembleId: string) {
  const supabase = await createClient();
  await detachEnsembleReferences(supabase, ensembleId);

  const { error } = await supabase.from("ensembles").delete().eq("id", ensembleId);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
  redirect("/ensembles");
}

export async function bulkDeleteEnsembles(ids: string[]) {
  const supabase = await createClient();
  for (const id of ids) {
    await detachEnsembleReferences(supabase, id);
  }

  const { error } = await supabase.from("ensembles").delete().in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
}

export async function bulkSetEnsemblesVerified(ids: string[], verified: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.from("ensembles").update({ is_verified: verified }).in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
}
