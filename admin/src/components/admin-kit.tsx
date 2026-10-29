import Link from "next/link";

// Erstellt von Claude Code (29.10.2026): gemeinsame Bausteine der neuen
// Redaktionsseiten (Abos, Datenlücken, Bekanntheit, Moderation, Plus) im
// Stil der Seite "Werkeinführungen" — Kopf, Kennzahl-Kacheln, Tabellenrahmen.

export const inputClass =
  "rounded-lg border border-black/10 bg-white px-3 py-2 text-sm outline-none focus:border-[#2D2A6E]";
export const secondaryButtonClass =
  "rounded-lg border border-black/10 bg-white px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50";

export function AdminPageHeader({ title, description, children }: { title: string; description?: React.ReactNode; children?: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
        {description && <p className="mt-1 max-w-2xl text-sm text-neutral-500">{description}</p>}
      </div>
      {children}
    </div>
  );
}

export function percent(part: number, total: number) {
  return total > 0 ? Math.round((part / total) * 100) : 0;
}

export function CoverageTile({ label, part, total, hint, href, active }: { label: string; part: number; total: number; hint?: string; href?: string; active?: boolean }) {
  const value = percent(part, total);
  const body = (
    <>
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums text-neutral-900">{value} %</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {part.toLocaleString("de-DE")} von {total.toLocaleString("de-DE")}
        {hint ? ` · ${hint}` : ""}
      </p>
      <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-black/[0.06]">
        <div className="h-full rounded-full bg-[#2D2A6E]" style={{ width: `${value}%` }} />
      </div>
    </>
  );
  const className = `block rounded-xl border bg-white p-4 shadow-sm ${active ? "border-[#2D2A6E] ring-1 ring-[#2D2A6E]" : "border-black/[0.06]"}`;
  return href ? (
    <Link href={href} className={`${className} transition-colors hover:border-[#2D2A6E]/40`} aria-current={active ? "true" : undefined}>
      {body}
    </Link>
  ) : (
    <div className={className}>{body}</div>
  );
}

export function StatTile({ label, value, hint }: { label: string; value: number | string; hint?: string }) {
  return (
    <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums text-neutral-900">
        {typeof value === "number" ? value.toLocaleString("de-DE") : value}
      </p>
      {hint && <p className="mt-0.5 text-xs text-neutral-500">{hint}</p>}
    </div>
  );
}

export function TableFrame({ children }: { children: React.ReactNode }) {
  return <div className="mt-3 overflow-x-auto rounded-xl border border-black/[0.06] bg-white shadow-sm">{children}</div>;
}

export function Th({ children, className = "" }: { children?: React.ReactNode; className?: string }) {
  return <th className={`px-4 py-2.5 font-medium ${className}`}>{children}</th>;
}

export const theadClass = "bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500";
export const tbodyClass = "divide-y divide-black/[0.05]";

export function EmptyRow({ colSpan, children }: { colSpan: number; children: React.ReactNode }) {
  return (
    <tr>
      <td colSpan={colSpan} className="px-4 py-8 text-center text-sm text-neutral-500">
        {children}
      </td>
    </tr>
  );
}

export function FilterTabs({ items, active }: { items: { key: string; label: string; href: string }[]; active: string }) {
  return (
    <div className="flex flex-wrap gap-1 rounded-lg bg-black/[0.04] p-1">
      {items.map((item) => (
        <Link
          key={item.key}
          href={item.href}
          aria-current={item.key === active ? "page" : undefined}
          className={`rounded-md px-3 py-1.5 text-sm font-medium ${item.key === active ? "bg-white text-neutral-900 shadow-sm" : "text-neutral-600 hover:text-neutral-900"}`}
        >
          {item.label}
        </Link>
      ))}
    </div>
  );
}

export const dayMonth = new Intl.DateTimeFormat("de-DE", { day: "numeric", month: "short", timeZone: "Europe/Berlin" });
export const dayMonthYear = new Intl.DateTimeFormat("de-DE", { day: "numeric", month: "short", year: "numeric", timeZone: "Europe/Berlin" });
