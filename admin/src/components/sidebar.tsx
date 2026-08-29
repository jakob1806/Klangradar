"use client";

import Link from "next/link";
import Image from "next/image";
import { usePathname } from "next/navigation";

// Gruppierung nach Arbeitsbereich (seit der ersten Redesign-Runde) macht
// die Navigation zusätzlich zum visuellen Stil auch inhaltlich schneller
// scanbar. Optik nach der Apple-Design-Skill-Referenz (Abschnitt
// "Materials & Depth"): Sidebar als durchscheinende Ebene statt Volltonfarbe,
// aktiver Eintrag als abgerundete Fläche in der einen Akzentfarbe.
// Nutzeranfrage: "gruppen von 5 auf 3 ohne den inhalt der gruppen jeweils
// zu ändern, nur die struktur" — rein mechanisches Zusammenlegen benachbarter
// Gruppen (Redaktion+Medien, Stammdaten+System), Reihenfolge und Beschriftung
// der einzelnen Einträge bleibt unangetastet, nur die drei ursprünglichen
// Gruppen-Header verschwinden zugunsten der zusammengelegten Labels.
const NAV_GROUPS = [
  {
    label: "Wichtig",
    items: [
      { href: "/wichtig", label: "Offene Aufgaben" },
      { href: "/todos", label: "To-Dos" },
    ],
  },
  {
    label: "Redaktion & Medien",
    items: [
      { href: "/events", label: "Veranstaltungen" },
      { href: "/event-groups", label: "Event-Gruppen" },
      { href: "/review-queue", label: "Review-Queue" },
      { href: "/cancellations", label: "Absage-Review" },
      { href: "/content-reports", label: "Meldungen & Fehler" },
      { href: "/media", label: "Bilderfreigabe" },
    ],
  },
  {
    label: "Qualität",
    items: [
      { href: "/data-quality", label: "Recherche & Anreicherung" },
      { href: "/duplicates", label: "Duplikate" },
      { href: "/entity-candidates", label: "Entity-Kandidaten" },
      { href: "/entity-claims", label: "Veranstalter-Claims" },
      { href: "/entity-edit-suggestions", label: "Profiländerungsvorschläge" },
      { href: "/entity-trust", label: "Verifizierung" },
      { href: "/qualitaetspruefung", label: "Qualitätsprüfung" },
      { href: "/work-image-reuse", label: "Werk-Bild-Verknüpfungen" },
      { href: "/aliases", label: "Schreibweisen & Aliasse" },
    ],
  },
  {
    label: "Stammdaten & System",
    items: [
      { href: "/venues", label: "Venues" },
      { href: "/persons", label: "Personen" },
      { href: "/ensembles", label: "Ensembles" },
      { href: "/ensemble-families", label: "Ensemblefamilien" },
      { href: "/festivals", label: "Festivals" },
      { href: "/editorial-collections", label: "Redaktionelle Sammlungen" },
      { href: "/attributes", label: "Attribute & Inspiration" },
      { href: "/tags", label: "Tags" },
      { href: "/regions", label: "Regionen" },
      { href: "/sources", label: "Datenquellen & Import" },
      { href: "/source-health", label: "Quellen-Gesundheit" },
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
    <aside className="dashboard-sidebar">
      <div className="dashboard-brand">
        <span className="dashboard-brand-mark" aria-hidden="true">
          <Image src="/app-logo.svg" alt="" width={40} height={40} priority />
        </span>
        <span className="min-w-0">
          <span className="block truncate text-[15px] font-semibold tracking-[-0.014em] text-[#1d1d1f]">Klangradar</span>
          <span className="mt-0.5 block truncate text-[11px] text-[#86868b]">Redaktions-Dashboard</span>
        </span>
      </div>
      <nav className="dashboard-sidebar-nav">
        {NAV_GROUPS.map((group) => (
          <div key={group.label} className="dashboard-nav-group">
            <p className="type-label mb-1.5 px-2.5">{group.label}</p>
            <div className="flex flex-col gap-0.5">
              {group.items.map((item) => {
                const active = item.href === activeHref;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    aria-current={active ? "page" : undefined}
                    className={`dashboard-nav-item ${active ? "dashboard-nav-item-active" : ""}`}
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
        <div className="dashboard-account" title={userEmail}>
          <span className="dashboard-account-avatar" aria-hidden="true">{userEmail.slice(0, 1).toUpperCase()}</span>
          <span className="min-w-0">
            <span className="block text-[10px] font-semibold uppercase tracking-[0.06em] text-[#86868b]">Angemeldet</span>
            <span className="block truncate text-[11px] text-[#424245]">{userEmail}</span>
          </span>
        </div>
      )}
    </aside>
  );
}
