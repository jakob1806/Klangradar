import { createClient } from "@/lib/supabase/server";

type Supa = Awaited<ReturnType<typeof createClient>>;

/** Löscht eine Event-Gruppe (programs-Zeile), wenn sie keine Termine mehr
 * hat. Aufzurufen nach JEDER Operation, die einem Event sein program_id
 * wegnehmen oder das Event selbst löschen kann (Aushängen, Event löschen,
 * Duplikate-Merge) — sonst bleiben leere Gruppen wie "Finding Neverland · 0
 * Termine" stehen, weil programs keine ON DELETE CASCADE auf events.program_id
 * hat und nichts sonst die Mitgliederzahl gegenprüft. groupId ist optional,
 * damit Aufrufer den zuvor gelesenen event.program_id (kann null sein) ohne
 * eigene Prüfung direkt durchreichen können. */
export async function cleanupEventGroupIfEmpty(supabase: Supa, groupId: string | null): Promise<void> {
  if (!groupId) return;
  const { count, error: countError } = await supabase
    .from("events")
    .select("id", { count: "exact", head: true })
    .eq("program_id", groupId);
  if (countError || (count ?? 0) > 0) return;
  await supabase.from("programs").delete().eq("id", groupId);
}
