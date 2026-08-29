import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { resolveEntityNames, resolveTrustLevels, type ClaimableEntityType, type TrustLevel } from "@/lib/entity-tables";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "./event-organizer-context";

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
  const refs = allClaims.map((c) => ({ entityType: c.entity_type, entityId: c.entity_id }));
  const [names, trustLevels] = await Promise.all([
    resolveEntityNames(supabase, refs),
    resolveTrustLevels(supabase, refs),
  ]);

  const pending = allClaims.filter((c) => c.status === "pending");
  const approved = allClaims.filter((c) => c.status === "approved");
  const rejected = allClaims.filter((c) => c.status === "rejected");

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

  if (allClaims.length === 0) {
    return (
      <div className="mx-auto flex max-w-xl flex-col items-center gap-4 px-6 py-24 text-center">
        <h1 className="type-heading text-2xl text-[#1d1d1f]">Willkommen im Veranstalter-Portal</h1>
        <p className="text-[#48484a]">
          Du verwaltest noch keine Institution, Venue, Person oder kein Ensemble. Beanspruche eine
          bestehende Einrichtung oder lege deine eigene Institution neu an, um loszulegen.
        </p>
        <Link
          href="/veranstalter/claim"
          className="rounded-full bg-[#0071e3] px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-[#0077ed]"
        >
          Jetzt beanspruchen
        </Link>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <h1 className="type-heading mb-6 text-2xl text-[#1d1d1f]">Dashboard</h1>

      {pending.length > 0 && (
        <section className="mb-8">
          <h2 className="mb-3 text-sm font-semibold text-[#86868b]">In Prüfung ({pending.length})</h2>
          <ClaimList claims={pending} names={names} />
        </section>
      )}

      <section className="mb-8">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-[#86868b]">Genehmigt ({approved.length})</h2>
          <Link href="/veranstalter/claim" className="text-sm font-medium text-[#0071e3] hover:underline">
            Weitere beanspruchen
          </Link>
        </div>
        {approved.length > 0 ? (
          <ClaimList claims={approved} names={names} trustLevels={trustLevels} showProfileLink />
        ) : (
          <p className="text-sm text-[#86868b]">Noch keine genehmigten Berechtigungen.</p>
        )}
      </section>

      {rejected.length > 0 && (
        <section className="mb-8">
          <h2 className="mb-3 text-sm font-semibold text-[#86868b]">Abgelehnt ({rejected.length})</h2>
          <ClaimList claims={rejected} names={names} />
        </section>
      )}

      {approvedOrganizerIds.length > 0 && (
        <section>
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-[#86868b]">Anstehende Events</h2>
            <Link href="/veranstalter/events/new" className="text-sm font-medium text-[#0071e3] hover:underline">
              Neues Event anlegen
            </Link>
          </div>
          {upcomingEvents.length > 0 ? (
            <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white">
              <table className="w-full text-sm">
                <tbody className="divide-y divide-neutral-200">
                  {upcomingEvents.map((event) => (
                    <tr key={event.id}>
                      <td className="px-4 py-3 font-medium text-[#1d1d1f]">{event.title}</td>
                      <td className="px-4 py-3 text-[#48484a]">{event.venues?.name ?? "—"}</td>
                      <td className="px-4 py-3 tabular-nums text-[#48484a]">
                        {formatMunichDateTime(event.start_datetime)}
                      </td>
                      <td className="px-4 py-3 text-[#86868b]">{event.status === "draft" ? "Entwurf" : event.status}</td>
                      <td className="px-4 py-3 text-right">
                        <Link href={`/veranstalter/events/${event.id}`} className="font-medium text-[#0071e3] hover:underline">
                          Bearbeiten
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-sm text-[#86868b]">Noch keine Events angelegt.</p>
          )}
        </section>
      )}
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
    <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white">
      <table className="w-full text-sm">
        <tbody className="divide-y divide-neutral-200">
          {claims.map((claim) => {
            const trust = trustLevels?.get(`${claim.entity_type}:${claim.entity_id}`);
            return (
            <tr key={claim.id}>
              <td className="px-4 py-3 font-medium text-[#1d1d1f]">
                <span className="inline-flex items-center gap-2">
                  {names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "(unbekannt)"}
                  {trust && (trust === "verified" || trust === "official") && (
                    <span
                      className="type-label rounded-full border border-black/10 bg-black/[0.03] px-2 py-0.5 !text-[#0071e3]"
                      title={TRUST_LABEL[trust]}
                    >
                      {TRUST_LABEL[trust]}
                    </span>
                  )}
                </span>
              </td>
              <td className="px-4 py-3 text-[#86868b]">{ENTITY_TYPE_LABEL[claim.entity_type]}</td>
              <td className="px-4 py-3 text-[#86868b]">{STATUS_LABEL[claim.status] ?? claim.status}</td>
              <td className="px-4 py-3 text-right">
                {showProfileLink && (
                  <span className="inline-flex items-center gap-3">
                    <Link
                      href={`/veranstalter/profile/${claim.entity_type}/${claim.entity_id}`}
                      className="font-medium text-[#0071e3] hover:underline"
                    >
                      Profil bearbeiten
                    </Link>
                    <Link
                      href={`/veranstalter/team/${claim.entity_type}/${claim.entity_id}`}
                      className="font-medium text-[#0071e3] hover:underline"
                    >
                      Team
                    </Link>
                  </span>
                )}
              </td>
            </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
