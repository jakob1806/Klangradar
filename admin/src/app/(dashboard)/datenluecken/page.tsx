import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import {
  AdminPageHeader, CoverageTile, EmptyRow, FilterTabs, TableFrame, Th, dayMonth, tbodyClass, theadClass,
} from "@/components/admin-kit";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): ein Cockpit für alle
// Datenlücken kommender Termine nach dem Muster der Werkeinführungen —
// Abdeckung je Feld und darunter die Termine mit Lücke, die meistgemerkten
// und nächsten zuerst.

interface Coverage {
  total: number;
  image: number;
  cast: number;
  program: number;
  ticket: number;
  price: number;
}

interface GapEvent {
  event_id: string;
  title: string;
  start_datetime: string;
  venue_name: string | null;
  organizer_name: string | null;
  saves: number;
}

const GAPS = [
  { key: "image", label: "Eigenes Bild", missing: "ohne eigenes Bild (in der App mit Ersatzbild der Spielstätte)" },
  { key: "cast", label: "Besetzung", missing: "ohne Besetzung" },
  { key: "program", label: "Programm", missing: "ohne Programm" },
  { key: "ticket", label: "Ticket-Link", missing: "ohne Ticket-Link" },
  { key: "price", label: "Preis", missing: "ohne Preis" },
] as const;

const RANGES = [
  { key: "30", label: "30 Tage" },
  { key: "90", label: "90 Tage" },
  { key: "365", label: "12 Monate" },
];

export default async function DataGapsPage({ searchParams }: { searchParams: Promise<{ gap?: string; days?: string }> }) {
  const params = await searchParams;
  const gap = GAPS.find((g) => g.key === params.gap) ?? GAPS[0];
  const days = RANGES.some((r) => r.key === params.days) ? Number(params.days) : 90;
  const supabase = await createClient();
  const [{ data: coverageData, error: coverageError }, { data: eventData, error: eventError }] = await Promise.all([
    supabase.rpc("admin_data_gap_coverage", { p_days: days }),
    supabase.rpc("admin_events_with_gap", { p_gap: gap.key, p_days: days, p_limit: 150 }),
  ]);
  const coverage = coverageData as Coverage | null;
  const events = (eventData ?? []) as GapEvent[];
  const error = coverageError ?? eventError;

  return (
    <div className="p-8">
      <AdminPageHeader
        title="Datenlücken"
        description="Wie vollständig sind die kommenden Termine? Eine Kachel wählt die Lücke, darunter stehen die betroffenen Termine – die meistgemerkten und nächsten zuerst."
      >
        <FilterTabs
          active={String(days)}
          items={RANGES.map((r) => ({ ...r, href: `/datenluecken?gap=${gap.key}&days=${r.key}` }))}
        />
      </AdminPageHeader>

      {error && <p className="mt-4 text-sm text-amber-700">Konnte Daten nicht laden: {error.message}</p>}

      {coverage && (
        <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {GAPS.map((g) => (
            <CoverageTile
              key={g.key}
              label={g.label}
              part={coverage[g.key]}
              total={coverage.total}
              hint={`${(coverage.total - coverage[g.key]).toLocaleString("de-DE")} fehlen`}
              href={`/datenluecken?gap=${g.key}&days=${days}`}
              active={g.key === gap.key}
            />
          ))}
        </div>
      )}

      <div className="mt-8">
        <h2 className="text-base font-semibold text-neutral-900">Termine {gap.missing}</h2>
        <p className="text-xs text-neutral-500">Höchstens 150 Einträge, sortiert nach Merkliste und Datum.</p>
      </div>

      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Termin</Th>
              <Th>Datum</Th>
              <Th>Veranstalter</Th>
              <Th>Gemerkt</Th>
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {events.map((event) => (
              <tr key={event.event_id} className="align-top">
                <td className="px-4 py-3">
                  <Link href={`/events/${event.event_id}`} className="font-medium text-neutral-900 hover:underline">
                    {event.title}
                  </Link>
                  {event.venue_name && <p className="text-xs text-neutral-500">{event.venue_name}</p>}
                </td>
                <td className="whitespace-nowrap px-4 py-3">{dayMonth.format(new Date(event.start_datetime))}</td>
                <td className="px-4 py-3 text-neutral-600">{event.organizer_name ?? "–"}</td>
                <td className="px-4 py-3 tabular-nums">{event.saves}</td>
              </tr>
            ))}
            {!error && events.length === 0 && <EmptyRow colSpan={4}>Keine Lücken in diesem Zeitraum.</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>
    </div>
  );
}
