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
/** key: Tastenkürzel „g“ + Buchstabe springt zum ersten Eintrag der Gruppe. */
export type NavGroupDef = { label: string; key?: string; items: NavArea[] };

// Neuordnung 14.11.2026 (Nutzerwunsch „man sucht ewig“): nach Gegenstand
// statt nach Tätigkeit, nur deutsche Namen, alle Seiten erreichbar,
// höchstens fünf Einträge je Bereich. Alle Pfade bleiben unverändert.
export const NAV_GROUPS: NavGroupDef[] = [
  {
    label: "Heute",
    key: "h",
    items: [
      { href: "/admin", label: "Startseite" },
      {
        href: "/eingang",
        label: "Eingang",
        tabs: [
          { href: "/eingang", label: "Alles" },
          { href: "/review-queue", label: "Termine prüfen" },
          { href: "/wichtig", label: "Kennzahlen" },
        ],
      },
      { href: "/todos", label: "To-Dos" },
    ],
  },
  {
    label: "Programm",
    key: "p",
    items: [
      {
        href: "/events",
        label: "Konzerte",
        tabs: [
          { href: "/events", label: "Termine" },
          { href: "/event-groups", label: "Event-Gruppen" },
          { href: "/festivals", label: "Festivals" },
          { href: "/cancellations", label: "Absagen" },
        ],
      },
      {
        href: "/abos",
        label: "Abos & Reihen",
        tabs: [
          { href: "/abos", label: "Abos" },
          { href: "/editorial-collections", label: "Sammlungen" },
        ],
      },
      {
        href: "/event-promotions",
        label: "Promotion",
        tabs: [
          { href: "/event-promotions", label: "Promotions" },
          { href: "/promotion-preise", label: "Preise" },
        ],
      },
    ],
  },
  {
    label: "Verzeichnis",
    key: "v",
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
        ],
      },
      {
        href: "/venues",
        label: "Spielstätten",
        tabs: [
          { href: "/venues", label: "Spielstätten" },
          { href: "/saalplaene", label: "Saalpläne" },
        ],
      },
      {
        href: "/organizers",
        label: "Veranstalter",
        tabs: [
          { href: "/organizers", label: "Veranstalter" },
          { href: "/entity-claims", label: "Profil-Claims" },
        ],
      },
    ],
  },
  {
    label: "Bilder",
    key: "b",
    items: [
      {
        href: "/media",
        label: "Bilder",
        tabs: [
          { href: "/media", label: "Freigabe" },
          { href: "/media/pruefen", label: "Prüfen" },
          { href: "/media/gaps", label: "Bildlücken" },
          { href: "/image-research", label: "Recherche" },
          { href: "/work-image-reuse", label: "Werk-Bilder" },
        ],
      },
    ],
  },
  {
    label: "Qualität",
    key: "q",
    items: [
      {
        href: "/qualitaetspruefung",
        label: "Prüfen",
        tabs: [
          { href: "/qualitaetspruefung", label: "Qualitätsprüfung" },
          { href: "/datenluecken", label: "Datenlücken" },
          { href: "/bekanntheit", label: "Bekanntheit" },
        ],
      },
      {
        href: "/data-quality",
        label: "Recherche",
        tabs: [
          { href: "/data-quality", label: "Anreicherung" },
          { href: "/bio-research", label: "Bio-Recherche" },
        ],
      },
      {
        href: "/duplicates",
        label: "Duplikate",
        tabs: [
          { href: "/duplicates", label: "Duplikate" },
          { href: "/entity-candidates", label: "Kandidaten" },
          { href: "/aliases", label: "Schreibweisen" },
        ],
      },
      {
        href: "/content-reports",
        label: "Community",
        tabs: [
          { href: "/content-reports", label: "Meldungen" },
          { href: "/content-reports-native", label: "App-Meldungen" },
          { href: "/entity-requests", label: "Nutzeranfragen" },
          { href: "/entity-edit-suggestions", label: "Profiländerungen" },
          { href: "/entity-trust", label: "Verifizierung" },
          { href: "/moderation", label: "Moderation" },
        ],
      },
    ],
  },
  {
    label: "Betrieb",
    key: "s",
    items: [
      {
        href: "/sources",
        label: "Quellen",
        tabs: [
          { href: "/sources", label: "Datenquellen" },
          { href: "/source-health", label: "Gesundheit" },
        ],
      },
      {
        href: "/plus",
        label: "Geschäft",
        tabs: [
          { href: "/plus", label: "Klangradar Plus" },
          { href: "/partner", label: "Partner & Affiliate" },
          { href: "/invoice-settings", label: "Rechnungsdaten" },
        ],
      },
      {
        href: "/users",
        label: "Einstellungen",
        tabs: [
          { href: "/users", label: "Benutzer" },
          { href: "/regions", label: "Regionen" },
          { href: "/tags", label: "Tags" },
          { href: "/attributes", label: "Attribute & Inspiration" },
        ],
      },
      {
        href: "/knowledge-graph",
        label: "Technik",
        tabs: [
          { href: "/knowledge-graph", label: "Knowledge Graph" },
          { href: "/code-fix-tasks", label: "Code-Fix-Aufgaben" },
          { href: "/reports", label: "Flutter-Meldungen" },
        ],
      },
    ],
  },
];

/** Direkte Tastenkürzel „g“ + Buchstabe für häufige Bereiche. */
export const NAV_SHORTCUTS: Record<string, { href: string; label: string }> = {
  ...Object.fromEntries(NAV_GROUPS.filter((g) => g.key).map((g) => [g.key!, { href: g.items[0].href, label: g.label }])),
  e: { href: "/eingang", label: "Eingang" },
  k: { href: "/events", label: "Konzerte" },
  d: { href: "/duplicates", label: "Duplikate" },
};

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
