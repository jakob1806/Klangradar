import Link from "next/link";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): gemeinsamer Baukasten
// für die Stammdaten-Listen (Personen, Ensembles, Venues). Suche, Filter,
// Sortierung und Seiten laufen über die URL und serverseitig — vorher lud
// jede Liste den kompletten Bestand (Personen: > 1.700 Zeilen) und filterte
// nur im Browser nach dem Namen.

export type ListParams = { q: string; filter: string; sort: string; page: number };
export type ListOption = { key: string; label: string };

export const LIST_PAGE_SIZE = 100;

export function readListParams(
  raw: Record<string, string | string[] | undefined>,
  filters: ListOption[],
  sorts: ListOption[],
): ListParams {
  const value = (key: string) => (typeof raw[key] === "string" ? (raw[key] as string) : "");
  const filter = filters.some((option) => option.key === value("filter")) ? value("filter") : filters[0].key;
  const sort = sorts.some((option) => option.key === value("sort")) ? value("sort") : sorts[0].key;
  const page = Math.max(1, Number.parseInt(value("page"), 10) || 1);
  return { q: value("q").trim(), filter, sort, page };
}

export function listRange(params: ListParams): [number, number] {
  const from = (params.page - 1) * LIST_PAGE_SIZE;
  return [from, from + LIST_PAGE_SIZE - 1];
}

/** Escaped Eingaben für PostgREST-ilike (%, _ und Komma). */
export function ilikePattern(q: string) {
  return `%${q.replace(/[%_,()]/g, " ").trim()}%`;
}

function hrefWith(basePath: string, params: ListParams, extra: Record<string, string>, overrides: Partial<ListParams>) {
  const merged = { ...params, ...overrides };
  const search = new URLSearchParams(extra);
  if (merged.q) search.set("q", merged.q);
  if (merged.filter) search.set("filter", merged.filter);
  if (merged.sort) search.set("sort", merged.sort);
  if (merged.page > 1) search.set("page", String(merged.page));
  const query = search.toString();
  return query ? `${basePath}?${query}` : basePath;
}

export function ListToolbar({
  basePath,
  params,
  filters,
  sorts,
  total,
  searchPlaceholder,
  extra = {},
  children,
}: {
  basePath: string;
  params: ListParams;
  filters: ListOption[];
  sorts: ListOption[];
  total: number;
  searchPlaceholder: string;
  extra?: Record<string, string>;
  children?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <form className="flex min-w-0 flex-1 items-center gap-2" action={basePath}>
          {Object.entries(extra).map(([key, value]) => (
            <input key={key} type="hidden" name={key} value={value} />
          ))}
          <input type="hidden" name="filter" value={params.filter} />
          <input
            type="search"
            name="q"
            defaultValue={params.q}
            placeholder={searchPlaceholder}
            className="h-9 w-full max-w-sm rounded-lg border border-black/10 bg-white px-3 text-sm outline-none focus:border-[#2D2A6E]"
          />
          <select
            name="sort"
            defaultValue={params.sort}
            aria-label="Sortierung"
            className="h-9 rounded-lg border border-black/10 bg-white px-2 text-sm text-neutral-700 outline-none focus:border-[#2D2A6E]"
          >
            {sorts.map((option) => (
              <option key={option.key} value={option.key}>
                {option.label}
              </option>
            ))}
          </select>
          <button type="submit" className="h-9 rounded-lg border border-black/10 bg-white px-3 text-sm font-medium text-neutral-700 hover:bg-neutral-50">
            Anwenden
          </button>
        </form>
        {children}
      </div>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap gap-1 rounded-lg bg-black/[0.04] p-1">
          {filters.map((option) => {
            const active = option.key === params.filter;
            return (
              <Link
                key={option.key}
                href={hrefWith(basePath, params, extra, { filter: option.key, page: 1 })}
                aria-current={active ? "page" : undefined}
                className={`rounded-md px-3 py-1 text-[13px] font-medium ${active ? "bg-white text-neutral-900 shadow-sm" : "text-neutral-600 hover:text-neutral-900"}`}
              >
                {option.label}
              </Link>
            );
          })}
        </div>
        <span className="text-xs tabular-nums text-neutral-500">
          {total.toLocaleString("de-DE")} {total === 1 ? "Eintrag" : "Einträge"}
          {params.q ? ` für „${params.q}“` : ""}
        </span>
      </div>
    </div>
  );
}

export function ListPagination({
  basePath,
  params,
  total,
  extra = {},
}: {
  basePath: string;
  params: ListParams;
  total: number;
  extra?: Record<string, string>;
}) {
  const pages = Math.max(1, Math.ceil(total / LIST_PAGE_SIZE));
  if (pages <= 1) return null;
  const linkClass = "rounded-lg border border-black/10 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50";
  return (
    <nav aria-label="Seiten" className="mt-4 flex items-center justify-center gap-3">
      {params.page > 1 ? (
        <Link href={hrefWith(basePath, params, extra, { page: params.page - 1 })} className={linkClass}>
          ← Zurück
        </Link>
      ) : (
        <span className={`${linkClass} opacity-40`}>← Zurück</span>
      )}
      <span className="text-sm tabular-nums text-neutral-600">
        Seite {params.page} von {pages}
      </span>
      {params.page < pages ? (
        <Link href={hrefWith(basePath, params, extra, { page: params.page + 1 })} className={linkClass}>
          Weiter →
        </Link>
      ) : (
        <span className={`${linkClass} opacity-40`}>Weiter →</span>
      )}
    </nav>
  );
}

export function VerifiedBadge({ verified }: { verified: boolean }) {
  return (
    <span
      className={`inline-flex rounded-full px-2 py-0.5 text-[11px] font-medium ${verified ? "bg-emerald-50 text-emerald-700" : "bg-neutral-100 text-neutral-500"}`}
    >
      {verified ? "Geprüft" : "Ungeprüft"}
    </span>
  );
}

export const listTableClass = "w-full text-sm";
export const listTheadClass = "border-b border-black/[0.06] bg-neutral-50/70 text-left";
export const listThClass = "px-4 py-2.5 text-xs font-medium uppercase tracking-wide text-neutral-500";
export const listRowClass = "group hover:bg-neutral-50";
