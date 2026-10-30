// Navigation des Veranstalterportals – ohne "use client", damit auch die
// ⌘K-Palette sie lesen kann. Umbau 30.10.2026 (Nutzerwunsch): vier
// Hauptpunkte statt 17 Einträgen; Unterseiten klappen nur im aktiven Punkt auf.
export type OrganizerNavItem = { href: string; label: string };
export type OrganizerNavGroup = { key: string; label: string; items: OrganizerNavItem[] };

export const ORGANIZER_TOP_LINKS: OrganizerNavItem[] = [
  { href: "/veranstalter", label: "Übersicht" },
  { href: "/veranstalter/postfach", label: "Postfach" },
];

export const ORGANIZER_NAV_GROUPS: OrganizerNavGroup[] = [
  {
    key: "programm",
    label: "Programm",
    items: [
      { href: "/veranstalter/events", label: "Meine Events" },
      { href: "/veranstalter/serien", label: "Serien" },
      { href: "/veranstalter/werkeinfuehrungen", label: "Werkeinführungen" },
      { href: "/veranstalter/import", label: "Automatischer Import" },
      { href: "/veranstalter/events/discover", label: "Entdecken" },
    ],
  },
  {
    key: "sichtbarkeit",
    label: "Sichtbarkeit",
    items: [
      { href: "/veranstalter/promote", label: "Push & Promote" },
      { href: "/veranstalter/abos", label: "Abos" },
      { href: "/veranstalter/tickets", label: "Tickets & Preise" },
      { href: "/veranstalter/marketing", label: "Marketing-Tools" },
    ],
  },
  {
    key: "auswertung",
    label: "Auswertung",
    items: [
      { href: "/veranstalter/analytics", label: "Analytics" },
      { href: "/veranstalter/publikum", label: "Publikum" },
    ],
  },
  {
    key: "profil",
    label: "Profil",
    items: [
      { href: "/veranstalter/team", label: "Mitglieder & Rollen" },
      { href: "/veranstalter/agentur", label: "Agentur" },
      { href: "/veranstalter/finanzen", label: "Finanzen" },
      { href: "/veranstalter/bibliothek", label: "Bibliothek" },
      { href: "/veranstalter/claim", label: "Profil beanspruchen" },
    ],
  },
];

export const ORGANIZER_NAV_LINKS = [
  ...ORGANIZER_TOP_LINKS.map((l) => ({ ...l, group: "Übersicht" })),
  ...ORGANIZER_NAV_GROUPS.flatMap((g) => g.items.map((l) => ({ ...l, group: g.label }))),
  { href: "/veranstalter/events/new", label: "Termin anlegen", group: "Programm" },
];
