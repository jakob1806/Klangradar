import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { NAV_GROUPS } from "@/components/nav-groups";
import { RecentlyOpened } from "@/components/recently-opened";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Startseite des
// Admin-Portals unter klangradar.com/admin. Bisher gab es dort keine Seite —
// /admin landete nach dem Login im Leeren, die Redaktion startete auf
// /events. Oben die Lage (kommende Termine, Offenes), darunter alle Bereiche
// der Navigation als Kacheln.

const GROUP_HINTS: Record<string, string> = {
  Heute: "Was jetzt ansteht",
  Programm: "Termine, Festivals, Sammlungen",
  Wissen: "Personen, Ensembles, Werke, Orte",
  Datenqualität: "Prüfen, Duplikate, Vertrauen",
  System: "Quellen, Benutzer, Einstellungen",
};

// "Zuletzt erledigt": eigene Aktionen aus system_logs (Zusammenführungen,
// Sammlungen, Freigaben …) — Erweiterung Claude Code, 29.10.2026.
interface LogRow { id: string; entity_type: string; entity_id: string | null; action: string; created_at: string }

const LOG_TARGET: Record<string, { label: string; href: (id: string) => string }> = {
  person: { label: "Person", href: (id) => `/persons/${id}` },
  persons: { label: "Person", href: (id) => `/persons/${id}` },
  ensemble: { label: "Ensemble", href: (id) => `/ensembles/${id}` },
  ensembles: { label: "Ensemble", href: (id) => `/ensembles/${id}` },
  venue: { label: "Venue", href: (id) => `/venues/${id}` },
  event: { label: "Termin", href: (id) => `/events/${id}` },
  work: { label: "Werk", href: (id) => `/works/${id}` },
  editorial_collection: { label: "Sammlung", href: (id) => `/editorial-collections/${id}` },
  person_duplicate_candidate: { label: "Personen-Duplikat", href: () => "/duplicates?type=person" },
  ensemble_duplicate_candidate: { label: "Ensemble-Duplikat", href: () => "/duplicates?type=ensemble" },
  venue_duplicate_candidate: { label: "Venue-Duplikat", href: () => "/duplicates?type=venue" },
  work_duplicate_candidate: { label: "Werk-Duplikat", href: () => "/duplicates?type=work" },
};

const ACTION_LABEL: Record<string, string> = {
  created: "angelegt",
  updated: "bearbeitet",
  deleted: "gelöscht",
  merged: "zusammengeführt",
  dismissed: "als verschieden markiert",
  approved: "freigegeben",
  rejected: "abgelehnt",
};

const logTime = new Intl.DateTimeFormat("de-DE", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Europe/Berlin" });

function greeting(hour: number) {
  if (hour < 11) return "Guten Morgen";
  if (hour < 18) return "Guten Tag";
  return "Guten Abend";
}

export default async function AdminHomePage() {
  const supabase = await createClient();
  const now = new Date();
  const nowIso = now.toISOString();
  const weekIso = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const berlinHour = Number(new Intl.DateTimeFormat("de-DE", { hour: "numeric", hour12: false, timeZone: "Europe/Berlin" }).format(now));

  const count = { count: "exact" as const, head: true };
  const [
    { data: { user } },
    { count: upcoming },
    { count: nextWeek },
    { count: reviewQueue },
    { count: cancellations },
    { count: contentReports },
    { count: claims },
    { count: entityRequests },
    { count: duplicates },
  ] = await Promise.all([
    supabase.auth.getUser(),
    supabase.from("events").select("id", count).gte("start_datetime", nowIso).in("status", ["scheduled", "sold_out"]),
    supabase.from("events").select("id", count).gte("start_datetime", nowIso).lt("start_datetime", weekIso).in("status", ["scheduled", "sold_out"]),
    supabase.from("events").select("id", count).in("review_status", ["needs_review", "needs_quick_check"]),
    supabase.from("cancellation_candidates").select("id", count).eq("status", "pending"),
    supabase.from("content_reports").select("id", count).eq("status", "pending"),
    supabase.from("entity_claims").select("id", count).eq("status", "pending"),
    supabase.from("entity_requests").select("id", count).eq("status", "pending"),
    supabase.from("duplicate_candidates").select("id", count).eq("status", "pending"),
  ]);

  const tasks = [
    { href: "/review-queue", label: "Review-Queue", count: reviewQueue ?? 0 },
    { href: "/cancellations", label: "Absage-Review", count: cancellations ?? 0 },
    { href: "/content-reports", label: "Meldungen & Fehler", count: contentReports ?? 0 },
    { href: "/entity-claims", label: "Veranstalter-Claims", count: claims ?? 0 },
    { href: "/entity-requests", label: "Nutzeranfragen", count: entityRequests ?? 0 },
    { href: "/duplicates", label: "Duplikate", count: duplicates ?? 0 },
  ];
  const open = tasks.reduce((sum, task) => sum + task.count, 0);
  const actor = user?.email ?? user?.id ?? null;
  const { data: logData } = actor
    ? await supabase
        .from("system_logs")
        .select("id, entity_type, entity_id, action, created_at")
        .eq("actor", actor)
        .order("created_at", { ascending: false })
        .limit(8)
    : { data: [] };
  const logs = (logData ?? []) as LogRow[];
  const name = user?.email?.split("@")[0];

  return (
    <div className="p-8">
      <p className="text-[13px] font-medium text-neutral-500">Klangradar Admin</p>
      <h1 className="mt-1 text-2xl font-semibold tracking-tight text-neutral-900">
        {greeting(berlinHour)}
        {name ? `, ${name}` : ""}
      </h1>
      <p className="mt-1 max-w-2xl text-sm text-neutral-500">
        {open > 0 ? `${open.toLocaleString("de-DE")} offene Punkte warten auf Prüfung.` : "Gerade ist nichts offen."}
      </p>

      <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-neutral-500">Kommende Termine</p>
          <p className="mt-1 text-2xl font-semibold tabular-nums text-neutral-900">{(upcoming ?? 0).toLocaleString("de-DE")}</p>
          <p className="mt-0.5 text-xs text-neutral-500">{(nextWeek ?? 0).toLocaleString("de-DE")} in den nächsten 7 Tagen</p>
        </div>
        <Link href="/wichtig" className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm transition-colors hover:border-[#2D2A6E]/40">
          <p className="text-xs font-medium uppercase tracking-wide text-neutral-500">Offen</p>
          <p className="mt-1 text-2xl font-semibold tabular-nums text-neutral-900">{open.toLocaleString("de-DE")}</p>
          <p className="mt-0.5 text-xs text-[#2D2A6E]">Alle offenen Aufgaben →</p>
        </Link>
        <Link href="/events/new" className="flex flex-col justify-between rounded-xl bg-[#2D2A6E] p-4 text-white shadow-sm transition-colors hover:bg-[#38358a]">
          <p className="text-xs font-medium uppercase tracking-wide text-white/70">Schnellstart</p>
          <p className="mt-1 text-lg font-semibold">Termin anlegen →</p>
        </Link>
      </div>

      <h2 className="mt-10 text-base font-semibold text-neutral-900">Heute zu tun</h2>
      <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {tasks.map((task) => (
          <Link
            key={task.href}
            href={task.href}
            className="flex items-center justify-between gap-3 rounded-xl border border-black/[0.06] bg-white px-4 py-3 shadow-sm transition-colors hover:border-[#2D2A6E]/40"
          >
            <span className="text-sm font-medium text-neutral-800">{task.label}</span>
            <span
              className={`min-w-8 rounded-full px-2 py-0.5 text-center text-sm font-semibold tabular-nums ${task.count > 0 ? "bg-[#2D2A6E] text-white" : "bg-neutral-100 text-neutral-500"}`}
            >
              {task.count}
            </span>
          </Link>
        ))}
      </div>

      <div className="mt-10 grid gap-6 lg:grid-cols-2">
        <section>
          <h2 className="text-base font-semibold text-neutral-900">Zuletzt geöffnet</h2>
          <p className="mb-3 text-xs text-neutral-500">Nur in diesem Browser gespeichert.</p>
          <RecentlyOpened />
        </section>
        <section>
          <h2 className="text-base font-semibold text-neutral-900">Zuletzt erledigt</h2>
          <p className="mb-3 text-xs text-neutral-500">Deine letzten protokollierten Aktionen.</p>
          {logs.length === 0 ? (
            <p className="text-sm text-neutral-500">Noch keine protokollierten Aktionen.</p>
          ) : (
            <ul className="flex flex-col divide-y divide-black/[0.05] rounded-xl border border-black/[0.06] bg-white shadow-sm">
              {logs.map((log) => {
                const target = LOG_TARGET[log.entity_type];
                const label = `${target?.label ?? log.entity_type} ${ACTION_LABEL[log.action] ?? log.action}`;
                const content = (
                  <span className="flex items-center justify-between gap-3 px-4 py-2.5">
                    <span className="text-sm text-neutral-800">{label}</span>
                    <span className="shrink-0 text-xs text-neutral-400">{logTime.format(new Date(log.created_at))}</span>
                  </span>
                );
                return (
                  <li key={log.id}>
                    {target && log.entity_id ? (
                      <Link href={target.href(log.entity_id)} className="block hover:bg-neutral-50">
                        {content}
                      </Link>
                    ) : (
                      content
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </section>
      </div>

      <h2 className="mt-10 text-base font-semibold text-neutral-900">Bereiche</h2>
      <div className="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {NAV_GROUPS.map((group) => (
          <section key={group.label} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
            <h3 className="text-sm font-semibold text-neutral-900">{group.label}</h3>
            {GROUP_HINTS[group.label] && <p className="text-xs text-neutral-500">{GROUP_HINTS[group.label]}</p>}
            <ul className="mt-3 flex flex-wrap gap-1.5">
              {group.items
                .flatMap((item) => [item, ...(item.tabs ?? []).filter((tab) => tab.href !== item.href)])
                .filter((item, index, all) => item.href !== "/admin" && all.findIndex((other) => other.href === item.href) === index)
                .map((item) => (
                  <li key={item.href}>
                    <Link href={item.href} className="inline-block rounded-lg bg-neutral-100 px-2.5 py-1 text-[13px] text-neutral-700 hover:bg-[#2D2A6E]/10 hover:text-[#2D2A6E]">
                      {item.label}
                    </Link>
                  </li>
                ))}
            </ul>
          </section>
        ))}
      </div>
    </div>
  );
}
