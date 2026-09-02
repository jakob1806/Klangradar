import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DeleteButton } from "@/components/delete-button";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import { AiEnrichButton } from "@/components/ai-enrich-button";
import { EntityAuditButton } from "@/components/entity-audit-button";
import { EditorialAiAssistant } from "@/components/editorial-ai-assistant";
import type { GalleryImage } from "@/lib/gallery-actions";
import { deleteEvent, updateEvent } from "../actions";
import { EventForm, type EventFormValues } from "../event-form";
import { loadEventFormOptions } from "../form-options";
import { TicketProviderManager, type TicketLinkRow } from "./ticket-provider-manager";

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
  status: string;
  program_id: string | null;
  event_genres: { genre_id: string }[];
}

interface ProgramPreviewRow {
  position: number;
  after_intermission: boolean;
  works: { title: string; composer: { full_name: string } | null } | null;
}

export default async function EditEventPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: event, error }, { venues, organizers, genres }, { data: images }, { data: ticketLinks }] = await Promise.all([
    supabase
      .from("events")
      .select(
        "id, slug, title, subtitle, description_de, start_datetime, duration_minutes, has_intermission, venue_id, venue_detail, organizer_id, ticket_url, price_min, price_max, is_free, remaining_tickets_status, doors_info, age_restriction, discount_info, presale_fee_info, status, program_id, event_genres(genre_id)",
      )
      .eq("id", id)
      .maybeSingle<EventDetailRow>(),
    loadEventFormOptions(),
    // Nur freigegebene Bilder — siehe Kommentar in persons/[id]/page.tsx.
    supabase
      .from("images")
      .select("id, source_url, sort_order, crop_x, crop_y, crop_width, crop_height, review_status, quality_status, confidence_score, source_name, license_status, last_checked_at, warnings")
      .eq("origin_type", "event")
      .eq("origin_id", id)
      .in("license_status", ["confirmed_free", "confirmed_licensed"])
      .order("sort_order", { ascending: true })
      .returns<GalleryImage[]>(),
    supabase.from("event_ticket_links")
      .select("url,price_min,price_max,currency,is_primary,is_broken,last_checked_at,availability_status,discount_categories,discount_notes,price_updated_at,ticket_providers(name)")
      .eq("event_id", id).order("price_min", { ascending: true, nullsFirst: false }).returns<TicketLinkRow[]>(),
  ]);

  if (error || !event) notFound();

  const initial: EventFormValues = {
    ...event,
    genreIds: event.event_genres.map((g) => g.genre_id),
  };

  // Nutzeranfrage: "falls man ein einzelnes Event anklickt, das in einer
  // Gruppe ist, soll irgendwo ein Hinweis sein, dass dieses Event bereits
  // in der Gruppe 'xy' ist, mit Button direkt dorthin zu wechseln" — plus
  // eine kompakte Programm-Vorschau direkt auf dieser Seite, weil das
  // Programm bisher nur über den separaten "Programm & Mitwirkende"-Link
  // sichtbar war und dadurch leicht übersehen wurde.
  const [{ data: group }, { data: programPreview }] = await Promise.all([
    event.program_id
      ? supabase.from("programs").select("id, title").eq("id", event.program_id).maybeSingle()
      : Promise.resolve({ data: null }),
    supabase
      .from("event_works")
      .select("position, after_intermission, works(title, composer:persons(full_name))")
      .eq("event_id", id)
      .order("position", { ascending: true })
      .returns<ProgramPreviewRow[]>(),
  ]);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{event.title} bearbeiten</h1>
        <div className="flex items-center gap-4">
          <Link
            href={`/events/${id}/program`}
            className="text-sm font-medium text-neutral-700 hover:text-neutral-900"
          >
            Programm & Mitwirkende →
          </Link>
          <DeleteButton
            action={deleteEvent.bind(null, id)}
            confirmMessage={`"${event.title}" wirklich löschen?`}
          />
        </div>
      </div>
      <div className="mt-4 flex flex-wrap items-start gap-3">
        <AiEnrichButton entityType="event" entityId={id} />
        <EntityAuditButton entityType="event" entityId={id} />
      </div>
      <div className="mt-4"><EditorialAiAssistant entityType="event" entityId={id} /></div>
      {group && (
        <div className="mt-4 flex items-center justify-between rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm">
          <span className="text-amber-800">
            Dieses Event ist Teil der Gruppe „{group.title}“ — Programm/Mitwirkende werden dort für alle Termine
            gemeinsam gepflegt.
          </span>
          <Link
            href={`/event-groups/${group.id}`}
            className="shrink-0 rounded-md bg-amber-700 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-800"
          >
            Gruppe bearbeiten →
          </Link>
        </div>
      )}

      <div className="mt-6">
        <EventForm
          action={updateEvent.bind(null, id)}
          initial={initial}
          venues={venues}
          organizers={organizers}
          genres={genres}
        />
      </div>

      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <TicketProviderManager eventId={id} links={ticketLinks ?? []} />
      </div>

      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">
            Programm {programPreview && programPreview.length > 0 && `(${programPreview.length})`}
          </h2>
          <Link href={`/events/${id}/program`} className="text-sm font-medium text-neutral-700 hover:text-neutral-900">
            Bearbeiten →
          </Link>
        </div>
        {programPreview && programPreview.length > 0 ? (
          <ol className="mt-3 flex flex-col gap-1.5">
            {programPreview.map((row, i) => (
              <li key={i} className="text-sm text-neutral-700">
                {row.after_intermission && (
                  <span className="mr-2 rounded bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium uppercase text-amber-700">
                    nach Pause
                  </span>
                )}
                <span className="font-medium text-neutral-900">{row.works?.title}</span>
                {row.works?.composer && <span className="text-neutral-500"> — {row.works.composer.full_name}</span>}
              </li>
            ))}
          </ol>
        ) : (
          <p className="mt-3 text-sm text-neutral-400">Noch kein Programm erfasst.</p>
        )}
      </div>

      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <GalleryEditor originType="event" originId={id} path={`/events/${id}`} images={images ?? []} />
      </div>
    </div>
  );
}
