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

export interface SuggestedMerge {
  key: string;
  title: string;
  venueName: string | null;
  targetGroupId: string;
  targetTitle: string;
  sourceGroupIds: string[];
  groups: { id: string; title: string; eventCount: number }[];
}

/** Nutzeranfrage: "automatische vorschläge zum zusammenführen beim gleichen
 * standort und gleichem programm" — anders als suggestEventGroups() geht es
 * hier NICHT um noch ungruppierte Events, sondern um bereits als eigene
 * Gruppen angelegte Serien, die eigentlich dieselbe Produktion sind (z.B.
 * "zwei gruppen zauberflöte, bei denen aber zwischen den beiden blöcken
 * mehr als 14 tage dazwischen liegen, weshalb sie nicht zusammengehen" —
 * genau die 14-Tage-Grenze aus suggestEventGroups() greift hier bewusst
 * nicht). Gruppiert stattdessen nach normalisiertem Titel (case-insensitiv,
 * Anführungszeichen/Whitespace ignoriert — Quellen liefern denselben Titel
 * gerne mal in Groß- oder Kleinschreibung) UND demselben Hauptspielort:
 * mehrere bestehende Gruppen mit gleichem Titel UND mindestens einem
 * gemeinsamen Veranstaltungsort gelten als Vorschlag. Zielgruppe der
 * Zusammenführung ist die mit den meisten Terminen (bei Gleichstand die
 * älteste) — die anderen werden vorgeschlagen, dort hinein aufzugehen. */
export async function suggestGroupMerges(): Promise<SuggestedMerge[]> {
  const supabase = await createClient();
  const { data: groups } = await supabase
    .from("programs")
    .select("id, title, created_at, events(id, venues(name))")
    .order("created_at", { ascending: true })
    .returns<
      { id: string; title: string; created_at: string; events: { id: string; venues: { name: string } | null }[] }[]
    >();

  if (!groups || groups.length < 2) return [];

  const normalizeTitle = (title: string) =>
    title
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[«»„"'’]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();

  const withVenues = groups
    .filter((g) => g.events.length > 0)
    .map((g) => ({
      id: g.id,
      title: g.title,
      created_at: g.created_at,
      eventCount: g.events.length,
      normalizedTitle: normalizeTitle(g.title),
      venueNames: new Set(g.events.map((e) => e.venues?.name).filter((n): n is string => !!n)),
    }));

  const byTitle = new Map<string, typeof withVenues>();
  for (const g of withVenues) {
    if (!g.normalizedTitle) continue;
    const list = byTitle.get(g.normalizedTitle) ?? [];
    list.push(g);
    byTitle.set(g.normalizedTitle, list);
  }

  const suggestions: SuggestedMerge[] = [];
  for (const [normalizedTitle, sameTitle] of byTitle) {
    if (sameTitle.length < 2) continue;

    // Innerhalb desselben Titels zusätzlich nach gemeinsamem Spielort
    // clustern — ein generischer Titel wie "Der Nussknacker" kann an
    // mehreren, komplett unabhängigen Häusern laufen, das wäre keine
    // Zusammenführung, sondern eine andere Produktion.
    const remaining = [...sameTitle];
    while (remaining.length > 1) {
      const seed = remaining.shift()!;
      const cluster = [seed];
      for (let i = remaining.length - 1; i >= 0; i--) {
        const candidate = remaining[i];
        const sharesVenue = [...candidate.venueNames].some((v) => seed.venueNames.has(v));
        if (sharesVenue) {
          cluster.push(candidate);
          remaining.splice(i, 1);
        }
      }
      if (cluster.length < 2) continue;

      cluster.sort((a, b) => b.eventCount - a.eventCount || a.created_at.localeCompare(b.created_at));
      const [target, ...sources] = cluster;
      suggestions.push({
        key: `${normalizedTitle}__${target.id}`,
        title: target.title,
        venueName: [...target.venueNames][0] ?? null,
        targetGroupId: target.id,
        targetTitle: target.title,
        sourceGroupIds: sources.map((s) => s.id),
        groups: cluster.map((g) => ({ id: g.id, title: g.title, eventCount: g.eventCount })),
      });
    }
  }

  return suggestions;
}
