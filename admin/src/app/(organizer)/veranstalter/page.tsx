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

const WORKSPACES = [
  { eyebrow: "Programm", title: "Events & Serien", copy: "Termine anlegen, Besetzungen pflegen und Veröffentlichungen steuern.", href: "/veranstalter/events", mark: "01" },
  { eyebrow: "Stammdaten", title: "Künstler & Venues", copy: "Profile, Bilder, Werke und Spielstätten zentral aktuell halten.", href: "/veranstalter/bibliothek", mark: "02" },
  { eyebrow: "Reichweite", title: "Marketing & Push", copy: "Social Assets vorbereiten und Sichtbarkeit in Klangradar planen.", href: "/veranstalter/marketing", mark: "03" },
  { eyebrow: "Auswertung", title: "Analytics & Finanzen", copy: "Interesse, Ticket-Klicks und Budgets deiner Produktionen überblicken.", href: "/veranstalter/analytics", mark: "04" },
] as const;

const PLANNED_MODULES = ["Produktionszeitplan", "Dokumente & Verträge", "Gästelisten & Akkreditierung", "Presseverteiler", "Aufgaben & Team", "Künstlerkontakte"];

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
      <div className="mx-auto grid max-w-6xl gap-10 px-6 py-16 lg:grid-cols-[1.08fr_.92fr] lg:items-center lg:py-24">
        <div>
          <p className="mb-5 text-xs font-semibold uppercase tracking-[0.16em] text-[#8b2635]">Klangradar Pro</p>
          <h1 className="max-w-3xl text-balance text-[clamp(2.8rem,7vw,5.7rem)] font-semibold leading-[0.93] tracking-[-0.065em] text-[#171714]">
            Dein Programm.<br />Direkt im Konzertleben.
          </h1>
          <p className="mt-7 max-w-xl text-pretty text-base leading-7 text-[#5f5b56]">
            Verwalte Veranstaltungen, Künstler und Spielstätten an einem Ort. Veröffentlichte Termine erscheinen anschließend direkt in Klangradar.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-4">
            <Link href="/veranstalter/claim" className="rounded-xl bg-[#8b2635] px-5 py-3 text-sm font-semibold text-white shadow-[0_10px_28px_rgba(139,38,53,0.2)] transition duration-200 hover:-translate-y-0.5 hover:bg-[#7d2230] active:translate-y-0 active:scale-[0.98] focus-visible:outline-2 focus-visible:outline-offset-3 focus-visible:outline-[#8b2635]">Organisation beanspruchen</Link>
            <span className="text-sm text-[#77736d]">Die Prüfung schützt offizielle Profile.</span>
          </div>
        </div>
        <aside className="relative overflow-hidden rounded-[2rem] bg-[#1e2421] p-7 text-[#f7f4ed] shadow-[0_30px_80px_rgba(38,32,24,0.2)] sm:p-9">
          <div className="absolute -right-20 -top-24 h-64 w-64 rounded-full bg-[#8b2635]/35 blur-3xl" />
          <p className="relative text-xs font-semibold uppercase tracking-[0.14em] text-[#c7c0b5]">Nach der Freigabe</p>
          <ol className="relative mt-8 space-y-7">
            {["Profil und Team einrichten", "Erstes Event veröffentlichen", "Reichweite und Ticket-Klicks verfolgen"].map((step, index) => <li key={step} className="grid grid-cols-[2.5rem_1fr] gap-4"><span className="font-mono text-sm text-[#d9bc7f]">0{index + 1}</span><span className="border-b border-white/10 pb-7 text-lg font-medium tracking-[-0.025em] last:border-0">{step}</span></li>)}
          </ol>
        </aside>
      </div>
    );
  }

  const draftCount = upcomingEvents.filter((event) => event.status === "draft").length;
  const publishedCount = upcomingEvents.length - draftCount;

  return (
    <div className="mx-auto max-w-7xl px-5 py-9 sm:px-7 lg:py-14">
      <section className="grid gap-8 border-b border-black/10 pb-10 lg:grid-cols-[1.25fr_.75fr] lg:items-end lg:pb-14">
        <div>
          <p className="mb-4 text-xs font-semibold uppercase tracking-[0.16em] text-[#8b2635]">Klangradar Pro · Übersicht</p>
          <h1 className="max-w-4xl text-balance text-[clamp(2.65rem,5.5vw,5rem)] font-semibold leading-[0.94] tracking-[-0.06em] text-[#171714]">Deine Spielzeit.<br />Ein klarer Überblick.</h1>
        </div>
        <div className="lg:justify-self-end">
          <p className="max-w-md text-pretty text-sm leading-6 text-[#5f5b56]">Plane dein Programm, pflege Inhalte und bringe Veranstaltungen ohne doppelten Datenaufwand direkt zu deinem Publikum.</p>
          <div className="mt-5 flex flex-wrap gap-3">
            <Link href="/veranstalter/events/new" className="rounded-xl bg-[#8b2635] px-4 py-2.5 text-sm font-semibold text-white shadow-[0_8px_20px_rgba(139,38,53,0.18)] transition hover:-translate-y-0.5 hover:bg-[#7d2230] active:translate-y-0 active:scale-[0.98]">Neues Event</Link>
            <Link href="/veranstalter/events" className="rounded-xl border border-black/10 bg-white/55 px-4 py-2.5 text-sm font-semibold text-[#292825] transition hover:bg-white active:scale-[0.98]">Programm öffnen</Link>
          </div>
        </div>
      </section>

      <section aria-label="Status" className="grid border-b border-black/10 sm:grid-cols-3">
        <Metric value={publishedCount} label="Anstehend" note="veröffentlicht oder geplant" />
        <Metric value={draftCount} label="Entwürfe" note="brauchen noch Aufmerksamkeit" tone={draftCount > 0 ? "warm" : undefined} />
        <Metric value={approved.length} label="Profile" note="für dein Team freigegeben" />
      </section>

      {pending.length > 0 && (
        <section className="mt-10 rounded-2xl bg-[#eee5d3] p-5 sm:p-6">
          <h2 className="text-sm font-semibold text-[#6f512d]">{pending.length} {pending.length === 1 ? "Zugriff wird" : "Zugriffe werden"} geprüft</h2>
          <p className="mt-1 text-sm text-[#735f47]">Nach der redaktionellen Prüfung kannst du die zugehörigen Profile und Events verwalten.</p>
          <div className="mt-4">
          <ClaimList claims={pending} names={names} />
          </div>
        </section>
      )}

      <section className="mt-12 grid gap-8 lg:grid-cols-[minmax(0,1.55fr)_minmax(17rem,.65fr)]">
        <div>
          <div className="flex items-end justify-between gap-4">
            <div><p className="text-xs font-semibold uppercase tracking-[0.14em] text-[#8b2635]">Nächste Termine</p><h2 className="mt-2 text-2xl font-semibold tracking-[-0.035em] text-[#1d1d1f]">Dein Programm</h2></div>
            <Link href="/veranstalter/events" className="text-sm font-semibold text-[#8b2635] hover:underline">Alle Events</Link>
          </div>
          {upcomingEvents.length > 0 ? (
            <div className="mt-5 divide-y divide-black/[0.08] border-y border-black/[0.1]">
              {upcomingEvents.slice(0, 6).map((event) => (
                <article key={event.id} className="grid gap-3 py-4 sm:grid-cols-[7.5rem_minmax(0,1fr)_auto] sm:items-center sm:gap-5">
                  <time className="font-mono text-xs tabular-nums text-[#77736d]">{formatMunichDateTime(event.start_datetime)}</time>
                  <div className="min-w-0"><Link href={`/veranstalter/events/${event.id}`} className="block truncate text-sm font-semibold text-[#1d1d1f] transition hover:text-[#8b2635]">{event.title}</Link><p className="mt-1 truncate text-xs text-[#77736d]">{event.venues?.name ?? "Ort noch offen"}</p></div>
                  <span className={`w-fit text-xs font-medium ${event.status === "draft" ? "text-[#9a5c22]" : "text-[#386b58]"}`}>{event.status === "draft" ? "Entwurf" : "Veröffentlicht"}</span>
                </article>
              ))}
            </div>
          ) : <div className="mt-5 rounded-2xl bg-white/55 p-7"><p className="font-medium text-[#1d1d1f]">Noch keine Termine</p><p className="mt-2 text-sm leading-6 text-[#77736d]">Lege dein erstes Event an. Nach der Veröffentlichung erscheint es direkt in Klangradar.</p><Link href="/veranstalter/events/new" className="mt-5 inline-flex text-sm font-semibold text-[#8b2635] hover:underline">Erstes Event anlegen →</Link></div>}
        </div>
        <aside className="rounded-2xl bg-[#1e2421] p-6 text-[#f7f4ed] shadow-[0_20px_50px_rgba(37,32,25,0.14)]">
          <p className="text-xs font-semibold uppercase tracking-[0.14em] text-[#b7b1a7]">Direkt starten</p>
          <div className="mt-5 divide-y divide-white/10">
            <QuickLink href="/veranstalter/serien" title="Serie anlegen" copy="Wiederkehrende Programme bündeln" />
            <QuickLink href="/veranstalter/promote" title="Push-Kampagne" copy="Ein Event gezielt hervorheben" />
            <QuickLink href="/veranstalter/marketing" title="Social Asset" copy="Format und Text vorbereiten" />
            <QuickLink href="/veranstalter/agentur" title="Team & Kontakte" copy="Rollen und Roster organisieren" />
          </div>
        </aside>
      </section>

      <section className="mt-16">
        <div className="max-w-2xl"><p className="text-xs font-semibold uppercase tracking-[0.14em] text-[#8b2635]">Arbeitsbereiche</p><h2 className="mt-2 text-3xl font-semibold tracking-[-0.045em] text-[#171714]">Alles rund um eine Produktion.</h2><p className="mt-3 text-sm leading-6 text-[#5f5b56]">Die wichtigsten Werkzeuge greifen auf dieselben Event-, Künstler- und Venue-Daten zu.</p></div>
        <div className="mt-8 grid gap-px overflow-hidden rounded-2xl bg-black/10 sm:grid-cols-2">
          {WORKSPACES.map((workspace) => <Link key={workspace.title} href={workspace.href} className="group min-h-56 bg-[#faf9f6] p-6 transition duration-200 hover:bg-white sm:p-7"><span className="font-mono text-xs text-[#a09a91]">{workspace.mark}</span><p className="mt-8 text-xs font-semibold uppercase tracking-[0.12em] text-[#8b2635]">{workspace.eyebrow}</p><h3 className="mt-2 text-xl font-semibold tracking-[-0.035em] text-[#1d1d1f]">{workspace.title}</h3><p className="mt-3 max-w-sm text-sm leading-6 text-[#6f6a63]">{workspace.copy}</p><span className="mt-7 inline-block text-sm font-semibold text-[#8b2635] transition-transform group-hover:translate-x-1">Öffnen →</span></Link>)}
        </div>
      </section>

      <section className="mt-16 grid gap-8 border-y border-black/10 py-10 lg:grid-cols-[.8fr_1.2fr] lg:items-start">
        <div><p className="text-xs font-semibold uppercase tracking-[0.14em] text-[#8b2635]">Nächste Ausbaustufe</p><h2 className="mt-3 max-w-md text-3xl font-semibold tracking-[-0.045em] text-[#171714]">Vom Eventeintrag zur Produktionszentrale.</h2><p className="mt-4 max-w-md text-sm leading-6 text-[#5f5b56]">Diese Module sind als nächste Bausteine von Klangradar Pro vorgesehen. Bestehende Funktionen bleiben davon unabhängig nutzbar.</p></div>
        <div className="grid gap-x-8 sm:grid-cols-2">{PLANNED_MODULES.map((module) => <div key={module} className="flex items-center justify-between gap-4 border-b border-black/[0.09] py-4"><span className="text-sm font-medium text-[#292825]">{module}</span><span className="shrink-0 text-[0.68rem] font-semibold uppercase tracking-[0.09em] text-[#9a948b]">In Planung</span></div>)}</div>
      </section>

      <section className="mt-12">
        <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[0.14em] text-[#8b2635]">Organisationen & Profile</p><h2 className="mt-2 text-2xl font-semibold tracking-[-0.035em]">Deine Zugriffe</h2></div><Link href="/veranstalter/claim" className="text-sm font-semibold text-[#8b2635] hover:underline">Weiteres Profil beanspruchen</Link></div>
        <div className="mt-5">{approved.length > 0 ? <ClaimList claims={approved} names={names} trustLevels={trustLevels} showProfileLink /> : <p className="text-sm text-[#77736d]">Noch keine genehmigten Berechtigungen.</p>}</div>
      </section>

      {rejected.length > 0 && <details className="mt-8 text-sm text-[#77736d]"><summary className="cursor-pointer font-medium">Abgelehnte Anfragen ({rejected.length})</summary><div className="mt-3"><ClaimList claims={rejected} names={names} /></div></details>}
    </div>
  );
}

function Metric({ value, label, note, tone }: { value: number; label: string; note: string; tone?: "warm" }) {
  return <div className="min-h-36 border-black/10 px-1 py-7 sm:border-r sm:px-6 sm:first:pl-0 sm:last:border-0"><p className={`font-mono text-[2.4rem] font-medium leading-none tabular-nums tracking-[-0.06em] ${tone === "warm" ? "text-[#9a5c22]" : "text-[#1d1d1f]"}`}>{String(value).padStart(2, "0")}</p><p className="mt-4 text-sm font-semibold text-[#292825]">{label}</p><p className="mt-1 text-xs text-[#77736d]">{note}</p></div>;
}

function QuickLink({ href, title, copy }: { href: string; title: string; copy: string }) {
  return <Link href={href} className="group flex items-center justify-between gap-4 py-4 first:pt-1"><span><span className="block text-sm font-semibold">{title}</span><span className="mt-1 block text-xs text-[#aaa59d]">{copy}</span></span><span className="text-[#d9bc7f] transition-transform group-hover:translate-x-1">→</span></Link>;
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
    <div className="overflow-x-auto rounded-2xl border border-black/[0.07] bg-white/60">
      <table className="min-w-[42rem] w-full text-sm">
        <tbody className="divide-y divide-black/[0.07]">
          {claims.map((claim) => {
            const trust = trustLevels?.get(`${claim.entity_type}:${claim.entity_id}`);
            return (
            <tr key={claim.id}>
              <td className="px-4 py-3.5 font-medium text-[#1d1d1f]">
                <span className="inline-flex items-center gap-2">
                  {names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "(unbekannt)"}
                  {trust && (trust === "verified" || trust === "official") && (
                    <span
                      className="rounded-md bg-[#8b2635]/[0.08] px-2 py-1 text-[0.65rem] font-semibold text-[#8b2635]"
                      title={TRUST_LABEL[trust]}
                    >
                      {TRUST_LABEL[trust]}
                    </span>
                  )}
                </span>
              </td>
              <td className="px-4 py-3.5 text-[#77736d]">{ENTITY_TYPE_LABEL[claim.entity_type]}</td>
              <td className="px-4 py-3.5 text-[#77736d]">{STATUS_LABEL[claim.status] ?? claim.status}</td>
              <td className="px-4 py-3.5 text-right">
                {showProfileLink && (
                  <span className="inline-flex items-center gap-3">
                    <Link
                      href={`/veranstalter/profile/${claim.entity_type}/${claim.entity_id}`}
                      className="font-semibold text-[#8b2635] hover:underline"
                    >
                      Profil bearbeiten
                    </Link>
                    <Link
                      href={`/veranstalter/team/${claim.entity_type}/${claim.entity_id}`}
                      className="font-semibold text-[#8b2635] hover:underline"
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
