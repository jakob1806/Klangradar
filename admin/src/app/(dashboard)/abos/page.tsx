/* eslint-disable @next/next/no-img-element */
import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import {
  AdminPageHeader, EmptyRow, FilterTabs, StatTile, TableFrame, Th, dayMonthYear, inputClass, secondaryButtonClass, tbodyClass, theadClass,
} from "@/components/admin-kit";
import { mergeSubscription, updateSubscription } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Abo-Verwaltung. Abos
// kommen automatisch aus den Quellen; hier lassen sie sich korrigieren
// (Name, Link, Titelbild), ausblenden und doppelte zusammenführen.

interface Subscription {
  subscription_id: string;
  organizer_name: string;
  code: string;
  name: string;
  season: string;
  url: string | null;
  image_url: string | null;
  hidden: boolean;
  locked: boolean;
  merged_into: string | null;
  upcoming: number;
  total: number;
  members: number;
  next_start: string | null;
  fallback_image_url: string | null;
}

const FILTERS = [
  { key: "all", label: "Alle" },
  { key: "empty", label: "Ohne kommende Termine" },
  { key: "edited", label: "Bearbeitet" },
  { key: "hidden", label: "Ausgeblendet" },
];

export default async function SubscriptionsAdminPage({ searchParams }: { searchParams: Promise<{ q?: string; filter?: string }> }) {
  const { q, filter: rawFilter } = await searchParams;
  const filter = FILTERS.some((f) => f.key === rawFilter) ? rawFilter! : "all";
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_subscriptions", { p_query: q ?? null, p_filter: filter });
  const rows = (data ?? []) as Subscription[];
  const visible = rows.filter((row) => !row.hidden);
  const hrefFor = (key: string) => `/abos?filter=${key}${q ? `&q=${encodeURIComponent(q)}` : ""}`;

  return (
    <div className="p-8">
      <AdminPageHeader
        title="Abos"
        description="Abos und Zyklen der Veranstalter kommen automatisch aus den Quellen. Hier korrigierst du Name, Link und Titelbild, blendest Abos aus oder führst doppelte zusammen. Bearbeitete Abos überschreibt der automatische Abgleich nicht mehr."
      />

      {error && <p className="mt-4 text-sm text-amber-700">Konnte Abos nicht laden: {error.message}</p>}

      <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Abos in der Liste" value={rows.length} />
        <StatTile label="Mit kommenden Terminen" value={visible.filter((row) => row.upcoming > 0).length} />
        <StatTile label="„Ich habe dieses Abo“" value={rows.reduce((sum, row) => sum + row.members, 0)} hint="Summe aller Nutzer:innen" />
        <StatTile label="Bearbeitet" value={rows.filter((row) => row.locked).length} />
      </div>

      <div className="mt-8 flex flex-wrap items-center justify-between gap-3">
        <FilterTabs active={filter} items={FILTERS.map((f) => ({ ...f, href: hrefFor(f.key) }))} />
        <form className="flex gap-2">
          <input type="hidden" name="filter" value={filter} />
          <input name="q" defaultValue={q ?? ""} placeholder="Abo, Kürzel oder Veranstalter" className={`${inputClass} w-64`} />
          <button type="submit" className={secondaryButtonClass}>Suchen</button>
        </form>
      </div>

      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Abo</Th>
              <Th>Saison</Th>
              <Th>Termine</Th>
              <Th>Nächster</Th>
              <Th>Nutzer:innen</Th>
              <Th />
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {rows.map((row) => {
              const image = row.image_url ?? row.fallback_image_url;
              const siblings = rows.filter((other) => other.organizer_name === row.organizer_name && other.subscription_id !== row.subscription_id && !other.merged_into);
              return (
                <tr key={row.subscription_id} className={`align-top ${row.hidden ? "bg-neutral-50/70 text-neutral-500" : ""}`}>
                  <td className="px-4 py-3">
                    <div className="flex items-start gap-3">
                      <div className="size-12 shrink-0 overflow-hidden rounded-lg bg-neutral-100">
                        {image && <img src={image} alt="" className="size-full object-cover object-top" />}
                      </div>
                      <div className="min-w-0">
                        <p className="font-medium text-neutral-900">{row.name}</p>
                        <p className="text-xs text-neutral-500">
                          {row.organizer_name} · {row.code}
                          {row.locked && <span className="ml-2 rounded bg-[#2D2A6E]/10 px-1.5 py-0.5 text-[11px] font-medium text-[#2D2A6E]">bearbeitet</span>}
                          {row.hidden && <span className="ml-2 rounded bg-neutral-200 px-1.5 py-0.5 text-[11px] font-medium text-neutral-600">{row.merged_into ? "zusammengeführt" : "ausgeblendet"}</span>}
                        </p>
                      </div>
                    </div>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">{row.season}</td>
                  <td className="whitespace-nowrap px-4 py-3 tabular-nums">
                    {row.upcoming} <span className="text-neutral-400">/ {row.total}</span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">{row.next_start ? dayMonthYear.format(new Date(row.next_start)) : "–"}</td>
                  <td className="px-4 py-3 tabular-nums">{row.members}</td>
                  <td className="px-4 py-3">
                    {!row.merged_into && (
                      <details className="group">
                        <summary className={`${secondaryButtonClass} cursor-pointer list-none whitespace-nowrap`}>Bearbeiten</summary>
                        <div className="mt-3 flex w-80 flex-col gap-4 rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                          <form action={updateSubscription.bind(null, row.subscription_id)} className="flex flex-col gap-2">
                            <label className="text-xs font-medium text-neutral-600">
                              Name
                              <input name="name" required defaultValue={row.name} className={`${inputClass} mt-1 w-full`} />
                            </label>
                            <label className="text-xs font-medium text-neutral-600">
                              Link zum Abo
                              <input name="url" type="url" defaultValue={row.url ?? ""} className={`${inputClass} mt-1 w-full`} />
                            </label>
                            <label className="text-xs font-medium text-neutral-600">
                              Titelbild (URL, sonst Bild des ersten Termins)
                              <input name="image_url" type="url" defaultValue={row.image_url ?? ""} className={`${inputClass} mt-1 w-full`} />
                            </label>
                            <label className="flex items-center gap-2 text-sm text-neutral-700">
                              <input type="checkbox" name="hidden" defaultChecked={row.hidden} className="size-4 accent-[#2D2A6E]" />
                              In der App ausblenden
                            </label>
                            <div>
                              <SubmitButton>Speichern</SubmitButton>
                            </div>
                          </form>
                          {siblings.length > 0 && (
                            <form action={mergeSubscription.bind(null, row.subscription_id)} className="flex flex-col gap-2 border-t border-black/[0.06] pt-4">
                              <label className="text-xs font-medium text-neutral-600">
                                Zusammenführen in …
                                <select name="target" required defaultValue="" className={`${inputClass} mt-1 w-full`}>
                                  <option value="" disabled>Ziel-Abo wählen</option>
                                  {siblings.map((other) => (
                                    <option key={other.subscription_id} value={other.subscription_id}>
                                      {other.name} ({other.season}, {other.code})
                                    </option>
                                  ))}
                                </select>
                              </label>
                              <p className="text-xs text-neutral-500">Termine und „Ich habe dieses Abo“ wandern zum Ziel, dieses Abo wird ausgeblendet.</p>
                              <div>
                                <SubmitButton pendingLabel="Führe zusammen …">Zusammenführen</SubmitButton>
                              </div>
                            </form>
                          )}
                        </div>
                      </details>
                    )}
                  </td>
                </tr>
              );
            })}
            {!error && rows.length === 0 && <EmptyRow colSpan={6}>Keine Abos gefunden.</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>
    </div>
  );
}
