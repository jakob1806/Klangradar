"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// Gruppierung nach Arbeitsbereich (seit der ersten Redesign-Runde) macht
// die Navigation zusätzlich zum visuellen Stil auch inhaltlich schneller
// scanbar. Optik nach der Apple-Design-Skill-Referenz (Abschnitt
// "Materials & Depth"): Sidebar als durchscheinende Ebene statt Volltonfarbe,
// aktiver Eintrag als abgerundete Fläche in der einen Akzentfarbe.
const NAV_GROUPS = [
  {
    label: "Redaktion",
    items: [
      { href: "/events", label: "Veranstaltungen" },
      { href: "/event-groups", label: "Event-Gruppen" },
      { href: "/review-queue", label: "Review-Queue" },
      { href: "/cancellations", label: "Absage-Review" },
      { href: "/content-reports", label: "Nutzer-Meldungen (Flutter)" },
      { href: "/content-reports-native", label: "Nutzer-Meldungen (Native)" },
      { href: "/code-fix-tasks", label: "Code-Aufgaben (Claude Code)" },
    ],
  },
  {
    label: "Qualität",
    items: [
      { href: "/data-quality", label: "Datenqualität" },
      { href: "/duplicates", label: "Duplikate" },
      { href: "/entity-candidates", label: "Entity-Kandidaten" },
      { href: "/qualitaetspruefung", label: "Qualitätsprüfung" },
      { href: "/work-image-reuse", label: "Werk-Bild-Verknüpfungen" },
      { href: "/aliases", label: "Schreibweisen & Aliasse" },
      { href: "/reports", label: "Fehlerberichte" },
    ],
  },
  {
    label: "Stammdaten",
    items: [
      { href: "/venues", label: "Venues" },
      { href: "/persons", label: "Personen" },
      { href: "/ensembles", label: "Ensembles" },
      { href: "/ensemble-families", label: "Ensemblefamilien" },
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

// Ermittelt den am genauesten passenden Nav-Eintrag statt jeden Präfix-Treffer
// separat aktiv zu markieren — sonst blieb z.B. "Duplikate-Review" (/duplicates)
// dauerhaft blau hervorgehoben, auch auf /duplicates/persons oder
// /duplicates/works, weil deren Pfad ebenfalls mit "/duplicates" beginnt und
// jeder Eintrag unabhängig voneinander geprüft wurde (Nutzerfeedback: "der
// blaue hintergrund hängt immer bei duplikate review fest, auch wenn man zu
// einer anderen kategorie wechselt").
function bestMatchingHref(pathname: string, hrefs: string[]): string | null {
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
  const activeHref = pathname
    ? bestMatchingHref(
        pathname,
        NAV_GROUPS.flatMap((group) => group.items.map((item) => item.href)),
      )
    : null;

  return (
    <aside className="flex w-64 shrink-0 flex-col gap-6 border-r border-black/[0.06] bg-[#f5f5f7]/80 px-3 py-6 backdrop-blur-xl">
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
                const active = item.href === activeHref;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`rounded-lg px-3 py-1.5 text-[13px] font-medium transition-colors ${
                      active ? "bg-[#0071e3] text-white" : "text-[#1d1d1f] hover:bg-black/[0.04]"
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
