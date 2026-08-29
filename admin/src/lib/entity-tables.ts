import type { SupabaseClient } from "@supabase/supabase-js";

// Gemeinsame Zuordnung entity_type -> Stammdaten-Tabelle/Namensspalte,
// genutzt sowohl von entity-candidates (Ingestion-Review, kennt keine
// Venues) als auch von entity-claims (Veranstalter-Claiming, kennt alle
// vier Typen) — eine Quelle statt zweier abweichender Kopien.
export type ClaimableEntityType = "person" | "ensemble" | "organizer" | "venue";

export const TABLE_FOR_ENTITY_TYPE = {
  person: "persons",
  ensemble: "ensembles",
  organizer: "organizers",
  venue: "venues",
} as const satisfies Record<ClaimableEntityType, string>;

export const NAME_COLUMN_FOR_ENTITY_TYPE = {
  person: "full_name",
  ensemble: "name",
  organizer: "name",
  venue: "name",
} as const satisfies Record<ClaimableEntityType, string>;

// Für Phase 2 (Profil-Bearbeitung geclaimter Entitäten): bewusst eine kleine,
// konservative Auswahl unkritischer Beschreibungsfelder statt aller
// Spalten — strukturelle/verifizierende Felder (slug, is_verified, Adresse/
// Standort einer Venue, Rollen/Geburtsdatum einer Person, etc.) bleiben
// exklusiv Redaktionssache, auch nach Genehmigung eines Vorschlags. Die
// Spaltennamen unterscheiden sich je Typ (z.B. persons.biography_de statt
// description_de) — deshalb Record<Feldname, Label> statt eines einzigen
// gemeinsamen Feldnamens.
export const EDITABLE_FIELDS_FOR_ENTITY_TYPE = {
  organizer: {
    description_de: "Beschreibung",
    logo_url: "Logo-URL",
    website_url: "Website",
    contact_email: "Kontakt-E-Mail",
  },
  venue: {
    description_de: "Beschreibung",
    photo_url: "Foto-URL",
    website_url: "Website",
  },
  person: {
    biography_de: "Biografie",
    photo_url: "Foto-URL",
    website_url: "Website",
  },
  ensemble: {
    description_de: "Beschreibung",
    photo_url: "Foto-URL",
    website_url: "Website",
  },
} as const satisfies Record<ClaimableEntityType, Record<string, string>>;

/** Löst Anzeigenamen für eine Liste polymorpher entity_type/entity_id-Paare
 * auf (entity_claims hat KEINEN FK je Typ, deshalb ist ein eingebetteter
 * Join wie bei entity_candidates hier nicht möglich). Gruppiert nach Typ und
 * fragt pro vorkommendem Typ einmal gebündelt ab, statt pro Zeile einzeln —
 * genutzt sowohl vom Veranstalter-Dashboard als auch von der
 * Admin-Prüfseite /entity-claims. Rückgabe-Key: "entityType:entityId". */
export async function resolveEntityNames(
  supabase: SupabaseClient,
  refs: { entityType: ClaimableEntityType; entityId: string }[],
): Promise<Map<string, string>> {
  const names = new Map<string, string>();
  const idsByType = new Map<ClaimableEntityType, Set<string>>();
  for (const ref of refs) {
    if (!idsByType.has(ref.entityType)) idsByType.set(ref.entityType, new Set());
    idsByType.get(ref.entityType)!.add(ref.entityId);
  }

  await Promise.all(
    Array.from(idsByType.entries()).map(async ([entityType, ids]) => {
      const nameColumn = NAME_COLUMN_FOR_ENTITY_TYPE[entityType];
      const { data } = await supabase
        .from(TABLE_FOR_ENTITY_TYPE[entityType])
        .select(`id, ${nameColumn}`)
        .in("id", Array.from(ids));
      for (const row of (data ?? []) as Record<string, unknown>[]) {
        names.set(`${entityType}:${row.id as string}`, (row[nameColumn] as string) ?? "(ohne Namen)");
      }
    }),
  );

  return names;
}
