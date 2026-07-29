"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { repointFieldProvenance } from "@/lib/merge-provenance";
import { logSystemAction } from "@/lib/system-log";

type Supa = Awaited<ReturnType<typeof createClient>>;

/** Vor dem Löschen des verlierenden Events müssen alle Fremdschlüssel auf
 * das verbleibende Event umgebogen werden — das war bisher nie nötig, weil
 * "Zusammenführen" ausschließlich das frisch ingestierte, noch leere
 * Draft-Event löschte (event_b, garantiert ohne event_works/Favoriten/etc.).
 * Jetzt, wo die Redaktion auswählen kann, WELCHES der beiden Events
 * überlebt, kann auch das etablierte Event mit echten Verknüpfungen der
 * Verlierer sein. Tabellen mit einem natürlichen Schlüssel, der event_id
 * enthält, brauchen eine Existenzprüfung (sonst PK-Konflikt beim Umbiegen
 * auf ein Event, das dieselbe Zeile schon hat) — dann wird die Verlierer-
 * Zeile stattdessen gelöscht, analog zum event_works-Umbiegen beim
 * Werk-Merge (duplicates/works/actions.ts). */
async function repointEventReferences(supabase: Supa, deleteEventId: string, keepEventId: string) {
  const naturalKeyTables: { table: string; otherKeyColumns: string[] }[] = [
    { table: "event_genres", otherKeyColumns: ["genre_id"] },
    { table: "event_tags", otherKeyColumns: ["tag_id"] },
    { table: "event_ticket_links", otherKeyColumns: ["url"] },
    { table: "event_works", otherKeyColumns: ["work_id", "position"] },
    { table: "favorite_list_items", otherKeyColumns: ["list_id"] },
    { table: "favorites", otherKeyColumns: ["user_id"] },
  ];

  for (const { table, otherKeyColumns } of naturalKeyTables) {
    const { data: loserRows } = await supabase.from(table).select("*").eq("event_id", deleteEventId);
    for (const row of loserRows ?? []) {
      let existingQuery = supabase.from(table).select("event_id").eq("event_id", keepEventId);
      for (const col of otherKeyColumns) existingQuery = existingQuery.eq(col, row[col]);
      const { data: existing } = await existingQuery.maybeSingle();

      if (existing) {
        let delQuery = supabase.from(table).delete().eq("event_id", deleteEventId);
        for (const col of otherKeyColumns) delQuery = delQuery.eq(col, row[col]);
        await delQuery;
      } else {
        let updQuery = supabase.from(table).update({ event_id: keepEventId }).eq("event_id", deleteEventId);
        for (const col of otherKeyColumns) updQuery = updQuery.eq(col, row[col]);
        await updQuery;
      }
    }
  }

  // id-PK-Tabellen ohne Kollisionsrisiko — einfaches Umbiegen reicht.
  for (const table of ["event_participants", "event_views", "event_change_log", "cancellation_candidates"]) {
    await supabase.from(table).update({ event_id: keepEventId }).eq("event_id", deleteEventId);
  }

  await repointFieldProvenance(supabase, "event", keepEventId, deleteEventId);
}

// event_a_id ist im Ingestion-Worker (backend/supabase/functions/ingest-
// source/write.ts) immer das bereits existierende, event_b_id das neu
// angelegte Draft-Event — reine Anlage-Reihenfolge, sagt nichts darüber
// aus, welche der beiden Versionen inhaltlich vollständiger/richtiger ist.
// "Zusammenführen" behielt deshalb bisher blind immer event_a; die
// Redaktion kann jetzt auswählen, welche Version bestehen bleibt
// (Nutzeranfrage: "bei einer Zusammenführen-Funktion soll man generell
// auswählen können, welche Version genommen wird" — siehe dieselbe
// Änderung bei Werk-Duplikaten, duplicates/works/actions.ts).
export async function resolveDuplicateAsMerged(candidateId: string, keepEventId: string) {
  const supabase = await createClient();

  const { data: candidate, error: fetchError } = await supabase
    .from("duplicate_candidates")
    .select("event_a_id, event_b_id")
    .eq("id", candidateId)
    .maybeSingle();

  if (fetchError || !candidate) {
    throw new Error(fetchError?.message ?? "Duplikate-Kandidat nicht gefunden");
  }
  if (keepEventId !== candidate.event_a_id && keepEventId !== candidate.event_b_id) {
    throw new Error("Ausgewähltes Event gehört nicht zu diesem Kandidaten");
  }
  const deleteEventId = keepEventId === candidate.event_a_id ? candidate.event_b_id : candidate.event_a_id;

  await repointEventReferences(supabase, deleteEventId, keepEventId);

  const { error: updateError } = await supabase
    .from("duplicate_candidates")
    .update({ status: "merged", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (updateError) throw new Error(updateError.message);

  const { error: deleteError } = await supabase.from("events").delete().eq("id", deleteEventId);
  if (deleteError) throw new Error(deleteError.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "duplicate_candidate",
    entityId: candidateId,
    action: "merged",
    actor: user?.email ?? user?.id ?? "unknown",
    before: { deleted_event_id: deleteEventId, kept_event_id: keepEventId },
  });

  revalidatePath("/duplicates");
}

export async function resolveDuplicateAsDistinct(candidateId: string) {
  const supabase = await createClient();

  const { error } = await supabase
    .from("duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "duplicate_candidate",
    entityId: candidateId,
    action: "dismissed",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/duplicates");
}
