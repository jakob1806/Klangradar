import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Überblick: welche Spielstätten (mit kommenden Terminen) haben einen Saalplan. */
export default async function SeatingPlansPage() {
  const supabase = await createClient();
  const { data: venues } = await supabase
    .from("venues")
    .select("id, name, address_city, seating_plan_url, events!inner(id)")
    .gte("events.start_datetime", new Date().toISOString())
    .order("name")
    .returns<Array<{ id: string; name: string; address_city: string | null; seating_plan_url: string | null; events: { id: string }[] }>>();
  const rows = (venues ?? []).map((v) => ({ ...v, upcoming: v.events.length }))
    .sort((a, b) => Number(!!a.seating_plan_url) - Number(!!b.seating_plan_url) || b.upcoming - a.upcoming);
  const withPlan = rows.filter((r) => r.seating_plan_url).length;

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Saalpläne</h1>
      <p className="mt-1 text-sm text-neutral-500">
        {withPlan} von {rows.length} Spielstätten mit kommenden Terminen haben einen Saalplan. Fehlende zuerst, nach Anzahl der Termine.
      </p>
      <table className="mt-6 w-full text-sm">
        <thead className="text-left text-neutral-500">
          <tr><th className="py-2">Spielstätte</th><th>Ort</th><th>Kommende Termine</th><th>Saalplan</th><th /></tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id} className="border-t border-neutral-100">
              <td className="py-2 font-medium">{r.name}</td>
              <td className="text-neutral-600">{r.address_city ?? "—"}</td>
              <td className="tabular-nums text-neutral-600">{r.upcoming}</td>
              <td>{r.seating_plan_url
                ? <a href={r.seating_plan_url} target="_blank" rel="noreferrer" className="text-blue-700 underline">vorhanden</a>
                : <span className="text-amber-700">fehlt</span>}</td>
              <td className="text-right"><Link href={`/venues/${r.id}`} className="text-neutral-700 underline">Bearbeiten</Link></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
