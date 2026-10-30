"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { findNavArea } from "@/components/nav-groups";

// Reiter des aktuellen Bereichs (siehe NAV_GROUPS[].items[].tabs) oben auf
// jeder Seite — ersetzt die vielen Einzeleinträge der Seitenleiste.
export function SectionTabs() {
  const pathname = usePathname();
  const match = findNavArea(pathname);
  const tabs = match?.area.tabs;
  if (!tabs || tabs.length < 2) return null;

  return (
    <nav aria-label={match.area.label} className="flex gap-1 overflow-x-auto border-b border-[#EAEAEA] px-8 pt-3">
      {tabs.map((tab) => {
        const active = tab.href === match.href;
        return (
          <Link
            key={tab.href}
            href={tab.href}
            aria-current={active ? "page" : undefined}
            className={`-mb-px shrink-0 whitespace-nowrap border-b-2 px-3 pb-2.5 text-[13px] font-medium ${
              active ? "border-[#2D2A6E] text-[#111111]" : "border-transparent text-[#6B6B6B] hover:text-[#111111]"
            }`}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
