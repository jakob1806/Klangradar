import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import { EmptyRow, TableFrame, Th, dayMonth, tbodyClass, theadClass } from "@/components/admin-kit";
import { undoEventDuplicate } from "./actions";

// Erstellt von Claude Code (Nutzerwunsch 01.11.2026: "Gesamtquelle Bayerische
// Staatsoper"). Zeigt je Quellen-Verbund die beteiligten Quellen mit Rang
// (höherer Rang gewinnt, niedrigerer füllt nur Lücken) und darunter die
// automatischen Zusammenführungen der letzten Tage mit Begründung – jede
// lässt sich rückgängig machen; der Termin gilt dann als "keine Dublette".

interface GroupSource {
  id: string;
  name: string;
  status: string;
  priority: number | null;
  last_success_at: string | null;
  group_id: string | null;
}

interface DuplicateLogRow {
  id: string;
  kept_id: string;
  dropped_id: string;
  score: number;
  reasons: string[];
  filled_fields: string[];
  created_at: string;
  kept: { title: string; start_datetime: string } | null;
  dropped: { title: string; duplicate_of: string | null } | null;
}

const FIELD_LABEL: Record<string, string> = {
  description_de: "Beschreibung",
  price_min: "Preis",
  price_max: "Preis",
  ticket_url: "Ticketlink",
  end_datetime: "Ende",
  image_urls: "Bild",
  primary_image_id: "Bild",
  title: "Schreibweise Titel",
  event_works: "Programm",
  event_participants: "Mitwirkende",
};

export async function SourceGroupsSection() {
  const supabase = await createClient();
  const [{ data: groupRows }, { data: sourceRows }, { data: logRows }, { count: pendingCount }] = await Promise.all([
    supabase.from("source_groups").select("id, slug, name, description").order("name"),
    supabase.from("sources").select("id, name, status, priority, last_success_at, group_id").not("group_id", "is", null),
    supabase
      .from("event_duplicate_log")
      .select("id, kept_id, dropped_id, score, reasons, filled_fields, created_at, kept:events!event_duplicate_log_kept_id_fkey(title, start_datetime), dropped:events!event_duplicate_log_dropped_id_fkey(title, duplicate_of)")
      .order("created_at", { ascending: false })
      .limit(40),
    supabase.from("duplicate_candidates").select("id", { count: "exact", head: true }).eq("status", "pending"),
  ]);
  const groups = (groupRows ?? []) as { id: string; slug: string; name: string; description: string | null }[];
  const sources = (sourceRows ?? []) as GroupSource[];
  const log = (logRows ?? []) as unknown as DuplicateLogRow[];

  return (
    <section className="mt-12">
      <h2 className="text-base font-semibold text-neutral-900">Gesamtquellen</h2>
      <p className="max-w-2xl text-xs text-neutral-500">
        Mehrere Quellen für dasselbe Haus. Termine werden über alle Quellen abgeglichen (Zeit, Saal, Titelwörter, Mitwirkende, Werke). Die Quelle
        mit höherem Rang bestimmt Titel, Zeit und Status, die anderen füllen nur Lücken; Absagen aus Nebenquellen kommen zur Prüfung.
      </p>
      {groups.map((group) => {
        const members = sources.filter((source) => source.group_id === group.id).sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
        return (
          <div key={group.id} className="mt-4 rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
            <p className="font-medium text-neutral-900">{group.name}</p>
            {group.description && <p className="mt-0.5 max-w-3xl text-xs text-neutral-500">{group.description}</p>}
            <div className="mt-3 flex flex-wrap gap-2">
              {members.map((source) => (
                <Link
                  key={source.id}
                  href={`/sources/${source.id}`}
                  className="rounded-lg border border-black/[0.06] px-3 py-2 text-xs hover:bg-neutral-50"
                >
                  <span className="mr-2 rounded bg-[#2D2A6E]/10 px-1.5 py-0.5 font-semibold tabular-nums text-[#2D2A6E]">{source.priority ?? "–"}</span>
                  <span className="font-medium text-neutral-800">{source.name}</span>
                  <span className={`ml-2 ${source.status === "active" ? "text-neutral-400" : "text-amber-700"}`}>
                    {source.status === "active"
                      ? source.last_success_at
                        ? `zuletzt ${dayMonth.format(new Date(source.last_success_at))}`
                        : "noch kein Erfolg"
                      : source.status}
                  </span>
                </Link>
              ))}
            </div>
          </div>
        );
      })}

      <div className="mt-8 flex items-baseline justify-between gap-4">
        <h3 className="text-sm font-semibold text-neutral-900">Automatisch zusammengeführte Termine</h3>
        <Link href="/duplicates" className="text-sm font-medium text-[#2D2A6E] hover:underline">
          {pendingCount ?? 0} unsichere Fälle prüfen →
        </Link>
      </div>
      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Behalten</Th>
              <Th>Ausgeblendet</Th>
              <Th>Begründung</Th>
              <Th>Übernommen</Th>
              <Th />
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {log.map((row) => {
              const filled = Array.from(new Set(row.filled_fields.map((field) => FIELD_LABEL[field] ?? field)));
              const undone = !row.dropped?.duplicate_of;
              return (
                <tr key={row.id} className="align-top">
                  <td className="px-4 py-3">
                    <Link href={`/events/${row.kept_id}`} className="font-medium text-neutral-900 hover:underline">
                      {row.kept?.title ?? "–"}
                    </Link>
                    {row.kept && <p className="text-xs text-neutral-500">{dayMonth.format(new Date(row.kept.start_datetime))}</p>}
                  </td>
                  <td className="px-4 py-3 text-neutral-600">
                    <Link href={`/events/${row.dropped_id}`} className="hover:underline">
                      {row.dropped?.title ?? "–"}
                    </Link>
                  </td>
                  <td className="max-w-xs px-4 py-3 text-xs text-neutral-500">{row.reasons.join(" · ")}</td>
                  <td className="px-4 py-3 text-xs text-neutral-500">{filled.length ? filled.join(", ") : "–"}</td>
                  <td className="px-4 py-3">
                    {undone ? (
                      <span className="text-xs text-neutral-400">getrennt</span>
                    ) : (
                      <form action={undoEventDuplicate.bind(null, row.dropped_id)}>
                        <SubmitButton pendingLabel="Trenne …">Trennen</SubmitButton>
                      </form>
                    )}
                  </td>
                </tr>
              );
            })}
            {log.length === 0 && <EmptyRow colSpan={5}>Noch keine automatischen Zusammenführungen.</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>
    </section>
  );
}
