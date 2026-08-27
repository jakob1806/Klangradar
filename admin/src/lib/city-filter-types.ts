// Reine Typen/Konstanten ohne Server-only-Importe (next/headers) — eigene
// Datei, damit city-filter-switcher.tsx (Client Component) sie importieren
// kann, ohne city-filter.ts's next/headers-Abhängigkeit mit in den
// Client-Bundle zu ziehen (Next.js verbietet das: "You're importing a
// module that depends on 'next/headers' ... in the Pages Router").
export const ALL_CITIES = "all";

export interface CityFilterOption {
  id: string;
  slug: string;
  name_de: string;
  short_name_de: string | null;
}
