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

  revalidatePath(`/editorial-collections/${collectionId}`);
}

export async function removeEventFromCollection(collectionId: string, eventId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("editorial_collection_events")
    .delete()
    .eq("collection_id", collectionId)
    .eq("event_id", eventId);
  if (error) throw new Error(error.message);

  revalidatePath(`/editorial-collections/${collectionId}`);
}
