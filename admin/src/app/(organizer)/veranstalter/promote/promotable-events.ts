import { resolveEntityNames, type ClaimableEntityType } from "@/lib/entity-tables";
import { createClient } from "@/lib/supabase/server";
import { getEventOrganizerOptions } from "../event-organizer-context";

type ProfileClaim = { entity_type: "venue" | "person" | "ensemble"; entity_id: string };
type EventRow = { id: string; title: string; start_datetime: string; venue_id: string; image_urls: string[] | null; venues: { name: string } | null };
type ParticipantLink = { event_id: string; person_id: string | null; ensemble_id: string | null };

export type PromotableEvent = {
  id: string;
  title: string;
  startDatetime: string;
  venueName: string | null;
  imageUrl: string | null;
  sourceLabel: string;
};

/** Kommende veröffentlichte Events, die der Nutzer selbst angelegt hat ODER
 * über ein beanspruchtes Profil (Venue, Person, Ensemble) vertreten darf. */
export async function getPromotableEvents(): Promise<{ events: PromotableEvent[]; error: string | null }> {
  const supabase = await createClient();
  const now = new Date().toISOString();
  const [organizers, claimResult] = await Promise.all([
    getEventOrganizerOptions(),
    supabase.from("entity_claims").select("entity_type, entity_id").eq("status", "approved"),
  ]);
  const claims = (claimResult.data ?? []).filter(
    (claim): claim is ProfileClaim => ["venue", "person", "ensemble"].includes(claim.entity_type),
  );
  const venueIds = claims.filter((claim) => claim.entity_type === "venue").map((claim) => claim.entity_id);
  const personIds = claims.filter((claim) => claim.entity_type === "person").map((claim) => claim.entity_id);
  const ensembleIds = claims.filter((claim) => claim.entity_type === "ensemble").map((claim) => claim.entity_id);
  const eventFields = "id, title, start_datetime, venue_id, image_urls, venues(name)";
  const [own, venues, persons, ensembles] = await Promise.all([
    organizers.length ? supabase.from("events").select(eventFields).eq("status", "scheduled").gt("start_datetime", now).in("organizer_id", organizers.map((organizer) => organizer.id)).returns<EventRow[]>() : Promise.resolve({ data: [] as EventRow[], error: null }),
    venueIds.length ? supabase.from("events").select(eventFields).eq("status", "scheduled").gt("start_datetime", now).in("venue_id", venueIds).returns<EventRow[]>() : Promise.resolve({ data: [] as EventRow[], error: null }),
    personIds.length ? supabase.from("event_participants").select("event_id, person_id, ensemble_id").in("person_id", personIds).returns<ParticipantLink[]>() : Promise.resolve({ data: [] as ParticipantLink[], error: null }),
    ensembleIds.length ? supabase.from("event_participants").select("event_id, person_id, ensemble_id").in("ensemble_id", ensembleIds).returns<ParticipantLink[]>() : Promise.resolve({ data: [] as ParticipantLink[], error: null }),
  ]);
  const participantLinks = [...(persons.data ?? []), ...(ensembles.data ?? [])];
  const participantEventIds = [...new Set(participantLinks.map((link) => link.event_id))];
  const participantEvents = participantEventIds.length
    ? await supabase.from("events").select(eventFields).eq("status", "scheduled").gt("start_datetime", now).in("id", participantEventIds).returns<EventRow[]>()
    : { data: [] as EventRow[], error: null };
  const error = claimResult.error ?? own.error ?? venues.error ?? persons.error ?? ensembles.error ?? participantEvents.error;
  if (error) return { events: [], error: error.message };

  const names = await resolveEntityNames(supabase, claims.map((claim) => ({ entityType: claim.entity_type as ClaimableEntityType, entityId: claim.entity_id })));
  const claimedLabels = new Map<string, string[]>();
  for (const event of venues.data ?? []) {
    const claim = claims.find((item) => item.entity_type === "venue" && item.entity_id === event.venue_id);
    if (claim) claimedLabels.set(event.id, [`Venue: ${names.get(`venue:${claim.entity_id}`) ?? "Beanspruchte Venue"}`]);
  }
  for (const link of participantLinks) {
    const claim = link.person_id
      ? claims.find((item) => item.entity_type === "person" && item.entity_id === link.person_id)
      : claims.find((item) => item.entity_type === "ensemble" && item.entity_id === link.ensemble_id);
    if (!claim) continue;
    const type = claim.entity_type === "person" ? "Person" : "Ensemble";
    const label = `${type}: ${names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "Beanspruchtes Profil"}`;
    claimedLabels.set(link.event_id, [...new Set([...(claimedLabels.get(link.event_id) ?? []), label])]);
  }
  const merged = new Map<string, PromotableEvent>();
  for (const event of [...(venues.data ?? []), ...(participantEvents.data ?? [])]) {
    merged.set(event.id, { id: event.id, title: event.title, startDatetime: event.start_datetime, venueName: event.venues?.name ?? null, imageUrl: event.image_urls?.[0] ?? null, sourceLabel: (claimedLabels.get(event.id) ?? ["Beanspruchtes Profil"]).join(" · ") });
  }
  for (const event of own.data ?? []) {
    merged.set(event.id, { id: event.id, title: event.title, startDatetime: event.start_datetime, venueName: event.venues?.name ?? null, imageUrl: event.image_urls?.[0] ?? null, sourceLabel: "Eigenes Event" });
  }
  return { events: [...merged.values()].sort((a, b) => a.startDatetime.localeCompare(b.startDatetime)), error: null };
}
