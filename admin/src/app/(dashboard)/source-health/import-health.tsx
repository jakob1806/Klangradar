import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import { EmptyRow, TableFrame, Th, dayMonth, inputClass, tbodyClass, theadClass } from "@/components/admin-kit";
import { addVenueAlias } from "./actions";

// Erstellt von Claude Code (Nutzerwunsch 31.10.2026: Überwachung der
// Importquellen). Ampel je Quelle aus admin_import_health(): rot = seit
// über 3 Tagen kein erfolgreicher Lauf, gelb = mehr als die Hälfte der
// Läufe gescheitert oder Treffer ohne kommende Termine. Darunter die
// Spielstätten, die der Import nicht zuordnen konnte.

interface ImportHealth {
  source_id: string;
  name: string;
  type: string;
  status: string;
  city: string | null;
  last_success_at: string | null;
  days_since_success: number | null;
  runs_7d: number;
  failed_7d: number;
  timeouts_7d: number;
  found_7d: number;
  created_7d: number;
  upcoming: number;
  top_error: string | null;
  health: "ok" | "warn" | "error" | "paused";
}

interface UnmatchedVenue {
  venue_name: string;
  city: string | null;
  occurrences: number;
  sources: string;
  example_event: string | null;
}

const CITY_LABEL: Record<string, string> = { munich: "München", berlin: "Berlin", hamburg: "Hamburg", vienna: "Wien", frankfurt: "Frankfurt" };

const HEALTH_STYLE: Record<ImportHealth["health"], { label: string; className: string }> = {
  error: { label: "Ausfall", className: "bg-red-50 text-red-700" },
  warn: { label: "Auffällig", className: "bg-amber-50 text-amber-800" },
  ok: { label: "OK", className: "bg-emerald-50 text-emerald-700" },
  paused: { label: "Pausiert", className: "bg-neutral-100 text-neutral-500" },
};

export async function ImportHealthSection() {
  const supabase = await createClient();
  const [{ data: healthData, error }, { data: venueData }, { data: venueRows }] = await Promise.all([
    supabase.rpc("admin_import_health"),
    supabase.rpc("admin_unmatched_venues", { p_days: 14 }),
    supabase.from("venues").select("id, name, city_id, regions:city_id(slug)").order("name"),
  ]);
  const sources = (healthData ?? []) as ImportHealth[];
  const unmatched = (venueData ?? []) as UnmatchedVenue[];
  const venues = (venueRows ?? []) as unknown as { id: string; name: string; regions: { slug: string } | null }[];
  const counts = { error: 0, warn: 0, ok: 0, paused: 0 };
  for (const source of sources) counts[source.health]++;

  return (
    <section className="mt-12">
      <h2 className="text-base font-semibold text-neutral-900">Importquellen</h2>
      <p className="max-w-2xl text-xs text-neutral-500">
        Ersterfassung der Termine aus allen Quellen, letzte 7 Tage. Rot: seit über 3 Tagen kein erfolgreicher Lauf. Gelb: mehr als die Hälfte der
        Läufe gescheitert oder Treffer ohne kommende Termine.
      </p>
      {error && <p className="mt-2 text-sm text-amber-700">Konnte Daten nicht laden: {error.message}</p>}
      <div className="mt-3 flex flex-wrap gap-2 text-xs">
        {(["error", "warn", "ok", "paused"] as const).map((key) => (
          <span key={key} className={`rounded-full px-2.5 py-1 font-medium ${HEALTH_STYLE[key].className}`}>
            {HEALTH_STYLE[key].label}: {counts[key]}
          </span>
        ))}
      </div>
      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Quelle</Th>
              <Th>Status</Th>
              <Th>Letzter Erfolg</Th>
              <Th>Läufe 7 T.</Th>
              <Th>Kommend</Th>
              <Th>Letzter Fehler</Th>
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {sources.map((source) => (
              <tr key={source.source_id} className="align-top">
                <td className="px-4 py-3">
                  <Link href={`/sources/${source.source_id}`} className="font-medium text-neutral-900 hover:underline">
                    {source.name}
                  </Link>
                  <p className="text-xs text-neutral-500">
                    {source.type} · {CITY_LABEL[source.city ?? ""] ?? source.city ?? "–"}
                  </p>
                </td>
                <td className="px-4 py-3">
                  <span className={`whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium ${HEALTH_STYLE[source.health].className}`}>
                    {HEALTH_STYLE[source.health].label}
                  </span>
                </td>
                <td className="whitespace-nowrap px-4 py-3 text-neutral-600">
                  {source.last_success_at ? dayMonth.format(new Date(source.last_success_at)) : "nie"}
                  {source.days_since_success != null && source.days_since_success > 0 && (
                    <span className="block text-xs text-neutral-400">vor {source.days_since_success} Tagen</span>
                  )}
                </td>
                <td className="whitespace-nowrap px-4 py-3 tabular-nums text-neutral-600">
                  {source.runs_7d}
                  {source.failed_7d > 0 && <span className="block text-xs text-red-600">{source.failed_7d} gescheitert</span>}
                  {source.timeouts_7d > 0 && <span className="block text-xs text-neutral-400">{source.timeouts_7d} Zeitlimit</span>}
                </td>
                <td className="px-4 py-3 tabular-nums text-neutral-600">{source.upcoming}</td>
                <td className="max-w-md px-4 py-3 text-xs text-neutral-500">{source.top_error ?? "–"}</td>
              </tr>
            ))}
            {!error && sources.length === 0 && <EmptyRow colSpan={6}>Keine Quellen.</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>

      <h2 className="mt-12 text-base font-semibold text-neutral-900">Nicht zugeordnete Spielstätten</h2>
      <p className="max-w-2xl text-xs text-neutral-500">
        Diese Ortsnamen konnte der Import in den letzten 14 Tagen keiner Spielstätte zuordnen – die Termine wurden übersprungen. Ist der Ort schon
        angelegt, als Alias zuordnen; sonst neu anlegen. Der nächste Import übernimmt die Termine.
      </p>
      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Ortsname aus der Quelle</Th>
              <Th>Treffer</Th>
              <Th>Quelle</Th>
              <Th>Zuordnen</Th>
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {unmatched.map((row) => {
              const options = venues.filter((venue) => !row.city || venue.regions?.slug === row.city);
              return (
                <tr key={`${row.venue_name}|${row.city}`} className="align-top">
                  <td className="px-4 py-3">
                    <p className="font-medium text-neutral-900">{row.venue_name}</p>
                    <p className="text-xs text-neutral-500">
                      {CITY_LABEL[row.city ?? ""] ?? row.city ?? "–"}
                      {row.example_event ? ` · z. B. „${row.example_event}“` : ""}
                    </p>
                  </td>
                  <td className="px-4 py-3 tabular-nums">{row.occurrences}</td>
                  <td className="px-4 py-3 text-xs text-neutral-500">{row.sources}</td>
                  <td className="px-4 py-3">
                    <form action={addVenueAlias.bind(null, row.venue_name)} className="flex flex-wrap items-center gap-2">
                      <select name="venue_id" required defaultValue="" className={`${inputClass} w-56`}>
                        <option value="" disabled>
                          Bestehende Spielstätte …
                        </option>
                        {options.map((venue) => (
                          <option key={venue.id} value={venue.id}>
                            {venue.name}
                          </option>
                        ))}
                      </select>
                      <SubmitButton pendingLabel="Speichere …">Als Alias</SubmitButton>
                      <Link href="/venues/new" className="text-sm font-medium text-[#2D2A6E] hover:underline">
                        Neu anlegen
                      </Link>
                    </form>
                  </td>
                </tr>
              );
            })}
            {unmatched.length === 0 && <EmptyRow colSpan={4}>Alle Ortsnamen wurden zugeordnet.</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>
    </section>
  );
}
