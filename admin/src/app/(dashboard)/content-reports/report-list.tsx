import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolveContentReport, dismissContentReport } from "./actions";
import { AutoFixAllButton } from "./auto-fix-all-button";
import { AutoFixButton } from "./auto-fix-button";
import { ReportSourceTabs } from "@/components/report-source-tabs";

interface ReportRow {
  id: string;
  entity_type: "event" | "venue" | "person" | "ensemble";
  entity_id: string;
  reason: string;
  message: string | null;
  created_at: string;
}

interface FixRow {
  report_id: string;
  status: "fixed" | "needs_manual_review" | "error" | "code_bug_suspected";
  diagnosis: string;
  action_taken: string | null;
  created_at: string;
}

const FIX_STATUS_STYLE: Record<FixRow["status"], string> = {
  fixed: "bg-green-50 text-green-800 border-green-200",
  needs_manual_review: "bg-amber-50 text-amber-800 border-amber-200",
  error: "bg-red-50 text-red-700 border-red-200",
  code_bug_suspected: "bg-violet-50 text-violet-800 border-violet-200",
};

const FIX_STATUS_LABEL: Record<FixRow["status"], string> = {
  fixed: "Automatisch behoben",
  needs_manual_review: "Manuelle Prüfung nötig",
  error: "Fehler beim Fix-Versuch",
  code_bug_suspected: "Historischer struktureller Fehler",
};

/** Letzter Fix-Versuch pro Meldung (falls vorhanden) — content_report_fixes
 * kann mehrere Zeilen pro Meldung haben (mehrfache "Erneut versuchen"-
 * Klicks), hier zählt nur der jüngste. */
async function loadLatestFixes(
  supabase: Awaited<ReturnType<typeof createClient>>,
  reportIds: string[],
) {
  if (reportIds.length === 0) return new Map<string, FixRow>();
  const { data } = await supabase
    .from("content_report_fixes")
    .select("report_id, status, diagnosis, action_taken, created_at")
    .in("report_id", reportIds)
    .order("created_at", { ascending: false })
    .returns<FixRow[]>();

  const latest = new Map<string, FixRow>();
  for (const row of data ?? []) {
    if (!latest.has(row.report_id)) latest.set(row.report_id, row);
  }
  return latest;
}

const REASON_LABEL: Record<string, string> = {
  wrong_image: "Falsches Bild",
  wrong_time: "Falsche Uhrzeit",
  cancelled: "Veranstaltung abgesagt",
  wrong_artist: "Falsche Künstler-/Werkzuordnung",
  broken_ticket_link: "Ticketlink defekt",
  missing_program: "Programminformation fehlt",
  other: "Sonstiges",
};

const ENTITY_LABEL: Record<ReportRow["entity_type"], string> = {
  event: "Veranstaltung",
  venue: "Venue",
  person: "Person",
  ensemble: "Ensemble",
};

const ENTITY_TABLE: Record<ReportRow["entity_type"], string> = {
  event: "events",
  venue: "venues",
  person: "persons",
  ensemble: "ensembles",
};

const ENTITY_NAME_COLUMN: Record<ReportRow["entity_type"], string> = {
  event: "title",
  venue: "name",
  person: "full_name",
  ensemble: "name",
};

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

/** Meldungen verweisen polymorph auf events/venues/persons/ensembles (kein
 * FK möglich, siehe content_reports-Migration) — Anzeigenamen werden daher
 * pro Entitätstyp in einem Rutsch nachgeladen statt einzeln pro Zeile. */
async function loadEntityNames(
  supabase: Awaited<ReturnType<typeof createClient>>,
  reports: ReportRow[],
) {
  const names = new Map<string, string>();
  const types = Array.from(new Set(reports.map((r) => r.entity_type)));

  await Promise.all(
    types.map(async (type) => {
      const ids = Array.from(
        new Set(reports.filter((r) => r.entity_type === type).map((r) => r.entity_id)),
      );
      const { data } = await supabase
        .from(ENTITY_TABLE[type])
        .select(`id, ${ENTITY_NAME_COLUMN[type]}`)
        .in("id", ids);
      for (const row of (data as Array<Record<string, string>> | null) ?? []) {
        names.set(`${type}:${row.id}`, row[ENTITY_NAME_COLUMN[type]] ?? "(ohne Titel)");
      }
    }),
  );

  return names;
}

// Sortiert die Reihenfolge, in der Meldungen im Ergebnis erscheinen, statt
// rein chronologisch — Nutzerfeedback: "sehr unübersichtlich gestaltet".
// Bereits automatisch behobene Meldungen (warten nur noch auf die
// redaktionelle "Erledigt"-Bestätigung) zuerst, dann Fehler/manuelle
// Prüfung nötig (aktiv etwas zu tun), zuletzt noch nie versuchte Meldungen
// — sonst verschwinden schnell erledigbare Fälle in der chronologischen
// Liste zwischen lauter noch unbearbeiteten.
const STATUS_SORT_RANK: Record<FixRow["status"] | "none", number> = {
  fixed: 0,
  needs_manual_review: 1,
  error: 1,
  code_bug_suspected: 1,
  none: 2,
};

const CARD_BORDER_STYLE: Record<FixRow["status"] | "none", string> = {
  fixed: "border-l-emerald-500",
  needs_manual_review: "border-l-amber-500",
  error: "border-l-red-500",
  code_bug_suspected: "border-l-violet-500",
  none: "border-l-neutral-300",
};

/** Meldungsliste für EINE Herkunfts-App (Flutter oder native) — Nutzeranfrage:
 * "unterscheide dann aber bei nutzermeldungen zwischen native und flutter,
 * mache dafür eine eigene kategorie unter 'redaktion' auf". Beide Apps
 * schreiben in dieselbe content_reports-Tabelle (siehe platform-Spalte,
 * Migration 20261011000006), diese Komponente filtert nur die Anzeige —
 * die Server Actions (Erledigt/Verwerfen/Auto-Fix) bleiben plattform-
 * unabhängig und wirken auf die konkrete report.id. */
export async function ContentReportsList({
  platform,
  title,
  description,
}: {
  platform: "flutter" | "native";
  title: string;
  description: string;
}) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("content_reports")
    .select("id, entity_type, entity_id, reason, message, created_at")
    .eq("status", "pending")
    .eq("platform", platform)
    .order("created_at", { ascending: false })
    .returns<ReportRow[]>();

  const entityNames = data ? await loadEntityNames(supabase, data) : new Map<string, string>();
  const latestFixes = data ? await loadLatestFixes(supabase, data.map((r) => r.id)) : new Map<string, FixRow>();

  const sorted = [...(data ?? [])].sort((a, b) => {
    const rankA = STATUS_SORT_RANK[latestFixes.get(a.id)?.status ?? "none"];
    const rankB = STATUS_SORT_RANK[latestFixes.get(b.id)?.status ?? "none"];
    if (rankA !== rankB) return rankA - rankB;
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
  });

  const counts = { fixed: 0, needsAttention: 0, untried: 0 };
  for (const report of data ?? []) {
    const status = latestFixes.get(report.id)?.status;
    if (status === "fixed") counts.fixed++;
    else if (status === "needs_manual_review" || status === "error" || status === "code_bug_suspected") counts.needsAttention++;
    else counts.untried++;
  }

  return (
    <div className="mx-auto max-w-6xl p-6 lg:p-8">
      <ReportSourceTabs activeHref={platform === "native" ? "/content-reports-native" : "/content-reports"} />
      <div className="flex flex-col gap-4 border-b border-black/[0.08] pb-5 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
          <p className="mt-1 max-w-2xl text-sm text-neutral-500">{description}</p>
        </div>
        <AutoFixAllButton platform={platform} />
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Meldungen nicht laden: {error.message}</p>}

      {!error && data && data.length > 0 && (
        <div className="mt-5 grid grid-cols-3 overflow-hidden rounded-xl border border-black/[0.07] bg-white shadow-sm">
          <div className="px-4 py-3">
            <p className="text-xl font-semibold text-emerald-700">{counts.fixed}</p>
            <p className="text-xs text-neutral-500">behoben · Bestätigung offen</p>
          </div>
          <div className="border-l border-black/[0.07] px-4 py-3">
            <p className="text-xl font-semibold text-amber-700">{counts.needsAttention}</p>
            <p className="text-xs text-neutral-500">Prüfung erforderlich</p>
          </div>
          <div className="border-l border-black/[0.07] px-4 py-3">
            <p className="text-xl font-semibold text-neutral-700">{counts.untried}</p>
            <p className="text-xs text-neutral-500">noch nicht geprüft</p>
          </div>
        </div>
      )}

      {!error && (
        <div className="mt-4 flex flex-col gap-2.5">
          {sorted.length ? (
            sorted.map((report) => {
              const name = entityNames.get(`${report.entity_type}:${report.entity_id}`) ?? "(nicht mehr gefunden)";
              const lastFix = latestFixes.get(report.id);
              return (
                <div
                  key={report.id}
                  className={`rounded-xl border border-l-[3px] border-black/[0.07] bg-white px-4 py-3 shadow-sm ${CARD_BORDER_STYLE[lastFix?.status ?? "none"]}`}
                >
                  <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start">
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="rounded-full bg-amber-50 px-2 py-1 type-label !text-amber-700">
                          {REASON_LABEL[report.reason] ?? report.reason}
                        </span>
                        <span className="text-xs text-neutral-400">{formatDate(report.created_at)}</span>
                        {lastFix && (
                          <span className={`rounded-full border px-2 py-0.5 text-[11px] font-medium ${FIX_STATUS_STYLE[lastFix.status]}`}>
                            {FIX_STATUS_LABEL[lastFix.status]}
                          </span>
                        )}
                      </div>
                      <p className="mt-2 truncate text-sm font-semibold text-neutral-900">
                        <span className="font-normal text-neutral-500">{ENTITY_LABEL[report.entity_type]} · </span>
                        <a
                          href={`/${ENTITY_TABLE[report.entity_type]}/${report.entity_id}`}
                          className="text-blue-700 hover:underline"
                        >
                          {name}
                        </a>
                      </p>
                      {report.message && (
                        <p className="mt-1 line-clamp-2 text-sm leading-5 text-neutral-600">{report.message}</p>
                      )}
                    </div>
                    <div className="flex shrink-0 flex-wrap items-center justify-end gap-2">
                      <AutoFixButton reportId={report.id} alreadyTried={Boolean(lastFix)} />
                      <ConfirmButton
                        action={dismissContentReport.bind(null, report.id)}
                        confirmMessage="Ohne Handlungsbedarf verwerfen?"
                        label="Verwerfen"
                        pendingLabel="…"
                        className="rounded-lg border border-black/10 px-2.5 py-1.5 text-xs font-medium text-neutral-600 hover:bg-black/[0.04] disabled:opacity-50"
                      />
                      <ConfirmButton
                        action={resolveContentReport.bind(null, report.id)}
                        confirmMessage="Als erledigt markieren?"
                        label="Erledigt"
                        pendingLabel="…"
                        className="rounded-lg border border-emerald-600 bg-white px-2.5 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
                      />
                    </div>
                  </div>
                  {lastFix && (
                    <details className="group mt-2 border-t border-black/[0.06] pt-2 text-xs text-neutral-600">
                      <summary className="cursor-pointer list-none font-medium text-neutral-500 hover:text-neutral-900">
                        <span className="group-open:hidden">Diagnose anzeigen</span>
                        <span className="hidden group-open:inline">Diagnose ausblenden</span>
                        <span className="ml-2 font-normal text-neutral-400">{formatDate(lastFix.created_at)}</span>
                      </summary>
                      <div className={`mt-2 rounded-lg border px-3 py-2 leading-5 ${FIX_STATUS_STYLE[lastFix.status]}`}>
                        <p>{lastFix.diagnosis}</p>
                        {lastFix.action_taken && <p className="mt-1 font-medium">Änderung: {lastFix.action_taken}</p>}
                      </div>
                    </details>
                  )}
                </div>
              );
            })
          ) : (
            <p className="text-sm text-neutral-500">Keine offenen Meldungen.</p>
          )}
        </div>
      )}
    </div>
  );
}
