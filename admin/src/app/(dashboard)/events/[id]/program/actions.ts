"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

async function nextWorkPosition(
  supabase: Awaited<ReturnType<typeof createClient>>,
  eventId: string,
) {
  const { data } = await supabase
    .from("event_works")
    .select("position")
    .eq("event_id", eventId)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data?.position ?? -1) + 1;
}

export async function addExistingWork(eventId: string, formData: FormData) {
  const workId = String(formData.get("work_id") ?? "");
  const afterIntermission = formData.get("after_intermission") === "on";
  if (!workId) return;

  const supabase = await createClient();
  const position = await nextWorkPosition(supabase, eventId);

  const { error } = await supabase.from("event_works").insert({
    event_id: eventId,
    work_id: workId,
    position,
    after_intermission: afterIntermission,
  });
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}

export async function createWorkAndAdd(eventId: string, formData: FormData) {
  const title = String(formData.get("title") ?? "").trim();
  const composerId = String(formData.get("composer_id") ?? "") || null;
  const catalogNumber = String(formData.get("catalog_number") ?? "").trim() || null;
  const afterIntermission = formData.get("after_intermission_new") === "on";
  if (!title) return;

  const supabase = await createClient();

  const { data: work, error: workError } = await supabase
    .from("works")
    .insert({ title, composer_id: composerId, catalog_number: catalogNumber })
    .select("id")
    .single();
  if (workError) throw new Error(workError.message);

  const position = await nextWorkPosition(supabase, eventId);
  const { error } = await supabase.from("event_works").insert({
    event_id: eventId,
    work_id: work.id,
    position,
    after_intermission: afterIntermission,
  });
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}

/** Vertauscht die Position mit dem direkten Nachbarn — Nutzeranfrage: "man
 * soll die Reihenfolge der Programmpunkte auch immer ändern können". Setzt
 * die verschobene Zeile kurz auf eine unbenutzte Zwischen-Position (-1),
 * um einen PK-Konflikt zu vermeiden, falls (event_id, work_id, position)
 * für einen Moment mit der Zielposition kollidieren würde — analog zum
 * bestehenden event_works-Umbiegen beim Werk-Duplikate-Merge
 * (duplicates/works/actions.ts). after_intermission bleibt unangetastet,
 * es hängt am work_id-Datensatz und wandert dadurch automatisch mit.
 */
export async function moveWork(
  eventId: string,
  workId: string,
  position: number,
  direction: "up" | "down",
) {
  const supabase = await createClient();
  const { data: rows } = await supabase
    .from("event_works")
    .select("work_id, position")
    .eq("event_id", eventId)
    .order("position", { ascending: true });

  const list = rows ?? [];
  const index = list.findIndex((r) => r.work_id === workId && r.position === position);
  const swapIndex = direction === "up" ? index - 1 : index + 1;
  if (index === -1 || swapIndex < 0 || swapIndex >= list.length) return;

  const a = list[index];
  const b = list[swapIndex];

  await supabase.from("event_works").update({ position: -1 }).eq("event_id", eventId).eq("work_id", a.work_id).eq("position", a.position);
  await supabase.from("event_works").update({ position: a.position }).eq("event_id", eventId).eq("work_id", b.work_id).eq("position", b.position);
  await supabase.from("event_works").update({ position: b.position }).eq("event_id", eventId).eq("work_id", a.work_id).eq("position", -1);

  revalidatePath(`/events/${eventId}/program`);
}

export async function removeWork(eventId: string, workId: string, position: number) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("event_works")
    .delete()
    .eq("event_id", eventId)
    .eq("work_id", workId)
    .eq("position", position);
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}

export async function addParticipant(eventId: string, formData: FormData) {
  const personId = String(formData.get("person_id") ?? "") || null;
  const ensembleId = String(formData.get("ensemble_id") ?? "") || null;
  const role = String(formData.get("role") ?? "") || null;
  if (!personId && !ensembleId) return;

  const supabase = await createClient();
  const { error } = await supabase.from("event_participants").insert({
    event_id: eventId,
    person_id: personId,
    ensemble_id: ensembleId,
    role,
  });
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}

export async function removeParticipant(eventId: string, participantId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("event_participants").delete().eq("id", participantId);
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}
