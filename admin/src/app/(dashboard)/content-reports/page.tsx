import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolveContentReport, dismissContentReport } from "./actions";
import { AutoFixAllButton } from "./auto-fix-all-button";
import { AutoFixButton } from "./auto-fix-button";

export const dynamic = "force-dynamic";

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
  status: "fixed" | "needs_manual_review" | "error";
  diagnosis: string;
  action_taken: string | null;
  created_at: string;
}

const FIX_STATUS_STYLE: Record<FixRow["status"], string> = {
  fixed: "bg-green-50 text-green-800 border-green-200",
  needs_manual_review: "bg-amber-50 text-amber-800 border-amber-200",
  error: "bg-red-50 text-red-700 border-red-200",
};

const FIX_STATUS_LABEL: Record<FixRow["status"], string> = {
  fixed: "Automatisch behoben",
  needs_manual_review: "Manuelle Prüfung nötig",
  error: "Fehler beim Fix-Versuch",
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
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
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
  none: 2,
};

const CARD_BORDER_STYLE: Record<FixRow["status"] | "none", string> = {
  fixed: "border-l-4 border-l-green-400",
  needs_manual_review: "border-l-4 border-l-amber-400",
  error: "border-l-4 border-l-red-400",
  none: "border-l-4 border-l-neutral-200",
};

export default async function ContentReportsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("content_reports")
    .select("id, entity_type, entity_id, reason, message, created_at")
    .eq("status", "pending")
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
    else if (status === "needs_manual_review" || status === "error") counts.needsAttention++;
    else counts.untried++;
  }

  return (
    <div className="p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Nutzer-Meldungen</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Von Nutzer:innen in der App gemeldete Datenprobleme (falsches Bild, falsche Zeit, defekter Ticketlink
            etc.). Der ursprüngliche redaktionelle Fluss ändert nie automatisch Daten — &quot;Automatisch fixen&quot;
            ist ein separater, vorsichtig geprüfter Weg (Feld-Allowlist, Beleg-Zitat aus der echten Quellseite
            nötig, bei fehlender Quell-URL zusätzlich eigene Websuche), der bei Erfolg direkt speichert und immer
            einen Diagnose-Bericht hinterlässt. Läuft zusätzlich alle 30 Minuten automatisch für noch nie versuchte
            Meldungen.
          </p>
        </div>
        <AutoFixAllButton />
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Meldungen nicht laden: {error.message}</p>}

      {!error && data && data.length > 0 && (
        <div className="mt-6 flex gap-3 text-xs">
          <span className="border border-emerald-700 bg-white px-2.5 py-1.5 type-label !text-emerald-700">
            {counts.fixed} automatisch behoben, wartet auf Bestätigung
          </span>
          <span className="border border-amber-700 bg-white px-2.5 py-1.5 type-label !text-amber-700">
            {counts.needsAttention} brauchen manuelle Prüfung
          </span>
          <span className="border border-neutral-300 bg-white px-2.5 py-1.5 type-label !text-neutral-500">
            {counts.untried} noch nicht versucht
          </span>
        </div>
      )}

      {!error && (
        <div className="mt-4 flex flex-col gap-3">
          {sorted.length ? (
            sorted.map((report) => {
              const name = entityNames.get(`${report.entity_type}:${report.entity_id}`) ?? "(nicht mehr gefunden)";
              const lastFix = latestFixes.get(report.id);
              return (
                <div
                  key={report.id}
                  className={`border-2 border-[#171717] bg-white p-4 ${CARD_BORDER_STYLE[lastFix?.status ?? "none"]}`}
                >
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="border border-amber-700 px-2 py-1 type-label !text-amber-700">
                          {REASON_LABEL[report.reason] ?? report.reason}
                        </span>
                        <span className="text-xs text-neutral-400">{formatDate(report.created_at)}</span>
                      </div>
                      <p className="mt-2 text-sm font-medium text-neutral-900">
                        {ENTITY_LABEL[report.entity_type]}:{" "}
                        <a
                          href={`/${ENTITY_TABLE[report.entity_type]}/${report.entity_id}`}
                          className="text-blue-700 hover:underline"
                        >
                          {name}
                        </a>
                      </p>
                      {report.message && (
                        <p className="mt-1 text-sm text-neutral-600">{report.message}</p>
                      )}
                    </div>
                    <div className="flex shrink-0 flex-wrap items-start justify-end gap-2">
                      <ConfirmButton
                        action={dismissContentReport.bind(null, report.id)}
                        confirmMessage="Ohne Handlungsbedarf verwerfen?"
                        label="Verwerfen"
                        pendingLabel="…"
                        className="border border-neutral-300 px-2.5 py-1.5 text-xs font-medium text-neutral-600 hover:border-[#171717] hover:text-[#171717] disabled:opacity-50"
                      />
                      <ConfirmButton
                        action={resolveContentReport.bind(null, report.id)}
                        confirmMessage="Als erledigt markieren?"
                        label="Erledigt"
                        pendingLabel="…"
                        className="border-2 border-emerald-700 bg-white px-2.5 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
                      />
                      <AutoFixButton reportId={report.id} alreadyTried={Boolean(lastFix)} />
                    </div>
                  </div>
                  {lastFix && (
                    <div className={`mt-3 rounded-md border px-3 py-2 text-xs ${FIX_STATUS_STYLE[lastFix.status]}`}>
                      <p className="font-medium">
                        Letzter automatischer Fix-Versuch: {FIX_STATUS_LABEL[lastFix.status]} ({formatDate(lastFix.created_at)})
                      </p>
                      <p className="mt-0.5">{lastFix.diagnosis}</p>
                      {lastFix.action_taken && (
                        <p className="mt-0.5 font-medium">Änderung: {lastFix.action_taken}</p>
                      )}
                    </div>
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
