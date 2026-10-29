/* eslint-disable @next/next/no-img-element */
import { createClient } from "@/lib/supabase/server";
import { ConfirmButton } from "@/components/confirm-button";
import {
  AdminPageHeader, EmptyRow, FilterTabs, StatTile, TableFrame, Th, dayMonthYear, tbodyClass, theadClass,
} from "@/components/admin-kit";
import { resolveUserReport, withdrawFriendRequests } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Moderation für die
// Freunde-Funktionen. Oben gemeldete Profile (aus der App: Profil → Melden),
// darunter Konten mit auffällig vielen offenen Freundschaftsanfragen in den
// letzten 7 Tagen, z. B. über "Wer war noch da?".

interface Report {
  report_id: number;
  created_at: string;
  reason: string;
  message: string | null;
  reporter_name: string | null;
  reported_id: string;
  reported_name: string | null;
  reported_bio: string | null;
  reported_avatar_url: string | null;
  reported_is_public: boolean;
  reports_against: number;
  handled_at: string | null;
  resolution: string | null;
}

interface Activity {
  user_id: string;
  display_name: string | null;
  sent: number;
  from_concerts: number;
  oldest: string;
}

const REASONS: Record<string, string> = {
  spam: "Spam",
  inappropriate: "Unangemessen",
  impersonation: "Gibt sich als jemand anderes aus",
  other: "Sonstiges",
};

const RESOLUTIONS: Record<string, string> = {
  dismissed: "Erledigt ohne Eingriff",
  made_private: "Profil auf privat gesetzt",
};

export default async function ModerationPage({ searchParams }: { searchParams: Promise<{ show?: string }> }) {
  const { show } = await searchParams;
  const openOnly = show !== "all";
  const supabase = await createClient();
  const [{ data: reportData, error: reportError }, { data: activityData, error: activityError }] = await Promise.all([
    supabase.rpc("admin_user_reports", { p_open_only: openOnly }),
    supabase.rpc("admin_friend_request_activity", { p_days: 7, p_min: 10 }),
  ]);
  const reports = (reportData ?? []) as Report[];
  const activity = (activityData ?? []) as Activity[];
  const error = reportError ?? activityError;
  const open = reports.filter((report) => !report.handled_at);

  return (
    <div className="p-8">
      <AdminPageHeader
        title="Community-Moderation"
        description="Gemeldete Profile aus den Freunde-Funktionen und Konten, die auffällig viele Freundschaftsanfragen verschicken. Inhalte einzelner Nachrichten oder Konzertbesuche sind hier bewusst nicht sichtbar."
      />

      {error && <p className="mt-4 text-sm text-amber-700">Konnte Daten nicht laden: {error.message}</p>}

      <div className="mt-6 grid gap-3 sm:grid-cols-3">
        <StatTile label="Offene Meldungen" value={open.length} />
        <StatTile label="Gemeldete Personen" value={new Set(open.map((report) => report.reported_id)).size} />
        <StatTile label="Auffällige Konten" value={activity.length} hint="≥ 10 Anfragen in 7 Tagen" />
      </div>

      <div className="mt-8 flex flex-wrap items-end justify-between gap-3">
        <h2 className="text-base font-semibold text-neutral-900">Gemeldete Profile</h2>
        <FilterTabs
          active={openOnly ? "open" : "all"}
          items={[
            { key: "open", label: "Offen", href: "/moderation" },
            { key: "all", label: "Alle", href: "/moderation?show=all" },
          ]}
        />
      </div>

      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Gemeldetes Profil</Th>
              <Th>Grund</Th>
              <Th>Gemeldet von</Th>
              <Th>Datum</Th>
              <Th />
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {reports.map((report) => (
              <tr key={report.report_id} className="align-top">
                <td className="px-4 py-3">
                  <div className="flex items-start gap-3">
                    <div className="size-9 shrink-0 overflow-hidden rounded-full bg-neutral-100">
                      {report.reported_avatar_url && <img src={report.reported_avatar_url} alt="" className="size-full object-cover" />}
                    </div>
                    <div className="min-w-0 max-w-xs">
                      <p className="font-medium text-neutral-900">
                        {report.reported_name ?? "Ohne Namen"}
                        {report.reports_against > 1 && (
                          <span className="ml-2 rounded bg-red-50 px-1.5 py-0.5 text-[11px] font-semibold text-red-700">{report.reports_against}× gemeldet</span>
                        )}
                      </p>
                      <p className="text-xs text-neutral-500">{report.reported_is_public ? "Öffentliches Profil" : "Privates Profil"}</p>
                      {report.reported_bio && <p className="mt-1 text-xs text-neutral-700">„{report.reported_bio}“</p>}
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <p className="font-medium text-neutral-800">{REASONS[report.reason] ?? report.reason}</p>
                  {report.message && <p className="mt-1 max-w-xs text-xs text-neutral-600">{report.message}</p>}
                </td>
                <td className="px-4 py-3 text-neutral-600">{report.reporter_name ?? "–"}</td>
                <td className="whitespace-nowrap px-4 py-3">{dayMonthYear.format(new Date(report.created_at))}</td>
                <td className="px-4 py-3">
                  {report.handled_at ? (
                    <span className="text-xs text-neutral-500">{RESOLUTIONS[report.resolution ?? ""] ?? "Erledigt"}</span>
                  ) : (
                    <div className="flex flex-col items-end gap-2">
                      <ConfirmButton
                        action={resolveUserReport.bind(null, report.report_id, "made_private")}
                        confirmMessage="Profil privat schalten, Bio und Bild entfernen?"
                        label="Profil privat schalten"
                        pendingLabel="Wird umgesetzt …"
                      />
                      <ConfirmButton
                        action={resolveUserReport.bind(null, report.report_id, "dismissed")}
                        confirmMessage="Ohne Eingriff schließen?"
                        label="Erledigt"
                        pendingLabel="Schließe …"
                      />
                    </div>
                  )}
                </td>
              </tr>
            ))}
            {!reportError && reports.length === 0 && <EmptyRow colSpan={5}>{openOnly ? "Keine offenen Meldungen." : "Noch keine Meldungen."}</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>

      <div className="mt-10">
        <h2 className="text-base font-semibold text-neutral-900">Viele Freundschaftsanfragen</h2>
        <p className="text-xs text-neutral-500">Offene Anfragen der letzten 7 Tage, ab 10 pro Konto. „Über Konzerte“ = aus „Wer war noch da?“.</p>
      </div>

      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Konto</Th>
              <Th>Offene Anfragen</Th>
              <Th>Über Konzerte</Th>
              <Th>Seit</Th>
              <Th />
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {activity.map((row) => (
              <tr key={row.user_id}>
                <td className="px-4 py-3 font-medium text-neutral-900">{row.display_name ?? "Ohne Namen"}</td>
                <td className="px-4 py-3 tabular-nums">{row.sent}</td>
                <td className="px-4 py-3 tabular-nums">{row.from_concerts}</td>
                <td className="whitespace-nowrap px-4 py-3">{dayMonthYear.format(new Date(row.oldest))}</td>
                <td className="px-4 py-3 text-right">
                  <ConfirmButton
                    action={withdrawFriendRequests.bind(null, row.user_id)}
                    confirmMessage={`Alle ${row.sent} offenen Anfragen zurückziehen?`}
                    label="Anfragen zurückziehen"
                    pendingLabel="Ziehe zurück …"
                  />
                </td>
              </tr>
            ))}
            {!activityError && activity.length === 0 && <EmptyRow colSpan={5}>Keine auffälligen Konten.</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>
    </div>
  );
}
