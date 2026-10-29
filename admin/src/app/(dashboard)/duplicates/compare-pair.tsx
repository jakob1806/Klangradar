/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { DuplicateSelectCheckbox } from "@/components/duplicate-bulk-selection";
import { InstantButton } from "@/components/instant-button";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): kompakter Vergleich
// eines Duplikat-Paars für Personen und Ensembles — Konfidenz und Signale
// oben, beide Datensätze nebeneinander mit Foto, Lebensdaten/Gründung,
// Wikidata und Kennzahlen, damit sich echte und falsche Treffer auf einen
// Blick unterscheiden lassen.

export type PairSide = {
  id: string;
  name: string;
  /** undefined = kein Bildfeld (Werke) */
  photo_url?: string | null;
  wikidata_id: string | null;
  showWikidata?: boolean;
  facts: string[];
  stats: { label: string; value: number }[];
  description: string | null;
  href: string;
};

export type Signal = { label: string; tone: "good" | "bad" | "neutral" };

function confidenceStyle(confidence: number) {
  if (confidence >= 90) return { label: "sehr wahrscheinlich", className: "bg-emerald-50 text-emerald-800 ring-emerald-200" };
  if (confidence >= 65) return { label: "wahrscheinlich", className: "bg-sky-50 text-sky-800 ring-sky-200" };
  return { label: "unsicher", className: "bg-amber-50 text-amber-800 ring-amber-200" };
}

const toneClass: Record<Signal["tone"], string> = {
  good: "bg-emerald-50 text-emerald-800",
  bad: "bg-red-50 text-red-700",
  neutral: "bg-neutral-100 text-neutral-600",
};

function Side({ side, keepAction, shortcut }: { side: PairSide; keepAction: () => Promise<void>; shortcut: "a" | "b" }) {
  return (
    <div className="flex min-w-0 flex-1 gap-3 rounded-lg bg-neutral-50 p-3">
      {side.photo_url !== undefined ? (
        <div className="size-14 shrink-0 overflow-hidden rounded-lg bg-neutral-200">
          {side.photo_url && <img src={side.photo_url} alt="" className="size-full object-cover object-top" />}
        </div>
      ) : null}
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <Link href={side.href} className="truncate text-sm font-semibold text-neutral-900 hover:underline" target="_blank">
          {side.name}
        </Link>
        <p className="text-xs text-neutral-500">
          {[...side.facts, side.showWikidata === false ? null : side.wikidata_id ? `Wikidata ${side.wikidata_id}` : "ohne Wikidata"].filter(Boolean).join(" · ")}
        </p>
        <p className="text-xs tabular-nums text-neutral-600">{side.stats.map((stat) => `${stat.value} ${stat.label}`).join(" · ")}</p>
        {side.description && <p className="line-clamp-2 text-xs text-neutral-500">{side.description}</p>}
        <span data-shortcut={shortcut} className="mt-1 self-start">
          <InstantButton
            action={keepAction}
            pendingLabel="Führe zusammen…"
            className="rounded-md bg-white px-2.5 py-1 text-xs font-medium text-[#2D2A6E] ring-1 ring-black/10 hover:bg-[#2D2A6E] hover:text-white disabled:opacity-50"
          >
            Diese behalten <span className="ml-1 font-mono text-[10px] opacity-60">{shortcut.toUpperCase()}</span>
          </InstantButton>
        </span>
      </div>
    </div>
  );
}

export function ComparePair({
  id,
  confidence,
  signals,
  note,
  a,
  b,
  keepA,
  keepB,
  distinct,
}: {
  id: string;
  confidence: number;
  signals: Signal[];
  note?: string | null;
  a: PairSide;
  b: PairSide;
  keepA: () => Promise<void>;
  keepB: () => Promise<void>;
  distinct: () => Promise<void>;
}) {
  const style = confidenceStyle(confidence);
  return (
    <div data-pair className="rounded-xl border border-black/[0.06] bg-white p-3 shadow-sm transition-shadow data-[active=true]:border-[#2D2A6E]/40 data-[active=true]:ring-2 data-[active=true]:ring-[#2D2A6E]/30">
      <div className="flex flex-wrap items-center gap-1.5">
        <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ring-1 ${style.className}`}>
          {Math.min(confidence, 99)} % · {style.label}
        </span>
        {signals.map((signal) => (
          <span key={signal.label} className={`rounded-full px-2 py-0.5 text-xs ${toneClass[signal.tone]}`}>
            {signal.label}
          </span>
        ))}
        <span className="ml-auto">
          <DuplicateSelectCheckbox id={id} label={`${a.name} / ${b.name}`} />
        </span>
      </div>
      {note && <p className="mt-2 text-xs text-neutral-500">{note}</p>}
      <div className="mt-2 flex flex-col gap-2 md:flex-row">
        <Side side={a} keepAction={keepA} shortcut="a" />
        <Side side={b} keepAction={keepB} shortcut="b" />
      </div>
      <div className="mt-2 flex items-center justify-between gap-3">
        <p className="text-[11px] text-neutral-400">„Diese behalten“ löscht den anderen Eintrag; Verknüpfungen und Name (als Alias) wandern mit.</p>
        <span data-shortcut="v" className="shrink-0">
          <InstantButton action={distinct} pendingLabel="Speichere…" className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50">
            Verschieden <span className="ml-1 font-mono text-[10px] opacity-60">V</span>
          </InstantButton>
        </span>
      </div>
    </div>
  );
}
