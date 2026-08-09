"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// Swiss/International-Redesign: die bisherige flache 23-Punkte-Liste war
// selbst schon ein wiederkehrender Unübersichtlichkeits-Kritikpunkt (siehe
// #b4-Feedback zum Auto-Fix-Bereich, gleiches Muster) — Gruppierung nach
// Arbeitsbereich macht die Navigation zusätzlich zum neuen visuellen Stil
// auch inhaltlich schneller scanbar.
const NAV_GROUPS = [
  {
    label: "Redaktion",
    items: [
      { href: "/events", label: "Veranstaltungen" },
      { href: "/event-groups", label: "Event-Gruppen" },
      { href: "/review-queue", label: "Review-Queue" },
      { href: "/cancellations", label: "Absage-Review" },
      { href: "/content-reports", label: "Nutzer-Meldungen" },
    ],
  },
  {
    label: "Qualität",
    items: [
      { href: "/data-quality", label: "Datenqualität" },
      { href: "/duplicates", label: "Duplikate-Review" },
      { href: "/duplicates/persons", label: "Personen-Duplikate" },
      { href: "/duplicates/works", label: "Werk-Duplikate" },
      { href: "/entity-candidates", label: "Entity-Kandidaten" },
      { href: "/reports", label: "Fehlerberichte" },
    ],
  },
  {
    label: "Stammdaten",
    items: [
      { href: "/venues", label: "Venues" },
      { href: "/persons", label: "Personen" },
      { href: "/ensembles", label: "Ensembles" },
      { href: "/festivals", label: "Festivals" },
      { href: "/editorial-collections", label: "Redaktionelle Sammlungen" },
      { href: "/tags", label: "Tags" },
      { href: "/regions", label: "Regionen" },
    ],
  },
  {
    label: "Medien",
    items: [
      { href: "/media", label: "Bilder" },
      { href: "/image-research", label: "Bilder recherchieren" },
      { href: "/bio-research", label: "Bio-Recherche" },
    ],
  },
  {
    label: "System",
    items: [
      { href: "/sources", label: "Datenquellen & Import" },
      { href: "/users", label: "Benutzer" },
    ],
  },
];

export function Sidebar({ userEmail }: { userEmail?: string }) {
  const pathname = usePathname();

  return (
    <aside className="flex w-64 shrink-0 flex-col gap-8 border-r-2 border-[#171717] bg-white px-5 py-7">
      <div className="border-b-2 border-[#171717] pb-4">
        <p className="type-heading text-base">Klassik München</p>
        <p className="type-label mt-1">Redaktions-Dashboard</p>
      </div>
      <nav className="flex flex-1 flex-col gap-6 overflow-y-auto">
        {NAV_GROUPS.map((group) => (
          <div key={group.label}>
            <p className="type-label mb-2 px-3">{group.label}</p>
            <div className="flex flex-col gap-0.5">
              {group.items.map((item) => {
                const active = pathname === item.href || pathname?.startsWith(`${item.href}/`);
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`group flex items-center gap-2.5 border-l-2 px-3 py-1.5 text-[13px] font-medium ${
                      active
                        ? "border-[#d13c1f] text-neutral-900 font-semibold"
                        : "border-transparent text-neutral-700 hover:border-[#d13c1f] hover:text-neutral-900"
                    }`}
                  >
                    {item.label}
                  </Link>
                );
              })}
            </div>
          </div>
        ))}
      </nav>
      {userEmail && (
        <p className="type-label truncate border-t-2 border-[#171717] pt-3 normal-case tracking-normal" title={userEmail}>
          {userEmail}
        </p>
      )}
    </aside>
  );
}
