"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// Gruppierung nach Arbeitsbereich (seit der Swiss-Design-Runde) macht die
// Navigation zusätzlich zum visuellen Stil auch inhaltlich schneller
// scanbar — bei der Apple-Design-Umstellung unverändert übernommen, nur
// die Optik (Material/Radius/Akzentfarbe) folgt jetzt macOS Finder/Mail:
// durchscheinende Sidebar, abgerundete blaue Auswahl-Fläche statt Linie.
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
    <aside className="glass-surface flex w-64 shrink-0 flex-col gap-6 border-r border-black/[0.06] px-3 py-6">
      <div className="px-3">
        <p className="type-heading text-[15px] text-[#1d1d1f]">Klassik München</p>
        <p className="mt-0.5 text-[11px] text-[#86868b]">Redaktions-Dashboard</p>
      </div>
      <nav className="flex flex-1 flex-col gap-5 overflow-y-auto">
        {NAV_GROUPS.map((group) => (
          <div key={group.label}>
            <p className="type-label mb-1.5 px-3">{group.label}</p>
            <div className="flex flex-col gap-0.5">
              {group.items.map((item) => {
                const active = pathname === item.href || pathname?.startsWith(`${item.href}/`);
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`rounded-full px-3 py-1.5 text-[13px] font-medium transition-colors ${
                      active
                        ? "bg-[#0071e3] text-white shadow-sm"
                        : "text-[#1d1d1f] hover:bg-black/[0.05]"
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
        <p className="truncate px-3 pt-3 text-[11px] text-[#86868b]" title={userEmail}>
          {userEmail}
        </p>
      )}
    </aside>
  );
}
