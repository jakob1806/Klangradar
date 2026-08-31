import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { resolveEntityNames, resolveTrustLevels, type ClaimableEntityType, type TrustLevel } from "@/lib/entity-tables";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "./event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Button } from "@/components/organizer/ui/button";
import { Table, TableBody, TableRow, TableCell } from "@/components/organizer/ui/table";

export const dynamic = "force-dynamic";

const ENTITY_TYPE_LABEL: Record<ClaimableEntityType, string> = {
  organizer: "Institution",
  venue: "Venue",
  person: "Person",
  ensemble: "Ensemble",
};

const STATUS_LABEL: Record<string, string> = {
  pending: "In Prüfung",
  approved: "Genehmigt",
  rejected: "Abgelehnt",
};

const TRUST_LABEL: Record<TrustLevel, string> = {
  unverified: "Unbestätigt",
  claimed: "Beansprucht",
  verified: "Verifiziert",
  official: "Offiziell",
};

interface EventRow {
  id: string;
  title: string;
  start_datetime: string;
  status: string;
  venues: { name: string } | null;
}

export default async function VeranstalterDashboardPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: claims } = await supabase
    .from("entity_claims")
    .select("id, entity_type, entity_id, status, justification, created_at")
    .eq("user_id", user!.id)
    .order("created_at", { ascending: false })
    .returns<
      { id: string; entity_type: ClaimableEntityType; entity_id: string; status: string; justification: string | null; created_at: string }[]
    >();

  const allClaims = claims ?? [];
  // Für Profile (Person, Ensemble, Venue) wird im Hintergrund ein technischer
  // Veranstalter-Kontext angelegt, damit Events weiterhin einen organizer_id
  // besitzen können. Dieser Kontext ist ausschließlich Besitz-/Rechte-Logik,
  // kein zweites beanspruchtes Profil und darf deshalb nie im Dashboard
  // auftauchen. Bestehende Kontexte haben absichtlich diesen festen Marker.
  const visibleClaims = allClaims.filter(
    (claim) => !(
      claim.entity_type === "organizer" &&
      claim.justification === "Automatisch aus genehmigtem Profil-Claim"
    ),
  );
  const refs = visibleClaims.map((c) => ({ entityType: c.entity_type, entityId: c.entity_id }));
  const [names, trustLevels] = await Promise.all([
    resolveEntityNames(supabase, refs),
    resolveTrustLevels(supabase, refs),
  ]);

  const pending = visibleClaims.filter((c) => c.status === "pending");
  const approved = visibleClaims.filter((c) => c.status === "approved");
  const rejected = visibleClaims.filter((c) => c.status === "rejected");

  const eventOrganizers = await getEventOrganizerOptions();
  const approvedOrganizerIds = eventOrganizers.map((organizer) => organizer.id);

  let upcomingEvents: EventRow[] = [];
  if (approvedOrganizerIds.length > 0) {
    const { data } = await supabase
      .from("events")
      .select("id, title, start_datetime, status, venues(name)")
      .in("organizer_id", approvedOrganizerIds)
      .order("start_datetime", { ascending: true })
      .limit(10)
      .returns<EventRow[]>();
    upcomingEvents = data ?? [];
  }

  if (visibleClaims.length === 0) {
    return (
      <div className="mx-auto flex max-w-xl flex-col items-center gap-4 px-6 py-28 text-center">
        <span className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#2D2A6E]">Willkommen</span>
        <h1 className="text-3xl font-semibold tracking-tight text-[#15131a]">Dein Veranstalterportal</h1>
        <p className="text-[15px] text-[#726c78]">
          Du verwaltest noch keine Institution, Venue, Person oder kein Ensemble. Beanspruche eine
          bestehende Einrichtung oder lege deine eigene Institution neu an, um loszulegen.
        </p>
        <Button asChild size="lg" className="mt-2">
          <Link href="/veranstalter/claim">Jetzt beanspruchen</Link>
        </Button>
      </div>
    );
  }

  return (
    <div>
      <PageHeader eyebrow="Übersicht" title="Dashboard" description="Deine Berechtigungen und anstehenden Konzerte auf einen Blick." />
      <PageBody className="flex flex-col gap-10">
        {pending.length > 0 && (
          <section className="flex flex-col gap-3">
            <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">In Prüfung ({pending.length})</h2>
            <ClaimList claims={pending} names={names} />
          </section>
        )}

        <section className="flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Genehmigt ({approved.length})</h2>
            <Link href="/veranstalter/claim" className="text-sm font-semibold text-[#2D2A6E] hover:underline">
              Weitere beanspruchen
            </Link>
          </div>
          {approved.length > 0 ? (
            <ClaimList claims={approved} names={names} trustLevels={trustLevels} showProfileLink />
          ) : (
            <Card>
              <CardContent className="pt-5 text-sm text-[#726c78]">Noch keine genehmigten Berechtigungen.</CardContent>
            </Card>
          )}
        </section>

        {rejected.length > 0 && (
          <section className="flex flex-col gap-3">
            <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Abgelehnt ({rejected.length})</h2>
            <ClaimList claims={rejected} names={names} />
          </section>
        )}

        {approvedOrganizerIds.length > 0 && (
          <section className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Anstehende Events</h2>
              <Link href="/veranstalter/events/new" className="flex items-center gap-1 text-sm font-semibold text-[#2D2A6E] hover:underline">
                Neues Event anlegen
              </Link>
            </div>
            {upcomingEvents.length > 0 ? (
              <Table>
                <TableBody>
                  {upcomingEvents.map((event) => (
                    <TableRow key={event.id}>
                      <TableCell className="font-medium">{event.title}</TableCell>
                      <TableCell className="text-[#4a4550]">{event.venues?.name ?? "—"}</TableCell>
                      <TableCell className="tabular-nums text-[#4a4550]">{formatMunichDateTime(event.start_datetime)}</TableCell>
                      <TableCell>
                        <Badge>{event.status === "draft" ? "Entwurf" : event.status}</Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <Link href={`/veranstalter/events/${event.id}`} className="font-semibold text-[#2D2A6E] hover:underline">
                          Bearbeiten
                        </Link>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            ) : (
              <Card>
                <CardContent className="pt-5 text-sm text-[#726c78]">Noch keine Events angelegt.</CardContent>
              </Card>
            )}
          </section>
        )}
      </PageBody>
    </div>
  );
}

function ClaimList({
  claims,
  names,
  trustLevels,
  showProfileLink,
}: {
  claims: { id: string; entity_type: ClaimableEntityType; entity_id: string; status: string }[];
  names: Map<string, string>;
  trustLevels?: Map<string, TrustLevel>;
  showProfileLink?: boolean;
}) {
  return (
    <Table>
      <TableBody>
        {claims.map((claim) => {
          const trust = trustLevels?.get(`${claim.entity_type}:${claim.entity_id}`);
          return (
            <TableRow key={claim.id}>
              <TableCell className="font-medium">
                <span className="inline-flex items-center gap-2">
                  {names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "(unbekannt)"}
                  {trust && (trust === "verified" || trust === "official") && (
                    <Badge variant="gold" title={TRUST_LABEL[trust]}>
                      {TRUST_LABEL[trust]}
                    </Badge>
                  )}
                </span>
              </TableCell>
              <TableCell className="text-[#726c78]">{ENTITY_TYPE_LABEL[claim.entity_type]}</TableCell>
              <TableCell className="text-[#726c78]">{STATUS_LABEL[claim.status] ?? claim.status}</TableCell>
              <TableCell className="text-right">
                {showProfileLink && (
                  <span className="inline-flex items-center gap-3">
                    <Link href={`/veranstalter/profile/${claim.entity_type}/${claim.entity_id}`} className="font-semibold text-[#2D2A6E] hover:underline">
                      Profil bearbeiten
                    </Link>
                    <Link href={`/veranstalter/team/${claim.entity_type}/${claim.entity_id}`} className="font-semibold text-[#2D2A6E] hover:underline">
                      Team
                    </Link>
                  </span>
                )}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}
