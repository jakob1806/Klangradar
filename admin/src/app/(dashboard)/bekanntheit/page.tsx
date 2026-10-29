/* eslint-disable @next/next/no-img-element */
import { createClient } from "@/lib/supabase/server";
import {
  AdminPageHeader, EmptyRow, FilterTabs, TableFrame, Th, inputClass, secondaryButtonClass, tbodyClass, theadClass,
} from "@/components/admin-kit";
import { setProminenceBoost } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Bekanntheits-Score
// pflegen. Die Folgen-Vorschläge im Onboarding und unter Profil → Interessen
// sortieren nach Wikipedia-Aufrufen, Auftritten, Followern und Foto; hier
// lässt sich der Wert je Eintrag hoch- oder abstufen. Änderungen wirken
// sofort, die Vorschläge werden bei jedem Aufruf neu berechnet.

interface Row {
  entity_id: string;
  label: string;
  photo_url: string | null;
  wiki_views: number;
  score: number;
  boost: number;
  boost_note: string | null;
  upcoming: number;
  followers: number;
}

const KINDS = [
  { key: "person", label: "Personen" },
  { key: "ensemble", label: "Ensembles" },
  { key: "venue", label: "Orte" },
];

const STEPS = [
  { value: 2, label: "+2" },
  { value: 1, label: "+1" },
  { value: -1, label: "−1" },
  { value: -2, label: "−2" },
];

const compact = new Intl.NumberFormat("de-DE", { notation: "compact", maximumFractionDigits: 1 });

function BoostBadge({ boost }: { boost: number }) {
  if (boost === 0) return <span className="text-neutral-400">0</span>;
  if (boost <= -10) return <span className="rounded bg-neutral-200 px-1.5 py-0.5 text-[11px] font-medium text-neutral-700">ausgeblendet</span>;
  return (
    <span className={`rounded px-1.5 py-0.5 text-[11px] font-semibold tabular-nums ${boost > 0 ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-800"}`}>
      {boost > 0 ? `+${boost}` : `−${Math.abs(boost)}`}
    </span>
  );
}

export default async function ProminencePage({ searchParams }: { searchParams: Promise<{ kind?: string; q?: string }> }) {
  const params = await searchParams;
  const kind = KINDS.some((k) => k.key === params.kind) ? params.kind! : "person";
  const q = params.q ?? "";
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_prominence_list", { p_kind: kind, p_query: q || null, p_limit: 150 });
  const rows = (data ?? []) as Row[];

  return (
    <div className="p-8">
      <AdminPageHeader
        title="Bekanntheit"
        description="Reihenfolge der Folgen-Vorschläge im Onboarding und unter Profil → Interessen. Grundlage sind Wikipedia-Aufrufe (Score bis 6), Auftritte, Follower und Foto. Mit den Stufen schiebst du Einträge nach oben oder unten; „Ausblenden“ nimmt sie aus den Vorschlägen (die Suche findet sie weiterhin)."
      />

      <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
        <FilterTabs active={kind} items={KINDS.map((k) => ({ ...k, href: `/bekanntheit?kind=${k.key}${q ? `&q=${encodeURIComponent(q)}` : ""}` }))} />
        <form className="flex gap-2">
          <input type="hidden" name="kind" value={kind} />
          <input name="q" defaultValue={q} placeholder="Name suchen" className={`${inputClass} w-64`} />
          <button type="submit" className={secondaryButtonClass}>Suchen</button>
        </form>
      </div>

      {error && <p className="mt-4 text-sm text-amber-700">Konnte Daten nicht laden: {error.message}</p>}

      <TableFrame>
        <table className="w-full text-sm">
          <thead className={theadClass}>
            <tr>
              <Th>Name</Th>
              <Th>Wikipedia</Th>
              <Th>Auftritte</Th>
              <Th>Follower</Th>
              <Th>Anpassung</Th>
              <Th />
            </tr>
          </thead>
          <tbody className={tbodyClass}>
            {rows.map((row) => (
              <tr key={row.entity_id} className="align-middle">
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    <div className="size-9 shrink-0 overflow-hidden rounded-full bg-neutral-100">
                      {row.photo_url && <img src={row.photo_url} alt="" className="size-full object-cover object-top" />}
                    </div>
                    <div className="min-w-0">
                      <p className="font-medium text-neutral-900">{row.label}</p>
                      {row.boost_note && <p className="truncate text-xs text-neutral-500">{row.boost_note}</p>}
                    </div>
                  </div>
                </td>
                <td className="whitespace-nowrap px-4 py-3 tabular-nums">
                  {row.wiki_views > 0 ? (
                    <>
                      {row.score.toFixed(1)} <span className="text-xs text-neutral-500">({compact.format(row.wiki_views)} Aufrufe)</span>
                    </>
                  ) : (
                    <span className="text-neutral-400">kein Artikel</span>
                  )}
                </td>
                <td className="px-4 py-3 tabular-nums">{row.upcoming}</td>
                <td className="px-4 py-3 tabular-nums">{row.followers}</td>
                <td className="px-4 py-3">
                  <BoostBadge boost={row.boost} />
                </td>
                <td className="px-4 py-3">
                  <div className="flex flex-wrap justify-end gap-1.5">
                    {STEPS.map((step) => {
                      const next = Math.max(-10, Math.min(10, (row.boost <= -10 ? 0 : row.boost) + step.value));
                      return (
                        <form key={step.label} action={setProminenceBoost.bind(null, kind, row.entity_id, next)}>
                          <input type="hidden" name="note" value={row.boost_note ?? ""} />
                          <button type="submit" className="h-8 min-w-9 rounded-lg border border-black/10 px-2 text-sm font-medium tabular-nums text-neutral-700 hover:bg-neutral-50">
                            {step.label}
                          </button>
                        </form>
                      );
                    })}
                    {row.boost > -10 && (
                      <form action={setProminenceBoost.bind(null, kind, row.entity_id, -10)}>
                        <input type="hidden" name="note" value={row.boost_note ?? ""} />
                        <button type="submit" className="h-8 rounded-lg border border-black/10 px-2.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50">Ausblenden</button>
                      </form>
                    )}
                    {row.boost !== 0 && (
                      <form action={setProminenceBoost.bind(null, kind, row.entity_id, 0)}>
                        <button type="submit" className="h-8 rounded-lg px-2.5 text-sm font-medium text-[#2D2A6E] hover:underline">Zurücksetzen</button>
                      </form>
                    )}
                  </div>
                </td>
              </tr>
            ))}
            {!error && rows.length === 0 && <EmptyRow colSpan={6}>Keine Einträge gefunden.</EmptyRow>}
          </tbody>
        </table>
      </TableFrame>
    </div>
  );
}
