"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { repointFieldProvenance } from "@/lib/merge-provenance";
import { logSystemAction } from "@/lib/system-log";
import { cleanupEventGroupIfEmpty } from "@/lib/event-group-cleanup";

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

function normalizeWorkTitle(title: string): string {
  return title
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Nutzeranfrage: "falls ein event zusammengeführt wird, soll der
 * komponist automatisch für alle zusammengeführten events übernommen
 * werden." Der Komponist lebt auf works.composer_id, nicht auf event_works
 * selbst — repointEventReferences() oben behandelt event_works rein
 * strukturell über den natürlichen Schlüssel (work_id, position). Wenn
 * beide zusammengeführten Events dasselbe Werk als ZWEI unterschiedliche
 * works-Zeilen referenzieren (typischer Fall bei automatisch importierten
 * Duplikaten: eine Zeile mit Komponist von der direkten Venue-Quelle, eine
 * ohne von einer Aggregator-Quelle wie Concerti/IN München), landen nach
 * dem Zusammenführen BEIDE Werk-Zeilen im Programm des verbleibenden
 * Events — eine davon weiterhin ohne Komponist. Dieser Schritt läuft
 * danach: gruppiert die event_works-Zeilen des verbleibenden Events nach
 * normalisiertem Werktitel und behält bei Namensgleichheit nur die Zeile,
 * deren Werk einen Komponisten hat (falls vorhanden) — die
 * komponistenlose(n) Dublette(n) werden aus dem Programm entfernt (nur die
 * event_works-Verknüpfung, nicht die works-Zeile selbst, die könnte an
 * anderen Events noch hängen). */
async function carryOverComposerOnMerge(supabase: Supa, keepEventId: string) {
  const { data: rows } = await supabase
    .from("event_works")
    .select("work_id, position, works(title, composer_id)")
    .eq("event_id", keepEventId);
  if (!rows || rows.length < 2) return;

  type Row = { work_id: string; position: number; works: { title: string; composer_id: string | null }[] };
  const groups = new Map<string, Row[]>();
  for (const row of rows as unknown as Row[]) {
    const title = row.works?.[0]?.title;
    if (!title) continue;
    const key = normalizeWorkTitle(title);
    const list = groups.get(key) ?? [];
    list.push(row);
    groups.set(key, list);
  }

  for (const group of groups.values()) {
    if (group.length < 2) continue;
    const withComposer = group.find((r) => r.works?.[0]?.composer_id);
    if (!withComposer) continue; // keine Version hat einen Komponisten — nichts zu bevorzugen

    for (const row of group) {
      if (row.work_id === withComposer.work_id) continue;
      await supabase.from("event_works").delete().eq("event_id", keepEventId).eq("work_id", row.work_id);
    }
  }
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
  const { data: loserEvent } = await supabase.from("events").select("program_id").eq("id", deleteEventId).maybeSingle();

  await repointEventReferences(supabase, deleteEventId, keepEventId);
  await carryOverComposerOnMerge(supabase, keepEventId);

  const { error: updateError } = await supabase
    .from("duplicate_candidates")
    .update({ status: "merged", reviewed_at: new Date().toISOString() })
    .eq("id", candidateId);
  if (updateError) throw new Error(updateError.message);

  const { error: deleteError } = await supabase.from("events").delete().eq("id", deleteEventId);
  if (deleteError) throw new Error(deleteError.message);

  // War das gelöschte Event das letzte Mitglied seiner Event-Gruppe, bliebe
  // die Gruppe sonst leer stehen (Nutzer-Meldung "0 Termine"), siehe
  // event-group-cleanup.ts. Nur relevant, wenn keepEventId in einer anderen
  // Gruppe war/keiner — sonst hat die Gruppe durch keepEventId weiterhin
  // Mitglieder.
  await cleanupEventGroupIfEmpty(supabase, loserEvent?.program_id ?? null);

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

/** Mehrfachauswahl-Variante für die konsolidierte Duplikate-Seite —
 * Zusammenführen bleibt bewusst Einzelfall-Aktion (braucht pro Paar eine
 * Entscheidung, welche Version bleibt), aber "als unterschiedlich
 * markieren" ist für mehrere ausgewählte Paare auf einmal sicher. */
export async function resolveDuplicatesAsDistinct(candidateIds: string[]): Promise<{ completed: number }> {
  const uniqueIds = [...new Set(candidateIds)].slice(0, 200);
  if (uniqueIds.length === 0) return { completed: 0 };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("duplicate_candidates")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .in("id", uniqueIds)
    .eq("status", "pending")
    .select("id");
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  for (const row of data ?? []) {
    await logSystemAction(supabase, {
      entityType: "duplicate_candidate",
      entityId: row.id,
      action: "dismissed",
      actor: user?.email ?? user?.id ?? "unknown",
    });
  }

  revalidatePath("/duplicates");
  return { completed: data?.length ?? 0 };
}
