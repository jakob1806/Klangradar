import { sameWork, workIdentity } from "../_shared/workIdentity.ts";

export interface WorkRow {
  id: string;
  title: string;
  composer_id: string | null;
  catalog_number: string | null;
  uses: number;
}

/** Paare (behalten, entfernen) je Komponist. Behalten wird das meistgenutzte,
 * bei Gleichstand das mit Werkverzeichnis bzw. kürzerem Titel. */
export function planMerges(works: WorkRow[]): { keep: string; drop: string; reason: string }[] {
  const byComposer = new Map<string, WorkRow[]>();
  for (const w of works) {
    if (!w.composer_id) continue; // ohne Komponist nie automatisch zusammenführen
    byComposer.set(w.composer_id, [...(byComposer.get(w.composer_id) ?? []), w]);
  }
  const merges: { keep: string; drop: string; reason: string }[] = [];
  for (const group of byComposer.values()) {
    const sorted = [...group].sort((a, b) =>
      b.uses - a.uses || Number(Boolean(b.catalog_number)) - Number(Boolean(a.catalog_number)) || a.title.length - b.title.length
    );
    const kept: { row: WorkRow; identity: ReturnType<typeof workIdentity> }[] = [];
    for (const row of sorted) {
      const identity = workIdentity(row.title, row.catalog_number);
      const match = kept.find((k) => sameWork(k.identity, identity));
      if (match) merges.push({ keep: match.row.id, drop: row.id, reason: `"${row.title}" → "${match.row.title}"` });
      else kept.push({ row, identity });
    }
  }
  return merges;
}
