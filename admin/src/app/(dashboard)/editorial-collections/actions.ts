"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

// cover_image_url wird bewusst NICHT hier gelesen/geschrieben — das Titelbild
// läuft jetzt über die Bilder-Pipeline (siehe cover-image-picker.tsx +
// research-entity-image/index.ts, das die Spalte direkt setzt). Würde
// dieses Formular die Spalte weiter mitschreiben, würde JEDES Speichern
// (auch nur Titel/Untertitel ändern) das per Recherche/Upload gesetzte
// Titelbild wieder auf null zurücksetzen, weil das Feld nicht mehr im
// Formular existiert.
function readCollectionFields(formData: FormData) {
  return {
    title: String(formData.get("title") ?? "").trim(),
    slug: String(formData.get("slug") ?? "").trim(),
    subtitle: String(formData.get("subtitle") ?? "").trim() || null,
    description_de: String(formData.get("description_de") ?? "").trim() || null,
    is_published: formData.get("is_published") === "on",
    sort_order: Number(formData.get("sort_order") ?? 0) || 0,
  };
}

async function actor(supabase: Awaited<ReturnType<typeof createClient>>) {
  const { data: { user } } = await supabase.auth.getUser();
  return user?.email ?? user?.id ?? "unknown";
}

export async function createCollection(formData: FormData) {
  const supabase = await createClient();
  const payload = readCollectionFields(formData);

  const { data, error } = await supabase
    .from("editorial_collections")
    .insert(payload)
    .select("id")
    .single();
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "editorial_collection",
    entityId: data.id,
    action: "created",
    actor: await actor(supabase),
    after: payload,
  });

  revalidatePath("/editorial-collections");
  redirect(`/editorial-collections/${data.id}`);
}

export async function updateCollection(collectionId: string, formData: FormData) {
  const supabase = await createClient();
  const payload = readCollectionFields(formData);

  const { error } = await supabase
    .from("editorial_collections")
    .update({ ...payload, updated_at: new Date().toISOString() })
    .eq("id", collectionId);
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "editorial_collection",
    entityId: collectionId,
    action: "updated",
    actor: await actor(supabase),
    after: payload,
  });

  revalidatePath("/editorial-collections");
  revalidatePath(`/editorial-collections/${collectionId}`);
}

export async function deleteCollection(collectionId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("editorial_collections").delete().eq("id", collectionId);
  if (error) throw new Error(error.message);

  revalidatePath("/editorial-collections");
  redirect("/editorial-collections");
}

/** Sucht Events nach Titel für den Hinzufügen-Picker — der Event-Katalog
 * ist zu groß für eine feste Checkbox-Liste wie bei event-groups
 * (membership-editor.tsx), daher Textsuche statt vorgeladener Liste. */
export async function searchEventsForCollection(query: string) {
  if (query.trim().length < 2) return [];
  const supabase = await createClient();
  const { data } = await supabase
    .from("events")
    .select("id, title, start_datetime, venues(name)")
    .ilike("title", `%${query.trim()}%`)
    .order("start_datetime", { ascending: true })
    .limit(15);
  return (data ?? []) as unknown as Array<{
    id: string;
    title: string;
    start_datetime: string;
    venues: { name: string } | null;
  }>;
}

export async function addEventToCollection(collectionId: string, eventId: string) {
  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("editorial_collection_events")
    .select("position")
    .eq("collection_id", collectionId)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();
  const nextPosition = (existing?.position ?? -1) + 1;

  const { error } = await supabase
    .from("editorial_collection_events")
    .upsert(
      { collection_id: collectionId, event_id: eventId, position: nextPosition },
      { onConflict: "collection_id,event_id", ignoreDuplicates: true },
    );
  if (error) throw new Error(error.message);
  // Manuell wieder hinzugefügt: ein früherer Ausschluss gilt nicht mehr.
  await supabase.from("editorial_collection_exclusions").delete().eq("collection_id", collectionId).eq("event_id", eventId);

  revalidatePath(`/editorial-collections/${collectionId}`);
}

export async function removeEventFromCollection(collectionId: string, eventId: string) {
  const supabase = await createClient();
  // Automatisch hinzugefügte Termine merken, damit die Regel sie nicht
  // beim nächsten Abgleich wieder einträgt.
  const { data: row } = await supabase
    .from("editorial_collection_events")
    .select("source")
    .eq("collection_id", collectionId)
    .eq("event_id", eventId)
    .maybeSingle();
  if (row?.source === "rule") {
    await supabase.from("editorial_collection_exclusions").upsert({ collection_id: collectionId, event_id: eventId }, { onConflict: "collection_id,event_id", ignoreDuplicates: true });
  }
  const { error } = await supabase
    .from("editorial_collection_events")
    .delete()
    .eq("collection_id", collectionId)
    .eq("event_id", eventId);
  if (error) throw new Error(error.message);

  revalidatePath(`/editorial-collections/${collectionId}`);
}

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Sammlungen automatisch
// befüllen — Regel "alle Konzerte mit Person/Ensemble/Spielstätte X".

export type RuleSearchResult = { entity_type: "person" | "ensemble" | "venue"; entity_id: string; label: string; detail: string | null; upcoming: number };

export async function searchCollectionRuleEntities(query: string): Promise<RuleSearchResult[]> {
  if (query.trim().length < 2) return [];
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_collection_rule_search", { p_query: query.trim() });
  // Fehler nicht mehr still verschlucken (sah aus wie "keine Treffer").
  if (error) throw new Error(`Suche fehlgeschlagen: ${error.message}`);
  return (data ?? []) as RuleSearchResult[];
}

export async function addCollectionRule(collectionId: string, entityType: string, entityId: string): Promise<{ added: number }> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("editorial_collection_rules")
    .upsert({ collection_id: collectionId, entity_type: entityType, entity_id: entityId }, { onConflict: "collection_id,entity_type,entity_id", ignoreDuplicates: true });
  if (error) throw new Error(error.message);
  const { data: added, error: syncError } = await supabase.rpc("sync_editorial_collection_rules", { p_collection_id: collectionId });
  if (syncError) throw new Error(syncError.message);
  revalidatePath(`/editorial-collections/${collectionId}`);
  return { added: Number(added ?? 0) };
}

export async function removeCollectionRule(collectionId: string, entityType: string, entityId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("editorial_collection_rules")
    .delete()
    .eq("collection_id", collectionId)
    .eq("entity_type", entityType)
    .eq("entity_id", entityId);
  if (error) throw new Error(error.message);
  const { error: syncError } = await supabase.rpc("sync_editorial_collection_rules", { p_collection_id: collectionId });
  if (syncError) throw new Error(syncError.message);
  revalidatePath(`/editorial-collections/${collectionId}`);
}
