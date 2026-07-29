import type { SupabaseClient } from "@supabase/supabase-js";

/** Zieht field_provenance-Zeilen von deleteEntityId auf keepEntityId um.
 * Bug (Nutzermeldung): "ab und zu tritt ein fehler bei der zusammenführung
 * oder auswahl bei 'werk duplikate review'" — ein blindes
 * `update({entity_id: keepId}).eq("entity_id", deleteId)` verletzt den
 * Unique-Index (entity_type, entity_id, field_name), sobald keepEntityId
 * für dasselbe Feld bereits eine eigene Provenienz-Zeile hat. Analog zum
 * bestehenden Positions-Umbiegen bei event_works (siehe
 * duplicates/works/actions.ts moveWork-Kommentar): bei Kollision gewinnt
 * die bereits vorhandene Zeile von keepEntityId, die verwaiste Zeile von
 * deleteEntityId wird gelöscht statt verschoben. */
export async function repointFieldProvenance(
  supabase: SupabaseClient,
  entityType: string,
  keepEntityId: string,
  deleteEntityId: string,
) {
  const { data: rows } = await supabase
    .from("field_provenance")
    .select("id, field_name")
    .eq("entity_type", entityType)
    .eq("entity_id", deleteEntityId);

  for (const row of rows ?? []) {
    const { data: existing } = await supabase
      .from("field_provenance")
      .select("id")
      .eq("entity_type", entityType)
      .eq("entity_id", keepEntityId)
      .eq("field_name", row.field_name)
      .maybeSingle();

    if (existing) {
      await supabase.from("field_provenance").delete().eq("id", row.id);
    } else {
      await supabase.from("field_provenance").update({ entity_id: keepEntityId }).eq("id", row.id);
    }
  }
}
