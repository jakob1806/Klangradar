import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DeleteButton } from "@/components/delete-button";
import { deleteCollection, updateCollection } from "../actions";
import { CollectionForm, type CollectionFormValues } from "../collection-form";
import { EventPicker, type CollectionEvent } from "./event-picker";

export const dynamic = "force-dynamic";

export default async function EditCollectionPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data, error }, { data: eventRows }] = await Promise.all([
    supabase
      .from("editorial_collections")
      .select("title, slug, subtitle, description_de, cover_image_url, is_published, sort_order")
      .eq("id", id)
      .maybeSingle<CollectionFormValues>(),
    supabase
      .from("editorial_collection_events")
      .select("position, events(id, title, start_datetime, venues(name))")
      .eq("collection_id", id)
      .order("position", { ascending: true }),
  ]);

  if (error || !data) notFound();

  const events: CollectionEvent[] = (eventRows ?? [])
    .map((r) => {
      const e = r.events as unknown as
        | { id: string; title: string; start_datetime: string; venues: { name: string } | null }
        | null;
      if (!e) return null;
      return {
        id: e.id,
        title: e.title,
        start_datetime: e.start_datetime,
        venueName: e.venues?.name ?? null,
      };
    })
    .filter((e): e is CollectionEvent => e !== null);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{data.title} bearbeiten</h1>
        <DeleteButton action={deleteCollection.bind(null, id)} confirmMessage={`"${data.title}" wirklich löschen?`} />
      </div>
      <div className="mt-6">
        <CollectionForm action={updateCollection.bind(null, id)} initial={data} />
      </div>
      <div className="mt-10 border-t border-neutral-200 pt-8">
        <EventPicker collectionId={id} initialEvents={events} />
      </div>
    </div>
  );
}
