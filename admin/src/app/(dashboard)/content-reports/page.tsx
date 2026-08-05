import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { resolveContentReport, dismissContentReport } from "./actions";

export const dynamic = "force-dynamic";

interface ReportRow {
  id: string;
  entity_type: "event" | "venue" | "person" | "ensemble";
  entity_id: string;
  reason: string;
  message: string | null;
  created_at: string;
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

export default async function ContentReportsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("content_reports")
    .select("id, entity_type, entity_id, reason, message, created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .returns<ReportRow[]>();

  const entityNames = data ? await loadEntityNames(supabase, data) : new Map<string, string>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Nutzer-Meldungen</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Von Nutzer:innen in der App gemeldete Datenprobleme (falsches Bild, falsche Zeit, defekter Ticketlink
        etc.). Ändert nie automatisch Daten — bitte die zugrundeliegende Angabe im jeweiligen Formular selbst
        korrigieren, dann als &quot;Erledigt&quot; markieren.
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Meldungen nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((report) => {
              const name = entityNames.get(`${report.entity_type}:${report.entity_id}`) ?? "(nicht mehr gefunden)";
              return (
                <div key={report.id} className="rounded-lg border border-neutral-200 bg-white p-4">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="rounded-full bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-700">
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
                    <div className="flex items-center gap-4">
                      <ConfirmButton
                        action={dismissContentReport.bind(null, report.id)}
                        confirmMessage="Ohne Handlungsbedarf verwerfen?"
                        label="Verwerfen"
                        pendingLabel="Speichere…"
                        className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                      />
                      <ConfirmButton
                        action={resolveContentReport.bind(null, report.id)}
                        confirmMessage="Als erledigt markieren?"
                        label="Erledigt"
                        pendingLabel="Speichere…"
                        className="text-sm font-medium text-green-700 hover:text-green-900 disabled:opacity-50"
                      />
                    </div>
                  </div>
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
