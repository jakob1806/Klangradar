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

  revalidatePath(`/event-groups/${groupId}`);
  revalidatePath("/event-groups");
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
