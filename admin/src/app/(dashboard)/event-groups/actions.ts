"use server";

// Nutzt die vorhandene programs-Tabelle + events.program_id (seit Phase 0
// angelegt, aber bisher komplett ungenutzt — 0 Zeilen) als "Aufführungs-
// serie": mehrere Termine derselben Produktion (z.B. Opernfestspiele-
// Vorstellungen an mehreren Tagen mit identischem Programm) teilen sich
// eine programs-Zeile über program_id. Datenfelder wie Preis/Venue bleiben
// bewusst pro Event (können sich zwischen Terminen unterscheiden) — nur
// Werke/Mitwirkende werden über die Gruppe hinweg geteilt bearbeitet, siehe
// [id]/actions.ts.

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { cleanupEventGroupIfEmpty } from "@/lib/event-group-cleanup";

export async function createEventGroup(name: string, eventIds: string[]) {
  if (!name.trim() || eventIds.length === 0) return;
  const supabase = await createClient();

  const { data: program, error } = await supabase
    .from("programs")
    .insert({ title: name.trim() })
    .select("id")
    .single();
  if (error) throw new Error(error.message);

  const { error: linkError } = await supabase
    .from("events")
    .update({ program_id: program.id })
    .in("id", eventIds);
  if (linkError) throw new Error(linkError.message);

  revalidatePath("/event-groups");
}

export async function addEventToGroup(groupId: string, eventId: string) {
  if (!eventId) return;
  const supabase = await createClient();
  const { error } = await supabase.from("events").update({ program_id: groupId }).eq("id", eventId);
  if (error) throw new Error(error.message);

  revalidatePath(`/event-groups/${groupId}`);
  revalidatePath("/event-groups");
}

export async function removeEventFromGroup(groupId: string, eventId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("events").update({ program_id: null }).eq("id", eventId);
  if (error) throw new Error(error.message);

  // Nutzer-Meldung "es bestehen eventgruppen mit keinen terminen" (z.B.
  // "Finding Neverland" · 0 Termine) — Aushängen des letzten Mitglieds ließ
  // die Gruppe bisher als leere Zeile stehen, siehe event-group-cleanup.ts.
  await cleanupEventGroupIfEmpty(supabase, groupId);

  revalidatePath(`/event-groups/${groupId}`);
  revalidatePath("/event-groups");
}

/** Nutzeranfrage: "eventgruppen soll man auch zusammenführen können. zb.
 * habe ich zwei gruppen zauberflöte, bei denen aber zwischen den beiden
 * blöcken mehr als 14 tage dazwischen liegen, weshalb sie nicht
 * zusammengehen" — die 14-Tage-Lücke in suggestEventGroups() verhindert nur
 * den AUTOMATISCHEN Vorschlag für noch ungruppierte Events, ist aber keine
 * Regel für bereits angelegte Gruppen. Werke/Mitwirkende/Bilder hängen alle
 * an event_id, nicht an program_id (siehe [id]/actions.ts-Kommentar
 * "Broadcast"-Bearbeitung) — Zusammenführen ist deshalb rein ein Umhängen
 * aller Termine der Quellgruppe auf die Zielgruppe, ohne Datenverlust bei
 * Werken/Mitwirkenden/Bildern der einzelnen Termine.
 */
async function mergeOneGroup(
  supabase: Awaited<ReturnType<typeof createClient>>,
  sourceGroupId: string,
  targetGroupId: string,
) {
  const { error: moveError } = await supabase
    .from("events")
    .update({ program_id: targetGroupId })
    .eq("program_id", sourceGroupId);
  if (moveError) throw new Error(moveError.message);

  const { error: deleteError } = await supabase.from("programs").delete().eq("id", sourceGroupId);
  if (deleteError) throw new Error(deleteError.message);
}

export async function mergeEventGroups(sourceGroupId: string, targetGroupId: string) {
  if (!sourceGroupId || !targetGroupId || sourceGroupId === targetGroupId) return;
  const supabase = await createClient();
  await mergeOneGroup(supabase, sourceGroupId, targetGroupId);

  revalidatePath("/event-groups");
  revalidatePath(`/event-groups/${targetGroupId}`);
}

/** Nutzeranfrage: "automatische vorschläge zum zusammenführen beim gleichen
 * standort und gleichem programm" — Übernahme eines kompletten
 * suggestGroupMerges()-Vorschlags (mehrere Quellgruppen auf einmal in
 * dieselbe Zielgruppe), statt den einzelnen mergeEventGroups()-Aufruf pro
 * Quellgruppe manuell zu wiederholen. */
export async function mergeEventGroupsBatch(targetGroupId: string, sourceGroupIds: string[]) {
  if (!targetGroupId || sourceGroupIds.length === 0) return;
  const supabase = await createClient();
  for (const sourceGroupId of sourceGroupIds) {
    if (sourceGroupId === targetGroupId) continue;
    await mergeOneGroup(supabase, sourceGroupId, targetGroupId);
  }

  revalidatePath("/event-groups");
  revalidatePath(`/event-groups/${targetGroupId}`);
}

/** programs hat keine ON DELETE CASCADE auf events.program_id — erst alle
 * Mitglieder aushängen, dann die Gruppe selbst löschen, sonst schlägt der
 * Delete am FK fehl. */
export async function deleteEventGroup(groupId: string) {
  const supabase = await createClient();

  const { error: unlinkError } = await supabase
    .from("events")
    .update({ program_id: null })
    .eq("program_id", groupId);
  if (unlinkError) throw new Error(unlinkError.message);

  const { error } = await supabase.from("programs").delete().eq("id", groupId);
  if (error) throw new Error(error.message);

  revalidatePath("/event-groups");
}
