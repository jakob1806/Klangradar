"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const items = [
  { href: "/veranstalter", label: "Übersicht" },
  { href: "/veranstalter/events", label: "Programm" },
  { href: "/veranstalter/bibliothek", label: "Inhalte" },
  { href: "/veranstalter/marketing", label: "Marketing" },
  { href: "/veranstalter/analytics", label: "Reichweite" },
  { href: "/veranstalter/agentur", label: "Organisation" },
] as const;

export function OrganizerNavigation() {
  const pathname = usePathname();

  return (
    <nav aria-label="Veranstalterportal" className="flex min-w-0 items-center gap-1 overflow-x-auto px-5 pb-2.5 sm:px-7">
      {items.map((item) => {
        const active = item.href === "/veranstalter" ? pathname === item.href : pathname.startsWith(item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={`shrink-0 rounded-lg px-3 py-1.5 text-[0.82rem] font-medium transition duration-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#8b2635] ${
              active
                ? "bg-[#8b2635] text-white shadow-[0_4px_14px_rgba(139,38,53,0.18)]"
                : "text-[#5f5b56] hover:bg-black/[0.045] hover:text-[#1d1d1f] active:scale-[0.98]"
            }`}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
