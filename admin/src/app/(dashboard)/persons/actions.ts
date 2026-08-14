"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// full_name bleibt die einzige Quelle für Fuzzy-Matching (find_matching_person),
// Duplikat-Auflösung (resolve-person-duplicates), Volltextsuche (search_vector)
// und Sortierung in Admin/Flutter-App/nativer App — wird hier aus den drei
// strukturierten Feldern zusammengesetzt, damit alle bestehenden Lesepfade
// unverändert weiterfunktionieren, ohne dass irgendwo full_name manuell
// gepflegt werden muss.
function readPersonFields(formData: FormData) {
  const first_name = String(formData.get("first_name") ?? "").trim();
  const middle_name = String(formData.get("middle_name") ?? "").trim() || null;
  const last_name = String(formData.get("last_name") ?? "").trim();
  return {
    slug: String(formData.get("slug") ?? "").trim(),
    first_name,
    middle_name,
    last_name,
    full_name: [first_name, middle_name, last_name].filter(Boolean).join(" "),
    // TagInput schreibt die Rollen kommagetrennt in ein einzelnes verstecktes
    // Feld statt mehrerer gleichnamiger Checkbox-Werte (siehe tag-input.tsx).
    roles: String(formData.get("roles") ?? "").split(",").map((r) => r.trim()).filter(Boolean),
    instrument: String(formData.get("instrument") ?? "").trim() || null,
    nationality: String(formData.get("nationality") ?? "").trim() || null,
    birth_date: String(formData.get("birth_date") ?? "") || null,
    death_date: String(formData.get("death_date") ?? "") || null,
    is_deceased: formData.get("is_deceased") === "on",
    biography_de: String(formData.get("biography_de") ?? "").trim() || null,
    website_url: String(formData.get("website_url") ?? "").trim() || null,
    photo_url: String(formData.get("photo_url") ?? "").trim() || null,
    member_of_ensemble_id: String(formData.get("member_of_ensemble_id") ?? "") || null,
    is_verified: formData.get("is_verified") === "on",
  };
}

export async function createPerson(formData: FormData) {
  const f = readPersonFields(formData);
  const supabase = await createClient();
  const { error } = await supabase.from("persons").insert(f);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
  redirect("/persons");
}

export async function updatePerson(personId: string, formData: FormData) {
  const f = readPersonFields(formData);
  const supabase = await createClient();
  const { error } = await supabase
    .from("persons")
    .update({ ...f, updated_at: new Date().toISOString() })
    .eq("id", personId);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
  redirect("/persons");
}

export interface PersonDeleteInfo {
  events: { id: string; title: string }[];
  works: { id: string; title: string }[];
  sources: { id: string; name: string }[];
  candidateCount: number;
}

// event_participants.person_id/sources.person_id/works.composer_id/
// entity_candidates.created_person_id haben KEIN ON DELETE CASCADE. Gleiches
// Verhalten wie bei Ensembles (siehe ensembles/actions.ts,
// getEnsembleDeleteInfo/detachEnsembleReferences): erst zeigen, was noch
// verknüpft ist, dann trotzdem löschen dürfen statt zu blockieren.
export async function getPersonDeleteInfo(personId: string): Promise<PersonDeleteInfo> {
  const supabase = await createClient();
  const [{ data: participants }, { data: works }, { data: sources }, { count: candidateCount }] = await Promise.all([
    supabase
      .from("event_participants")
      .select("events(id, title)")
      .eq("person_id", personId)
      .returns<{ events: { id: string; title: string } | null }[]>(),
    supabase.from("works").select("id, title").eq("composer_id", personId).returns<{ id: string; title: string }[]>(),
    supabase.from("sources").select("id, name").eq("person_id", personId).returns<{ id: string; name: string }[]>(),
    supabase
      .from("entity_candidates")
      .select("id", { count: "exact", head: true })
      .eq("created_person_id", personId),
  ]);

  const eventMap = new Map<string, string>();
  for (const p of participants ?? []) {
    if (p.events) eventMap.set(p.events.id, p.events.title);
  }

  return {
    events: Array.from(eventMap, ([id, title]) => ({ id, title })),
    works: works ?? [],
    sources: sources ?? [],
    candidateCount: candidateCount ?? 0,
  };
}

/** Löst alle Verweise auf diese Person, bevor sie gelöscht wird —
 * event_participants-Zeilen werden entfernt (die Mitwirkenden-Angabe bei
 * den betroffenen Veranstaltungen verschwindet damit, so gewollt beim
 * bewussten Löschen einer Person), works/sources/entity_candidates werden
 * nur entkoppelt (composer_id/person_id/created_person_id = null), nicht
 * gelöscht — das Werk bzw. die Datenquelle/der Kandidaten-Log-Eintrag
 * selbst bleibt erhalten. */
async function detachPersonReferences(
  supabase: Awaited<ReturnType<typeof createClient>>,
  personId: string,
) {
  await supabase.from("event_participants").delete().eq("person_id", personId);
  await supabase.from("works").update({ composer_id: null }).eq("composer_id", personId);
  await supabase.from("sources").update({ person_id: null }).eq("person_id", personId);
  await supabase.from("entity_candidates").update({ created_person_id: null }).eq("created_person_id", personId);
}

export async function deletePerson(personId: string) {
  const supabase = await createClient();
  await detachPersonReferences(supabase, personId);

  const { error } = await supabase.from("persons").delete().eq("id", personId);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
  redirect("/persons");
}

export async function bulkDeletePersons(ids: string[]) {
  const supabase = await createClient();
  for (const id of ids) {
    await detachPersonReferences(supabase, id);
  }

  const { error } = await supabase.from("persons").delete().in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
}

export async function bulkSetPersonsVerified(ids: string[], verified: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.from("persons").update({ is_verified: verified }).in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
}
