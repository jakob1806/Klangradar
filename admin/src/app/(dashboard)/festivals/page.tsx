import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { TableSearchFilter } from "@/components/table-search-filter";

export const dynamic = "force-dynamic";

interface FestivalRow {
  id: string;
  name: string;
  recurring: boolean;
  start_date: string | null;
  end_date: string | null;
  organizer: { name: string } | null;
}

function formatDateRange(start: string | null, end: string | null): string {
  if (!start || !end) return "—";
  const fmt = (d: string) => new Date(d).toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit", year: "numeric" });
  return `${fmt(start)} – ${fmt(end)}`;
}

export default async function FestivalsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("festivals")
    .select("id, name, recurring, start_date, end_date, organizer:organizers(name)")
    .order("name")
    .returns<FestivalRow[]>();

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Festivals</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Wiederkehrende und einmalige Festivals, die Events gruppieren (z. B. Münchner Opernfestspiele).
          </p>
        </div>
        <Link
          href="/festivals/new"
          className="rounded-lg bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
        >
          Neu anlegen
        </Link>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Festivals nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6">
          <TableSearchFilter containerId="festivals-table" placeholder="Name durchsuchen…" />
          <div id="festivals-table" className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
          <table className="w-full text-sm">
            <thead className="border-b border-black/[0.06] text-left">
              <tr>
                <th className="type-label px-4 py-3">Name</th>
                <th className="type-label px-4 py-3">Veranstalter</th>
                <th className="type-label px-4 py-3">Zeitraum</th>
                <th className="type-label px-4 py-3">Wiederkehrend</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-200">
              {data?.length ? (
                data.map((f) => (
                  <tr key={f.id} data-search={f.name.toLowerCase()} className="hover:bg-neutral-50">
                    <td className="px-4 py-3 font-medium text-neutral-900">
                      <Link href={`/festivals/${f.id}`} className="hover:underline">
                        {f.name}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-neutral-600">{f.organizer?.name ?? "—"}</td>
                    <td className="px-4 py-3 text-neutral-600">{formatDateRange(f.start_date, f.end_date)}</td>
                    <td className="px-4 py-3 text-neutral-600">{f.recurring ? "Ja" : "Nein"}</td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={4} className="px-4 py-10 text-center text-neutral-400">
                    Keine Festivals angelegt.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          </div>
        </div>
      )}
    </div>
  );
}
