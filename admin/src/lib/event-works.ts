import { createClient } from "@/lib/supabase/server";

/** Lädt für die übergebenen Event-IDs das jeweilige Programm aus
 * event_works (position-sortiert) und formatiert es als "Werk (Komponist)"
 * — event_works bleibt auch nach dem Anlegen einer Event-Gruppe die
 * kanonische Quelle pro Termin (siehe event-groups/[id]/actions.ts:
 * "Broadcast"-Bearbeitung wirkt auf event_works, keine eigene
 * programs/program_items-Struktur). Geteilt zwischen den
 * Gruppierungs-Vorschlägen (suggestions.ts) und der Liste bestehender
 * Gruppen (page.tsx) — Nutzerwunsch: "dann auch bei jeder veranstaltung
 * das programm", nicht nur bei noch ungruppierten Vorschlägen. */
export async function loadWorksByEventId(
  supabase: Awaited<ReturnType<typeof createClient>>,
  eventIds: string[],
): Promise<Map<string, string[]>> {
  if (eventIds.length === 0) return new Map();
  const { data } = await supabase
    .from("event_works")
    .select("event_id, position, works(title, composer:persons(full_name))")
    .in("event_id", eventIds)
    .order("position", { ascending: true })
    .returns<
      { event_id: string; position: number; works: { title: string; composer: { full_name: string } | null } | null }[]
    >();

  const byEvent = new Map<string, string[]>();
  for (const row of data ?? []) {
    if (!row.works) continue;
    const label = row.works.composer?.full_name ? `${row.works.title} (${row.works.composer.full_name})` : row.works.title;
    const list = byEvent.get(row.event_id) ?? [];
    list.push(label);
    byEvent.set(row.event_id, list);
  }
  return byEvent;
}
