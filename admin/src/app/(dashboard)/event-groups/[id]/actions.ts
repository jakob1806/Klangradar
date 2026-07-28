"use server";

// "Broadcast"-Bearbeitung: eine Aktion hier wirkt auf event_works/
// event_participants ALLER Mitgliedsevents der Gruppe gleichzeitig, statt
// eine eigene programs/program_items-Struktur einzuführen — event_works
// ist an event_id gebunden (siehe events/[id]/program/actions.ts), das
// bleibt für die App-Seite unverändert, hier wird nur mehrfach dieselbe
// Operation ausgeführt. Duplikate pro Event werden übersprungen (nicht
// jedes Event startet zwangsläufig mit demselben Stand).

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

async function memberEventIds(
  supabase: Awaited<ReturnType<typeof createClient>>,
  groupId: string,
): Promise<string[]> {
  const { data } = await supabase.from("events").select("id").eq("program_id", groupId);
  return (data ?? []).map((e) => e.id);
}

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

export async function addExistingWorkToGroup(groupId: string, formData: FormData) {
  const workId = String(formData.get("work_id") ?? "");
  const afterIntermission = formData.get("after_intermission") === "on";
  if (!workId) return;

  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);

  for (const eventId of eventIds) {
    const { data: existing } = await supabase
      .from("event_works")
      .select("event_id")
      .eq("event_id", eventId)
      .eq("work_id", workId)
      .maybeSingle();
    if (existing) continue;

    const position = await nextWorkPosition(supabase, eventId);
    await supabase.from("event_works").insert({
      event_id: eventId,
      work_id: workId,
      position,
      after_intermission: afterIntermission,
    });
  }

  revalidatePath(`/event-groups/${groupId}`);
}

export async function createWorkAndAddToGroup(groupId: string, formData: FormData) {
  const title = String(formData.get("title") ?? "").trim();
  const composerId = String(formData.get("composer_id") ?? "") || null;
  const catalogNumber = String(formData.get("catalog_number") ?? "").trim() || null;
  const afterIntermission = formData.get("after_intermission_new") === "on";
  if (!title) return;

  const supabase = await createClient();

  const { data: work, error } = await supabase
    .from("works")
    .insert({ title, composer_id: composerId, catalog_number: catalogNumber })
    .select("id")
    .single();
  if (error) throw new Error(error.message);

  const eventIds = await memberEventIds(supabase, groupId);
  for (const eventId of eventIds) {
    const position = await nextWorkPosition(supabase, eventId);
    await supabase.from("event_works").insert({
      event_id: eventId,
      work_id: work.id,
      position,
      after_intermission: afterIntermission,
    });
  }

  revalidatePath(`/event-groups/${groupId}`);
}

/** Entfernt das Werk aus JEDEM Mitgliedsevent, das es gerade hat (nicht nur
 * dem, über das der Button geklickt wurde) — die Gruppenansicht zeigt eine
 * deduplizierte Werkliste, "Entfernen" soll sich deshalb auf die ganze
 * Gruppe beziehen. */
export async function removeWorkFromGroup(groupId: string, workId: string) {
  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);
  if (eventIds.length === 0) return;

  const { error } = await supabase.from("event_works").delete().eq("work_id", workId).in("event_id", eventIds);
  if (error) throw new Error(error.message);

  revalidatePath(`/event-groups/${groupId}`);
}

export async function addParticipantToGroup(groupId: string, formData: FormData) {
  const personId = String(formData.get("person_id") ?? "") || null;
  const ensembleId = String(formData.get("ensemble_id") ?? "") || null;
  const role = String(formData.get("role") ?? "") || null;
  if (!personId && !ensembleId) return;

  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);

  for (const eventId of eventIds) {
    let query = supabase.from("event_participants").select("id").eq("event_id", eventId);
    query = personId ? query.eq("person_id", personId) : query.eq("ensemble_id", ensembleId);
    const { data: existing } = await query.maybeSingle();
    if (existing) continue;

    await supabase.from("event_participants").insert({
      event_id: eventId,
      person_id: personId,
      ensemble_id: ensembleId,
      role,
    });
  }

  revalidatePath(`/event-groups/${groupId}`);
}

export async function removeParticipantFromGroup(
  groupId: string,
  personId: string | null,
  ensembleId: string | null,
) {
  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);
  if (eventIds.length === 0) return;

  let query = supabase.from("event_participants").delete().in("event_id", eventIds);
  query = personId ? query.eq("person_id", personId) : query.eq("ensemble_id", ensembleId);
  const { error } = await query;
  if (error) throw new Error(error.message);

  revalidatePath(`/event-groups/${groupId}`);
}
