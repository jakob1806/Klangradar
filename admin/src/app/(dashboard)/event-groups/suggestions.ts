import { createClient } from "@/lib/supabase/server";

export interface SuggestedGroup {
  key: string;
  title: string;
  events: { id: string; title: string; start_datetime: string; venueName: string | null }[];
}

const MAX_GAP_DAYS = 14;

/** Vorschläge für Aufführungsserien: noch nicht gruppierte, geplante Events
 * mit exakt identischem Titel (das trifft in der Praxis die allermeisten
 * Fälle — Quellen liefern für wiederholte Vorstellungen i.d.R. denselben
 * Titel), zusätzlich in zeitlich nahe beieinanderliegende Cluster
 * aufgeteilt (Lückenzweiten-Regel, max. 14 Tage zwischen zwei Terminen
 * derselben Serie) — sonst würde z.B. ein wiederkehrender generischer
 * Konzerttitel wie "Münchner Philharmoniker: Beethoven" über die gesamte
 * Saison hinweg fälschlich als eine einzige Serie vorgeschlagen. */
export async function suggestEventGroups(): Promise<SuggestedGroup[]> {
  const supabase = await createClient();
  const { data: events } = await supabase
    .from("events")
    .select("id, title, start_datetime, venues(name)")
    .eq("status", "scheduled")
    .is("program_id", null)
    .order("start_datetime", { ascending: true })
    .returns<{ id: string; title: string; start_datetime: string; venues: { name: string } | null }[]>();

  if (!events || events.length === 0) return [];

  const byTitle = new Map<string, typeof events>();
  for (const e of events) {
    const list = byTitle.get(e.title) ?? [];
    list.push(e);
    byTitle.set(e.title, list);
  }

  const suggestions: SuggestedGroup[] = [];
  for (const [title, group] of byTitle) {
    if (group.length < 2) continue;

    let cluster: typeof group = [group[0]];
    const flush = (clusterIndex: number) => {
      if (cluster.length < 2) return;
      suggestions.push({
        key: `${title}__${clusterIndex}`,
        title,
        events: cluster.map((e) => ({
          id: e.id,
          title: e.title,
          start_datetime: e.start_datetime,
          venueName: e.venues?.name ?? null,
        })),
      });
    };

    let clusterIndex = 0;
    for (let i = 1; i < group.length; i++) {
      const prev = new Date(cluster[cluster.length - 1].start_datetime).getTime();
      const cur = new Date(group[i].start_datetime).getTime();
      const gapDays = (cur - prev) / (1000 * 60 * 60 * 24);
      if (gapDays > MAX_GAP_DAYS) {
        flush(clusterIndex);
        clusterIndex += 1;
        cluster = [group[i]];
      } else {
        cluster.push(group[i]);
      }
    }
    flush(clusterIndex);
  }

  return suggestions;
}
