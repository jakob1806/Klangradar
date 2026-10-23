import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import { formatEventDate } from "@/lib/user-email";

// Erstellt von Claude Code. Konzertlink aus E-Mails (https://klangradar.com/e/<slug>):
// mit installierter App öffnet iOS direkt die App (Universal Link), sonst
// zeigt diese Seite das Konzert mit Ticket-Link.
type EventRow = {
  slug: string;
  title: string;
  subtitle: string | null;
  start_datetime: string;
  image_urls: string[] | null;
  ticket_url: string | null;
  website_url: string | null;
  venues: { name: string; address_city: string | null } | null;
};

async function loadEvent(slug: string): Promise<EventRow | null> {
  const { data } = await createAdminClient()
    .from("events")
    .select("slug, title, subtitle, start_datetime, image_urls, ticket_url, website_url, venues(name, address_city)")
    .eq("slug", slug)
    .neq("status", "draft")
    .maybeSingle<EventRow>();
  return data ?? null;
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const event = await loadEvent((await params).slug);
  return event ? { title: `${event.title} – Klangradar`, description: event.venues?.name ?? undefined, robots: { index: false } } : {};
}

export default async function EventLinkPage({ params }: { params: Promise<{ slug: string }> }) {
  const event = await loadEvent((await params).slug);
  if (!event) notFound();
  const ticket = event.ticket_url ?? event.website_url;
  return (
    <div className="mx-auto max-w-md px-6 py-14">
      {event.image_urls?.[0] ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={event.image_urls[0]} alt="" className="aspect-[3/2] w-full rounded-3xl object-cover" />
      ) : null}
      <p className="mt-6 text-[13px] font-semibold uppercase tracking-wide text-[#146194]">{formatEventDate(event.start_datetime)}</p>
      <h1 className="type-heading mt-2 text-3xl text-[#1d1d1f]">{event.title}</h1>
      {event.subtitle ? <p className="mt-2 text-[15px] text-[#3a3a3c]">{event.subtitle}</p> : null}
      {event.venues ? <p className="mt-2 text-[15px] text-[#6e6e73]">{[event.venues.name, event.venues.address_city].filter(Boolean).join(", ")}</p> : null}
      <a href={`de.klangradar.native://event/${event.slug}`} className="mt-8 inline-flex h-12 w-full items-center justify-center rounded-full bg-[#146194] text-[15px] font-semibold text-white">
        In Klangradar öffnen
      </a>
      {ticket ? (
        <a href={ticket} className="mt-3 inline-flex h-12 w-full items-center justify-center rounded-full border border-black/10 bg-white text-[15px] font-semibold text-[#1d1d1f]">
          Tickets & Infos beim Veranstalter
        </a>
      ) : null}
    </div>
  );
}
