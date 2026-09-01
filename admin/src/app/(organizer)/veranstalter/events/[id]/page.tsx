import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { OrganizerEventForm, type OrganizerEventFormValues } from "../../organizer-event-form";
import { updateOrganizerEvent } from "../actions";
import { EventImageUpload } from "../../event-image-upload";
import { getEventOrganizerOptions } from "../../event-organizer-context";

export const dynamic = "force-dynamic";

interface EventDetailRow {
  id: string;
  slug: string;
  title: string;
  subtitle: string | null;
  description_de: string | null;
  start_datetime: string;
  duration_minutes: number | null;
  has_intermission: boolean;
  venue_id: string;
  venue_detail: string | null;
  organizer_id: string | null;
  ticket_url: string | null;
  price_min: number | null;
  price_max: number | null;
  is_free: boolean;
  remaining_tickets_status: string | null;
  doors_info: string | null;
  age_restriction: string | null;
  discount_info: string | null;
  presale_fee_info: string | null;
  image_urls: string[] | null;
  venues: { name: string } | null;
  organizers: { name: string } | null;
}

export default async function EditOrganizerEventPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Kein manueller organizer_id-Filter nötig — RLS ("Veranstalter bearbeitet
  // eigene Events") liefert für ein fremdes Event schlicht keine Zeile.
  const { data: event } = await supabase
    .from("events")
    .select(
      "id, slug, title, subtitle, description_de, start_datetime, duration_minutes, has_intermission, venue_id, venue_detail, organizer_id, ticket_url, price_min, price_max, is_free, remaining_tickets_status, doors_info, age_restriction, discount_info, presale_fee_info, image_urls, venues(name), organizers(name)",
    )
    .eq("id", id)
    .maybeSingle()
    .returns<EventDetailRow | null>();

  if (!event) notFound();

  const [organizers, { data: genres }, { data: eventGenres }] = await Promise.all([
    getEventOrganizerOptions(),
    supabase.from("genres").select("id, label_de").order("sort_order"),
    supabase.from("event_genres").select("genre_id").eq("event_id", id),
  ]);
  const organizerLocked = Boolean(event.organizer_id && !organizers.some((organizer) => organizer.id === event.organizer_id));

  let previewImageUrl = event.image_urls?.[0] ?? null;
  if (!previewImageUrl) {
    const { data: galleryImage } = await supabase
      .from("images")
      .select("thumbnail_path, storage_path, source_url")
      .eq("origin_type", "event")
      .eq("origin_id", id)
      .in("license_status", ["confirmed_free", "confirmed_licensed"])
      .order("sort_order", { ascending: true })
      .limit(1)
      .maybeSingle();
    const path = galleryImage?.thumbnail_path ?? galleryImage?.storage_path;
    previewImageUrl = path ? supabase.storage.from("ingested-images").getPublicUrl(path).data.publicUrl : galleryImage?.source_url ?? null;
  }

  const initial: OrganizerEventFormValues = {
    slug: event.slug,
    title: event.title,
    subtitle: event.subtitle,
    description_de: event.description_de,
    start_datetime: event.start_datetime,
    duration_minutes: event.duration_minutes,
    has_intermission: event.has_intermission,
    venue_id: event.venue_id,
    venue_name: event.venues?.name ?? "",
    venue_detail: event.venue_detail,
    organizer_id: event.organizer_id ?? "",
    ticket_url: event.ticket_url,
    price_min: event.price_min,
    price_max: event.price_max,
    is_free: event.is_free,
    remaining_tickets_status: event.remaining_tickets_status,
    doors_info: event.doors_info,
    age_restriction: event.age_restriction,
    discount_info: event.discount_info,
    presale_fee_info: event.presale_fee_info,
    genreIds: (eventGenres ?? []).map((g) => g.genre_id as string),
  };

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <h1 className="type-heading mb-6 text-2xl text-[#1d1d1f]">Event bearbeiten</h1>
      <OrganizerEventForm
        action={updateOrganizerEvent.bind(null, event.id)}
        initial={initial}
        organizers={organizers}
        genres={genres ?? []}
        initialImageUrl={previewImageUrl}
        organizerLocked={organizerLocked}
        organizerLockedName={event.organizers?.name}
      />
      <div className="mt-8 max-w-2xl"><EventImageUpload eventId={event.id} userId={user!.id} /></div>
    </div>
  );
}
