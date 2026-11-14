"use client";

import Link from "next/link";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";

import { ALL_NAV_LINKS, NAV_GROUPS, findNavArea } from "@/components/nav-groups";
import { CountBadge, areaCount, useNavCounts, usePins } from "@/components/nav-extras";
import { readRecent, type RecentEntry } from "@/components/recent-tracker";
import { CommandPaletteButton } from "@/components/command-palette";

export { NAV_GROUPS };

const COLLAPSED_STORAGE_KEY = "klangradar.sidebar.collapsed";
const COLLAPSED_EVENT = "klangradar-sidebar-collapsed";

function subscribeCollapsed(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(COLLAPSED_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(COLLAPSED_EVENT, onChange);
  };
}

function readCollapsed() {
  try {
    return window.localStorage.getItem(COLLAPSED_STORAGE_KEY) ?? "[]";
  } catch {
    return "[]";
  }
}

// Ermittelt den am genauesten passenden Nav-Eintrag statt jeden Präfix-Treffer
// separat aktiv zu markieren — sonst blieb z.B. "Duplikate-Review" (/duplicates)
// dauerhaft blau hervorgehoben, auch auf /duplicates/persons oder
// /duplicates/works, weil deren Pfad ebenfalls mit "/duplicates" beginnt und
// jeder Eintrag unabhängig voneinander geprüft wurde (Nutzerfeedback: "der
// blaue hintergrund hängt immer bei duplikate review fest, auch wenn man zu
// einer anderen kategorie wechselt").
export function bestMatchingHref(pathname: string, hrefs: string[]): string | null {
  let best: string | null = null;
  for (const href of hrefs) {
    if (pathname === href || pathname.startsWith(`${href}/`)) {
      if (!best || href.length > best.length) best = href;
    }
  }
  return best;
}

export function Sidebar({ userEmail }: { userEmail?: string }) {
  const pathname = usePathname();
  const [query, setQuery] = useState("");
  const counts = useNavCounts();
  const [pins, togglePin] = usePins();
  const [recent, setRecent] = useState<RecentEntry[]>([]);
  useEffect(() => {
    // Nach dem Seitenwechsel neu lesen (RecentTracker schreibt im Browser).
    const id = window.setTimeout(() => setRecent(readRecent().slice(0, 3)), 300);
    return () => window.clearTimeout(id);
  }, [pathname]);
  // Zustand pro Browser über useSyncExternalStore (Server rendert alles offen,
  // danach übernimmt der Browser den gespeicherten Stand ohne Hydration-Fehler).
  const collapsedRaw = useSyncExternalStore(subscribeCollapsed, readCollapsed, () => "[]");
  const collapsed = useMemo(() => {
    try {
      return new Set(JSON.parse(collapsedRaw) as string[]);
    } catch {
      return new Set<string>();
    }
  }, [collapsedRaw]);

  const toggleGroup = (label: string) => {
    const next = new Set(collapsed);
    if (next.has(label)) next.delete(label);
    else next.add(label);
    try {
      window.localStorage.setItem(COLLAPSED_STORAGE_KEY, JSON.stringify([...next]));
      window.dispatchEvent(new Event(COLLAPSED_EVENT));
    } catch {
      // Ohne localStorage (privates Fenster) bleibt alles aufgeklappt.
    }
  };

  // Aktiv ist der Bereich, auch wenn man auf einem seiner Reiter steht.
  const navMatch = findNavArea(pathname);
  const activeHref = navMatch?.area.href ?? null;
  const currentHref = navMatch?.href ?? null;

  const normalizedQuery = query.trim().toLowerCase();
  const groups = NAV_GROUPS.map((group) => ({
    ...group,
    items: normalizedQuery
      ? group.items.filter((item) =>
          [item, ...(item.tabs ?? [])].some((link) => link.label.toLowerCase().includes(normalizedQuery)))
      : group.items,
  })).filter((group) => group.items.length > 0);

  return (
    <aside className="dashboard-sidebar">
      <Link href="/admin" className="dashboard-brand" aria-label="Startseite">
        <span className="dashboard-brand-mark" aria-hidden="true">
          <Image src="/app-logo.svg" alt="" width={40} height={40} priority />
        </span>
        <span className="min-w-0">
          <span className="block truncate text-[14px] font-semibold tracking-tight text-[#111111]">Klangradar</span>
          <span className="block truncate text-[12px] text-[#6B6B6B]">Redaktion</span>
        </span>
      </Link>
      <CommandPaletteButton />
      <label className="block px-0.5">
        <span className="sr-only">Navigation durchsuchen</span>
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Springe zu …"
          className="dashboard-nav-search"
        />
      </label>
      <nav className="dashboard-sidebar-nav" aria-label="Redaktion">
        {!normalizedQuery && pins.length > 0 && (
          <div className="dashboard-nav-group">
            <div className="dashboard-nav-group-toggle">Angeheftet</div>
            <div className="flex flex-col gap-px">
              {pins.map((href) => {
                const link = ALL_NAV_LINKS.find((l) => l.href === href);
                if (!link) return null;
                return (
                  <Link key={href} href={link.href} aria-current={currentHref === link.href ? "page" : undefined}
                    className={`dashboard-nav-item ${currentHref === link.href ? "dashboard-nav-item-active" : ""}`}>
                    <span className="truncate">{link.label === link.area ? link.label : `${link.area} · ${link.label}`}</span>
                    <CountBadge value={counts[link.href] ?? 0} />
                  </Link>
                );
              })}
            </div>
          </div>
        )}
        {groups.map((group) => {
          // Beim Suchen und für die Gruppe der aktuellen Seite immer offen.
          const containsActive = group.items.some((item) => item.href === activeHref);
          const open = Boolean(normalizedQuery) || containsActive || !collapsed.has(group.label);
          const listId = `nav-group-${group.label.replace(/[^a-z0-9]+/gi, "-").toLowerCase()}`;
          return (
            <div key={group.label} className="dashboard-nav-group">
              <button
                type="button"
                className="dashboard-nav-group-toggle"
                aria-expanded={open}
                aria-controls={listId}
                onClick={() => toggleGroup(group.label)}
              >
                {group.label}
                <svg aria-hidden="true" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 4.5l3 3 3-3" />
                </svg>
              </button>
              <div id={listId} className="dashboard-nav-collapse" data-open={open}>
                <div className="flex flex-col gap-px">
                  {group.items.map((item) => {
                    const active = item.href === activeHref;
                    // Unterseiten des aktiven Bereichs (oder Suchtreffer)
                    // auch in der Leiste zeigen, nicht nur als Reiter.
                    const subLinks = (item.tabs ?? []).filter(
                      (tab) => tab.href !== item.href && (active || (normalizedQuery && tab.label.toLowerCase().includes(normalizedQuery))),
                    );
                    return (
                      <div key={item.href} className="flex flex-col gap-px">
                        <div className="group relative flex items-center">
                          <Link
                            href={item.href}
                            tabIndex={open ? undefined : -1}
                            aria-current={active && currentHref === item.href ? "page" : undefined}
                            className={`dashboard-nav-item flex-1 pr-7 ${active ? "dashboard-nav-item-active" : ""}`}
                          >
                            <span className="truncate">{item.label}</span>
                            <CountBadge value={areaCount(item, counts)} />
                          </Link>
                          <button
                            type="button"
                            tabIndex={open ? undefined : -1}
                            onClick={() => togglePin(item.href)}
                            aria-label={pins.includes(item.href) ? `${item.label} lösen` : `${item.label} anheften`}
                            title={pins.includes(item.href) ? "Lösen" : "Anheften"}
                            className={`absolute right-1 rounded px-1 text-[12px] ${pins.includes(item.href) ? "text-[#2D2A6E]" : "text-[#B5B5B5] opacity-0 group-hover:opacity-100 focus:opacity-100"}`}
                          >
                            {pins.includes(item.href) ? "★" : "☆"}
                          </button>
                        </div>
                        {subLinks.length > 0 && (
                          <div className="ml-3 flex flex-col gap-px border-l border-[#EAEAEA] pl-2">
                            {subLinks.map((tab) => (
                              <Link
                                key={tab.href}
                                href={tab.href}
                                tabIndex={open ? undefined : -1}
                                aria-current={currentHref === tab.href ? "page" : undefined}
                                className={`dashboard-nav-item text-[13px] ${currentHref === tab.href ? "font-medium text-[#111111]" : ""}`}
                              >
                                <span className="truncate">{tab.label}</span>
                                <CountBadge value={counts[tab.href] ?? 0} />
                              </Link>
                            ))}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          );
        })}
        {groups.length === 0 && <p className="px-3 py-2 text-[13px] text-[#6B6B6B]">Kein Bereich gefunden.</p>}
      </nav>
      {recent.length > 0 && !normalizedQuery && (
        <div className="border-t border-[#EAEAEA] pt-3">
          <p className="px-3 pb-1 text-[11px] font-medium uppercase tracking-wide text-[#6B6B6B]">Zuletzt geöffnet</p>
          {recent.map((entry) => (
            <Link key={entry.href} href={entry.href} className="dashboard-nav-item text-[13px]">
              <span className="truncate">{entry.title}</span>
              <span className="ml-auto shrink-0 text-[11px] text-[#9A9A9A]">{entry.kind}</span>
            </Link>
          ))}
        </div>
      )}
      <p className="px-3 text-[11px] text-[#9A9A9A]">Tastenkürzel: <kbd>g</kbd> + Buchstabe · <kbd>?</kbd> Hilfe</p>
      <div className="border-t border-[#EAEAEA] pt-3">
        <Link href="/veranstalter" className="dashboard-nav-item">
          Zum Veranstalterportal
          <span aria-hidden="true">→</span>
        </Link>
      </div>
      {userEmail && (
        <div className="dashboard-account" title={userEmail}>
          <span className="dashboard-account-avatar" aria-hidden="true">{userEmail.slice(0, 1).toUpperCase()}</span>
          <span className="min-w-0">
            <span className="block text-[11px] text-[#6B6B6B]">Angemeldet</span>
            <span className="block truncate text-[12px] text-[#111111]">{userEmail}</span>
          </span>
        </div>
      )}
    </aside>
  );
}
