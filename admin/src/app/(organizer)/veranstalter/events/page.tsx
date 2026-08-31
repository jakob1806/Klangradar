import Link from "next/link";
import Image from "next/image";
import { createClient } from "@/lib/supabase/server";
import { resolveEntityNames, type ClaimableEntityType } from "@/lib/entity-tables";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Button } from "@/components/organizer/ui/button";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/organizer/ui/table";

export const dynamic = "force-dynamic";

const STATUS_LABEL: Record<string, string> = {
  scheduled: "Geplant",
  sold_out: "Ausverkauft",
  cancelled: "Abgesagt",
  postponed: "Verschoben",
  draft: "Entwurf",
};

interface EventRow {
  id: string;
  title: string;
  start_datetime: string;
  status: string;
  venue_id: string;
  venues: { name: string } | null;
  image_urls: string[] | null;
}

type ProfileClaim = { entity_type: "venue" | "person" | "ensemble"; entity_id: string };
type ParticipantLink = { event_id: string; person_id: string | null; ensemble_id: string | null };

type ListedEvent = EventRow & { source: "own" | "claimed"; sourceLabel?: string };

// Lädt eigene Events implizit über RLS ("Veranstalter sieht eigene Events",
// entity_claims-Migration) — kein manueller organizer_id-Filter nötig, ein
// unauthorisierter Nutzer sähe hier ohnehin nur öffentlich sichtbare Zeilen
// (die RLS-Policies werden pro Command-Typ ODER-verknüpft).
export default async function VeranstalterEventsPage() {
  const supabase = await createClient();
  const organizers = await getEventOrganizerOptions();
  const organizerIds = organizers.map((organizer) => organizer.id);
  const now = new Date().toISOString();
  const { data: claimData } = await supabase
    .from("entity_claims")
    .select("entity_type, entity_id")
    .eq("status", "approved");
  const profileClaims = (claimData ?? []).filter(
    (claim): claim is ProfileClaim => ["venue", "person", "ensemble"].includes(claim.entity_type),
  );
  const venueIds = profileClaims.filter((claim) => claim.entity_type === "venue").map((claim) => claim.entity_id);
  const personIds = profileClaims.filter((claim) => claim.entity_type === "person").map((claim) => claim.entity_id);
  const ensembleIds = profileClaims.filter((claim) => claim.entity_type === "ensemble").map((claim) => claim.entity_id);

  const [ownResult, venueResult, personParticipantsResult, ensembleParticipantsResult] = await Promise.all([
    organizerIds.length
      ? supabase.from("events").select("id, title, start_datetime, status, venue_id, venues(name), image_urls").in("organizer_id", organizerIds).gte("start_datetime", now).returns<EventRow[]>()
      : Promise.resolve({ data: [] as EventRow[], error: null }),
    venueIds.length
      ? supabase.from("events").select("id, title, start_datetime, status, venue_id, venues(name), image_urls").in("venue_id", venueIds).gte("start_datetime", now).returns<EventRow[]>()
      : Promise.resolve({ data: [] as EventRow[], error: null }),
    personIds.length
      ? supabase.from("event_participants").select("event_id, person_id, ensemble_id").in("person_id", personIds).returns<ParticipantLink[]>()
      : Promise.resolve({ data: [] as ParticipantLink[], error: null }),
    ensembleIds.length
      ? supabase.from("event_participants").select("event_id, person_id, ensemble_id").in("ensemble_id", ensembleIds).returns<ParticipantLink[]>()
      : Promise.resolve({ data: [] as ParticipantLink[], error: null }),
  ]);

  const participantLinks = [...(personParticipantsResult.data ?? []), ...(ensembleParticipantsResult.data ?? [])];
  const participantEventIds = [...new Set(participantLinks.map((link) => link.event_id))];
  const participantEventsResult = participantEventIds.length
    ? await supabase.from("events").select("id, title, start_datetime, status, venue_id, venues(name), image_urls").in("id", participantEventIds).gte("start_datetime", now).returns<EventRow[]>()
    : { data: [] as EventRow[], error: null };

  const names = await resolveEntityNames(
    supabase,
    profileClaims.map((claim) => ({ entityType: claim.entity_type as ClaimableEntityType, entityId: claim.entity_id })),
  );
  const claimedSourceByEvent = new Map<string, string[]>();
  for (const event of venueResult.data ?? []) {
    const venueClaim = profileClaims.find((claim) => claim.entity_type === "venue" && claim.entity_id === event.venue_id);
    if (venueClaim) claimedSourceByEvent.set(event.id, [`Venue: ${names.get(`venue:${venueClaim.entity_id}`) ?? "Beanspruchte Venue"}`]);
  }
  for (const link of participantLinks) {
    const claim = link.person_id
      ? profileClaims.find((item) => item.entity_type === "person" && item.entity_id === link.person_id)
      : profileClaims.find((item) => item.entity_type === "ensemble" && item.entity_id === link.ensemble_id);
    if (!claim) continue;
    const label = `${claim.entity_type === "person" ? "Person" : "Ensemble"}: ${names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "Beanspruchtes Profil"}`;
    claimedSourceByEvent.set(link.event_id, [...new Set([...(claimedSourceByEvent.get(link.event_id) ?? []), label])]);
  }

  const listedEvents = new Map<string, ListedEvent>();
  for (const event of [...(venueResult.data ?? []), ...(participantEventsResult.data ?? [])]) {
    listedEvents.set(event.id, { ...event, source: "claimed", sourceLabel: (claimedSourceByEvent.get(event.id) ?? ["Beanspruchtes Profil"]).join(" · ") });
  }
  for (const event of ownResult.data ?? []) {
    // Ein selbst angelegtes Event hat Vorrang, auch wenn es zugleich bei
    // einem beanspruchten Profil mitwirkt oder dort stattfindet.
    listedEvents.set(event.id, { ...event, source: "own" });
  }
  const events = [...listedEvents.values()].sort((a, b) => a.start_datetime.localeCompare(b.start_datetime));
  const error = ownResult.error ?? venueResult.error ?? personParticipantsResult.error ?? ensembleParticipantsResult.error ?? participantEventsResult.error;

  return (
    <div>
      <PageHeader
        eyebrow="Events"
        title="Meine Events"
        description="Kommende eigene Events und Termine deiner beanspruchten Profile, chronologisch ab heute."
        actions={
          organizerIds.length > 0 && (
            <Button asChild>
              <Link href="/veranstalter/events/new">Neu anlegen</Link>
            </Button>
          )
        }
      />
      <PageBody className="flex flex-col gap-6">
        {error && (
          <p className="rounded-xl border border-[#a9700f]/20 bg-[#a9700f]/10 px-4 py-3 text-sm text-[#8a5a0c]">
            Deine Events konnten gerade nicht geladen werden. Bitte lade die Seite erneut; die Events selbst sind nicht verloren.
          </p>
        )}
        {events.length === 0 ? (
          <Card>
            <CardContent className="pt-5 text-sm text-[#726c78]">
              {organizerIds.length === 0 && profileClaims.length === 0 ? (
                <>Noch keine Events. Beanspruche zuerst ein Profil unter <Link href="/veranstalter/claim" className="font-semibold text-[#2D2A6E] hover:underline">Beanspruchen</Link>.</>
              ) : (
                "Noch keine kommenden Events. Lege dein erstes Event an."
              )}
            </CardContent>
          </Card>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Bild</TableHead>
                <TableHead>Titel</TableHead>
                <TableHead>Ort</TableHead>
                <TableHead>Termin</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Zuordnung</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {events.map((event) => (
                <TableRow key={event.id}>
                  <TableCell><div className="relative h-12 w-16 overflow-hidden rounded-md bg-[#15131a]/[0.04]">{event.image_urls?.[0] && <Image src={event.image_urls[0]} alt="" fill className="object-cover" sizes="64px" unoptimized />}</div></TableCell>
                  <TableCell className="font-medium">{event.title}</TableCell>
                  <TableCell className="text-[#4a4550]">{event.venues?.name ?? "—"}</TableCell>
                  <TableCell className="tabular-nums text-[#4a4550]">{formatMunichDateTime(event.start_datetime)}</TableCell>
                  <TableCell>
                    <Badge>{STATUS_LABEL[event.status] ?? event.status}</Badge>
                  </TableCell>
                  <TableCell className="text-xs text-[#726c78]">
                    {event.source === "own" ? "Eigenes Event" : event.sourceLabel}
                  </TableCell>
                  <TableCell className="text-right">
                    {event.source === "own" ? (
                      <Link href={`/veranstalter/events/${event.id}`} className="font-semibold text-[#2D2A6E] hover:underline">Bearbeiten</Link>
                    ) : (
                      <Link href={`/veranstalter/events/discover/${event.id}`} className="font-semibold text-[#2D2A6E] hover:underline">Ansehen</Link>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </PageBody>
    </div>
  );
}
