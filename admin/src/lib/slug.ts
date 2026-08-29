import { createClient } from "@/lib/supabase/server";
import { TABLE_FOR_ENTITY_TYPE, NAME_COLUMN_FOR_ENTITY_TYPE, type ClaimableEntityType } from "@/lib/entity-tables";

// Slugify hier dupliziert statt aus den Deno-Functions importiert — die
// Admin-App (Next.js) und die Edge Functions (Deno) teilen keinen
// Modul-Raum, dieselbe kleine Funktion existiert auch in
// backend/supabase/functions/ingest-source/write.ts und
// enrich-event-references/index.ts.
export function slugify(title: string): string {
  const umlauts: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss", Ä: "ae", Ö: "oe", Ü: "ue" };
  let s = title;
  for (const [from, to] of Object.entries(umlauts)) s = s.split(from).join(to);
  s = s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "");
  return s || "eintrag";
}

/** Kollisionssicherer Slug — hängt bei Bedarf "-2", "-3", ... an, statt
 * blind den rohen slugify()-Wert einzufügen. Bugfix (Nutzerfeedback:
 * "duplicate key value violates unique constraint persons_slug_key"):
 * approveEntityCandidate prüfte bisher gar nicht, ob der generierte Slug
 * schon existiert, bevor eingefügt wurde — ein zweiter Kandidat mit
 * gleichem/ähnlichem Namen (oder einer, dessen Name bereits als echte
 * Stammdaten-Zeile existiert, z.B. durch einen parallel laufenden
 * Anreicherungs-Schritt) ließ den rohen INSERT mit einer für die
 * Redaktion unverständlichen Postgres-Fehlermeldung scheitern. */
export async function generateUniqueSlug(
  supabase: Awaited<ReturnType<typeof createClient>>,
  table: (typeof TABLE_FOR_ENTITY_TYPE)[ClaimableEntityType],
  name: string,
): Promise<string> {
  const base = slugify(name);
  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from(table).select("id").eq("slug", candidate).maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

/** Prüft VOR jeder Neuanlage, ob schon eine Stammdaten-Zeile mit exakt
 * diesem Namen existiert — z.B. weil ein anderer Anreicherungsschritt
 * (Werk-Programm-Erkennung, ein anderer bereits genehmigter Kandidat mit
 * gleichem Namen) sie zwischenzeitlich angelegt hat. Statt dann blind
 * einen zweiten, duplizierten Eintrag zu versuchen (und an der
 * Slug-Eindeutigkeit zu scheitern), wird der Kandidat wie ein manuelles
 * "Zusammenführen" mit der bestehenden Zeile verknüpft. */
export async function findExistingByName(
  supabase: Awaited<ReturnType<typeof createClient>>,
  entityType: ClaimableEntityType,
  name: string,
): Promise<string | null> {
  const { data } = await supabase
    .from(TABLE_FOR_ENTITY_TYPE[entityType])
    .select("id")
    .ilike(NAME_COLUMN_FOR_ENTITY_TYPE[entityType], name)
    .maybeSingle();
  return data?.id ?? null;
}
