// Navigationsstruktur der Redaktion – eigene Datei ohne "use client",
// damit auch Server-Komponenten (Startseite /admin) sie lesen können.
//
// Umbau 30.10.2026 (Nutzerwunsch "unübersichtlich durch die vielen
// Unterpunkte"): Die Seitenleiste zeigt nur noch Bereiche (~20 statt 44
// Einträge). Zusammengehörige Seiten liegen als Reiter (`tabs`) im Bereich
// und erscheinen oben auf der Seite (SectionTabs). Alle Pfade bleiben
// unverändert; ⌘K springt direkt zu jeder Seite und jedem Datensatz.
export type NavLink = { href: string; label: string };
export type NavArea = NavLink & { tabs?: NavLink[] };
export type NavGroupDef = { label: string; items: NavArea[] };

export const NAV_GROUPS: NavGroupDef[] = [
  {
    label: "Heute",
    items: [
      { href: "/admin", label: "Startseite" },
      {
        href: "/eingang",
        label: "Eingang",
        tabs: [
          { href: "/eingang", label: "Alles" },
          { href: "/review-queue", label: "Review-Queue" },
          { href: "/cancellations", label: "Absagen" },
          { href: "/content-reports", label: "Meldungen & Fehler" },
          { href: "/entity-requests", label: "Nutzeranfragen" },
          { href: "/wichtig", label: "Kennzahlen" },
        ],
      },
      { href: "/todos", label: "To-Dos" },
    ],
  },
  {
    label: "Programm",
    items: [
      {
        href: "/events",
        label: "Veranstaltungen",
        tabs: [
          { href: "/events", label: "Termine" },
          { href: "/event-groups", label: "Event-Gruppen" },
          { href: "/festivals", label: "Festivals" },
        ],
      },
      { href: "/abos", label: "Abos" },
      { href: "/editorial-collections", label: "Sammlungen" },
      {
        href: "/event-promotions",
        label: "Promotion",
        tabs: [
          { href: "/event-promotions", label: "Promotions" },
          { href: "/promotion-preise", label: "Preise" },
        ],
      },
      { href: "/media", label: "Bilderfreigabe" },
    ],
  },
  {
    label: "Wissen",
    items: [
      { href: "/persons", label: "Personen" },
      {
        href: "/ensembles",
        label: "Ensembles",
        tabs: [
          { href: "/ensembles", label: "Ensembles" },
          { href: "/ensemble-families", label: "Ensemblefamilien" },
        ],
      },
      {
        href: "/works",
        label: "Werke",
        tabs: [
          { href: "/works", label: "Werke" },
          { href: "/werkeinfuehrungen", label: "Werkeinführungen" },
          { href: "/work-image-reuse", label: "Bild-Verknüpfungen" },
        ],
      },
      { href: "/venues", label: "Venues" },
      { href: "/organizers", label: "Veranstalter" },
      { href: "/knowledge-graph", label: "Knowledge Graph" },
    ],
  },
  {
    label: "Datenqualität",
    items: [
      {
        href: "/qualitaetspruefung",
        label: "Prüfen & Anreichern",
        tabs: [
          { href: "/qualitaetspruefung", label: "Qualitätsprüfung" },
          { href: "/datenluecken", label: "Datenlücken" },
          { href: "/data-quality", label: "Recherche & Anreicherung" },
          { href: "/bekanntheit", label: "Bekanntheit" },
        ],
      },
      {
        href: "/duplicates",
        label: "Duplikate & Namen",
        tabs: [
          { href: "/duplicates", label: "Duplikate" },
          { href: "/entity-candidates", label: "Entity-Kandidaten" },
          { href: "/aliases", label: "Schreibweisen & Aliasse" },
        ],
      },
      {
        href: "/entity-claims",
        label: "Vertrauen",
        tabs: [
          { href: "/entity-claims", label: "Veranstalter-Claims" },
          { href: "/entity-edit-suggestions", label: "Profiländerungen" },
          { href: "/entity-trust", label: "Verifizierung" },
          { href: "/moderation", label: "Community-Moderation" },
        ],
      },
    ],
  },
  {
    label: "System",
    items: [
      {
        href: "/sources",
        label: "Quellen & Import",
        tabs: [
          { href: "/sources", label: "Datenquellen" },
          { href: "/source-health", label: "Quellen-Gesundheit" },
        ],
      },
      {
        href: "/users",
        label: "Einstellungen",
        tabs: [
          { href: "/users", label: "Benutzer" },
          { href: "/plus", label: "Klangradar Plus" },
          { href: "/partner", label: "Partner & Affiliate" },
          { href: "/invoice-settings", label: "Rechnungsdaten" },
          { href: "/regions", label: "Regionen" },
          { href: "/tags", label: "Tags" },
          { href: "/attributes", label: "Attribute & Inspiration" },
        ],
      },
    ],
  },
];

/** Alle erreichbaren Seiten (Bereiche + Reiter), ohne Dubletten. */
export const ALL_NAV_LINKS: (NavLink & { group: string; area: string })[] = (() => {
  const seen = new Set<string>();
  const out: (NavLink & { group: string; area: string })[] = [];
  for (const group of NAV_GROUPS) {
    for (const area of group.items) {
      for (const link of [area, ...(area.tabs ?? [])]) {
        if (seen.has(link.href)) continue;
        seen.add(link.href);
        out.push({ ...link, group: group.label, area: area.label });
      }
    }
  }
  return out;
})();

/** Bereich (inkl. Gruppe) zur genauest passenden Seite. */
export function findNavArea(pathname: string | null) {
  if (!pathname) return null;
  let best: { href: string; group: NavGroupDef; area: NavArea } | null = null;
  for (const group of NAV_GROUPS) {
    for (const area of group.items) {
      for (const link of [area, ...(area.tabs ?? [])]) {
        if ((pathname === link.href || pathname.startsWith(`${link.href}/`)) && (!best || link.href.length > best.href.length)) {
          best = { href: link.href, group, area };
        }
      }
    }
  }
  return best;
}
