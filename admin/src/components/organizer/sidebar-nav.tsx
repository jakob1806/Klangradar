"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  CalendarDays,
  Users,
  Megaphone,
  BarChart3,
  Plus,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";

import {
  ORGANIZER_NAV_GROUPS,
  ORGANIZER_TOP_LINKS,
  type OrganizerNavGroup,
  type OrganizerNavItem,
} from "@/components/organizer/nav-links";
import { CommandPaletteButton } from "@/components/command-palette";

export type NavItem = OrganizerNavItem;
export type NavGroup = OrganizerNavGroup & { icon: LucideIcon };

// Vier Hauptpunkte (Umbau 30.10.2026); Struktur in nav-links.ts.
const ICONS: Record<string, LucideIcon> = {
  programm: CalendarDays,
  sichtbarkeit: Megaphone,
  auswertung: BarChart3,
  profil: Users,
};
export const NAV_GROUPS: NavGroup[] = ORGANIZER_NAV_GROUPS.map((group) => ({ ...group, icon: ICONS[group.key] }));

// Genauester Treffer statt jedes Präfixes — sonst waren auf
// /veranstalter/events/discover "Meine Events" UND "Entdecken" aktiv.
function activeHrefFor(pathname: string): string | null {
  let best: string | null = null;
  for (const item of [...ORGANIZER_TOP_LINKS, ...NAV_GROUPS.flatMap((group) => group.items)]) {
    const matches = item.href === "/veranstalter"
      ? pathname === "/veranstalter"
      : pathname === item.href || pathname.startsWith(`${item.href}/`);
    if (matches && (!best || item.href.length > best.length)) best = item.href;
  }
  return best;
}

export function SidebarNavigation({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const activeHref = activeHrefFor(pathname);

  return (
    <nav aria-label="Veranstalterportal" className="flex flex-1 flex-col gap-5 overflow-y-auto px-3 pb-4">
      <Link
        href="/veranstalter/events/new"
        onClick={onNavigate}
        className="mx-0.5 flex h-10 items-center justify-center gap-2 rounded-lg bg-[#2D2A6E] text-[13.5px] font-medium text-white hover:bg-[#1F1D52]"
      >
        <Plus className="size-4" aria-hidden="true" />
        Termin anlegen
      </Link>
      <CommandPaletteButton />
      <div className="flex flex-col gap-px">
        {ORGANIZER_TOP_LINKS.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
            aria-current={item.href === activeHref ? "page" : undefined}
            className={cn("dashboard-nav-item text-[13.5px]", item.href === activeHref && "dashboard-nav-item-active")}
          >
            <span className="flex items-center gap-2">
              <LayoutDashboard className="size-4" aria-hidden="true" />
              {item.label}
            </span>
          </Link>
        ))}
      </div>
      {NAV_GROUPS.map((group) => {
        const containsActive = group.items.some((item) => item.href === activeHref);
        return (
          <div key={group.key} className="flex flex-col gap-px">
            <Link
              href={group.items[0].href}
              onClick={onNavigate}
              aria-expanded={containsActive}
              className={cn(
                "dashboard-nav-item text-[13.5px] font-medium",
                containsActive && "text-[#111111]",
              )}
            >
              <span className="flex items-center gap-2">
                <group.icon className="size-4" aria-hidden="true" />
                {group.label}
              </span>
            </Link>
            {containsActive && (
              <div className="ml-4 flex flex-col gap-px border-l border-[#EAEAEA] pl-2">
                {group.items.map((item) => {
                  const active = item.href === activeHref;
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      onClick={onNavigate}
                      aria-current={active ? "page" : undefined}
                      className={cn("dashboard-nav-item text-[13px]", active && "dashboard-nav-item-active")}
                    >
                      {item.label}
                    </Link>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </nav>
  );
}
