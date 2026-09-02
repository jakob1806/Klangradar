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
  Wallet,
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
  {
    label: "Übersicht",
    icon: LayoutDashboard,
    items: [
      { href: "/veranstalter", label: "Dashboard" },
      { href: "/veranstalter/postfach", label: "Postfach" },
    ],
  },
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
  // Nutzerfeedback: "Auswertung" bündelte Analytics + Finanzen -- unter-
  // schiedliche Nutzungsrhythmen (Analytics eher täglich, Finanzen eher
  // monatlich), getrennte Gruppen sind klarer als eine gemeinsame.
  { label: "Analytics", icon: BarChart3, items: [{ href: "/veranstalter/analytics", label: "Analytics" }] },
  { label: "Finanzen", icon: Wallet, items: [{ href: "/veranstalter/finanzen", label: "Finanzen" }] },
  { label: "Bibliothek", icon: Library, items: [{ href: "/veranstalter/bibliothek", label: "Bibliothek" }] },
  { label: "Beanspruchen", icon: BadgeCheck, items: [{ href: "/veranstalter/claim", label: "Neue Entität beanspruchen" }] },
];

function isActive(pathname: string, href: string) {
  if (href === "/veranstalter") return pathname === "/veranstalter";
  return pathname === href || pathname.startsWith(`${href}/`);
}

// Helle, weiche Sidebar-Optik (Soft-Minimalist-Flat-UI) — Indigo als einzige
// Akzentfarbe für den aktiven Zustand (weiche Pastell-Fläche + Indigo-Text),
// sonst zurückhaltendes Grau auf Off-White.
export function SidebarNavigation({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();

  return (
    <nav className="flex flex-1 flex-col gap-5 overflow-y-auto px-3 pb-4">
      {NAV_GROUPS.map((group) => (
        <div key={group.label} className="flex flex-col gap-0.5">
          <div className="flex items-center gap-2 px-2.5 py-1 text-[10.5px] font-semibold uppercase tracking-[0.08em] text-[#A1A1AA]">
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
                  "rounded-[10px] px-3 py-1.5 text-[13.5px] font-medium transition",
                  active ? "bg-[#ECEBFA] text-[#2D2A6E] font-semibold" : "text-[#71717A] hover:bg-[#EEEEE9] hover:text-[#18181B]"
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
