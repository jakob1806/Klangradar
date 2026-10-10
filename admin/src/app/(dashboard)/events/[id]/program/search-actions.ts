"use server";

import { createClient } from "@/lib/supabase/server";

export type EntityKind = "person" | "ensemble" | "work";
export type EntityHit = { id: string; label: string; hint?: string };

// Serverseitige Suche statt "alles in ein <select> laden": PostgREST kappt
// Antworten bei 1000 Zeilen (db.max_rows), alphabetisch hintere Komponisten,
// Personen und Werke fehlten deshalb in den Dropdowns.
export async function searchEntities(kind: EntityKind, query: string): Promise<EntityHit[]> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  // ilike-Wildcards und PostgREST-Trennzeichen aus der Eingabe entfernen.
  const q = query.trim().replace(/[%_,()\\]/g, " ").replace(/\s+/g, " ").slice(0, 80);
  const pattern = q ? `%${q.split(" ").join("%")}%` : null;

  if (kind === "person") {
    let request = supabase.from("persons").select("id, full_name").order("full_name").limit(25);
    if (pattern) request = request.ilike("full_name", pattern);
    const { data } = await request;
    return (data ?? []).map((row) => ({ id: row.id as string, label: row.full_name as string }));
  }
  if (kind === "ensemble") {
    let request = supabase
      .from("ensembles")
      .select("id, name")
      .eq("is_resolution_placeholder", false)
      .eq("is_family_root", false)
      .order("name")
      .limit(25);
    if (pattern) request = request.ilike("name", pattern);
    const { data } = await request;
    return (data ?? []).map((row) => ({ id: row.id as string, label: row.name as string }));
  }
  let request = supabase
    .from("works")
    .select("id, title, catalog_number, composer:persons(full_name)")
    .order("title")
    .limit(25);
  if (pattern) request = request.ilike("title", pattern);
  const { data } = await request.returns<{ id: string; title: string; catalog_number: string | null; composer: { full_name: string } | null }[]>();
  return (data ?? []).map((row) => ({
    id: row.id,
    label: row.title,
    hint: [row.composer?.full_name, row.catalog_number].filter(Boolean).join(" · ") || undefined,
  }));
}
