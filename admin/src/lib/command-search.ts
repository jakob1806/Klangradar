"use server";

import { createClient } from "@/lib/supabase/server";

// ⌘K-Suche im Admin-Portal (Nutzerwunsch 30.10.2026): Datensätze direkt
// anspringen. Je Typ wenige Treffer, Namensanfang zuerst.
export type CommandHit = { href: string; label: string; detail: string };

export async function searchCommandEntities(query: string): Promise<CommandHit[]> {
  const q = query.trim();
  if (q.length < 2) return [];
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];
  const pattern = `%${q.replace(/[%_,()]/g, " ")}%`;
  const [persons, ensembles, venues, works, events] = await Promise.all([
    supabase.from("persons").select("id, full_name").ilike("full_name", pattern).limit(5),
    supabase.from("ensembles").select("id, name").ilike("name", pattern).limit(5),
    supabase.from("venues").select("id, name").ilike("name", pattern).limit(4),
    supabase.from("works").select("id, title").ilike("title", pattern).limit(4),
    supabase
      .from("events")
      .select("id, title, start_datetime")
      .ilike("title", pattern)
      .gte("start_datetime", new Date().toISOString())
      .order("start_datetime")
      .limit(5),
  ]);
  const date = new Intl.DateTimeFormat("de-DE", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "Europe/Berlin" });
  return [
    ...(events.data ?? []).map((e) => ({ href: `/events/${e.id}`, label: e.title as string, detail: `Termin · ${date.format(new Date(e.start_datetime as string))}` })),
    ...(persons.data ?? []).map((p) => ({ href: `/persons/${p.id}`, label: p.full_name as string, detail: "Person" })),
    ...(ensembles.data ?? []).map((e) => ({ href: `/ensembles/${e.id}`, label: e.name as string, detail: "Ensemble" })),
    ...(venues.data ?? []).map((v) => ({ href: `/venues/${v.id}`, label: v.name as string, detail: "Venue" })),
    ...(works.data ?? []).map((w) => ({ href: `/works/${w.id}`, label: w.title as string, detail: "Werk" })),
  ];
}
