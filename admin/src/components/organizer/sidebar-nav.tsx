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
  Library,
  BadgeCheck,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";

export type NavItem = { href: string; label: string };
export type NavGroup = { label: string; icon: LucideIcon; items: NavItem[] };

// Gruppiert die inzwischen zehn Portal-Seiten thematisch statt sie als eine
// einzelne, endlos wachsende Pill-Leiste nebeneinander zu reihen — skaliert
// auch mit den neuen Team-/Postfach-Bereichen (Nutzerwunsch: "deutliche
// Erweiterung im Bereich der Navigation").
export const NAV_GROUPS: NavGroup[] = [
  { label: "Übersicht", icon: LayoutDashboard, items: [{ href: "/veranstalter", label: "Dashboard" }] },
  {
    label: "Events",
    icon: CalendarDays,
    items: [
      { href: "/veranstalter/events", label: "Meine Events" },
      { href: "/veranstalter/events/discover", label: "Entdecken" },
      { href: "/veranstalter/serien", label: "Serien" },
    ],
  },
  {
    label: "Team",
    icon: Users,
    items: [
      { href: "/veranstalter/team", label: "Mitglieder & Rollen" },
      { href: "/veranstalter/agentur", label: "Agentur" },
    ],
  },
  {
    label: "Marketing",
    icon: Megaphone,
    items: [
      { href: "/veranstalter/promote", label: "Push & Promote" },
      { href: "/veranstalter/marketing", label: "Marketing-Tools" },
    ],
  },
  {
    label: "Auswertung",
    icon: BarChart3,
    items: [
      { href: "/veranstalter/analytics", label: "Analytics" },
      { href: "/veranstalter/finanzen", label: "Finanzen" },
    ],
  },
  { label: "Bibliothek", icon: Library, items: [{ href: "/veranstalter/bibliothek", label: "Bibliothek" }] },
  { label: "Beanspruchen", icon: BadgeCheck, items: [{ href: "/veranstalter/claim", label: "Neue Entität beanspruchen" }] },
];

function isActive(pathname: string, href: string) {
  if (href === "/veranstalter") return pathname === "/veranstalter";
  return pathname === href || pathname.startsWith(`${href}/`);
}

// Eigenständige, dunkle Sidebar-Optik (Nutzerwunsch: "unabhängig von Apple")
// statt der hellen, halbtransparenten Redaktions-Chrome — Weinrot als
// einzige Akzentfarbe für den aktiven Zustand, sonst zurückhaltendes Grau
// auf Tinte.
export function SidebarNavigation({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();

  return (
    <nav className="flex flex-1 flex-col gap-5 overflow-y-auto px-3 pb-4">
      {NAV_GROUPS.map((group) => (
        <div key={group.label} className="flex flex-col gap-0.5">
          <div className="flex items-center gap-2 px-2.5 py-1 text-[10.5px] font-semibold uppercase tracking-[0.08em] text-white/35">
            <group.icon className="size-3.5" aria-hidden="true" />
            {group.label}
          </div>
          {group.items.map((item) => {
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={onNavigate}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "rounded-[8px] px-3 py-1.5 text-[13.5px] font-medium transition",
                  active ? "bg-[#7d1a3a] text-white shadow-[0_2px_8px_rgba(125,26,58,0.35)]" : "text-white/65 hover:bg-white/[0.06] hover:text-white"
                )}
              >
                {item.label}
              </Link>
            );
          })}
        </div>
      ))}
    </nav>
  );
}
