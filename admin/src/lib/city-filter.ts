import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { ALL_CITIES, type CityFilterOption } from "@/lib/city-filter-types";

export const CITY_FILTER_COOKIE = "admin_city_filter";

/** Alle Städte für den globalen Umschalter (nicht nur is_active, damit auch
 * die neuen "soft_launch"-Städte schon im Admin sichtbar/wählbar sind). */
export async function getCityFilterOptions(): Promise<CityFilterOption[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("city_regions")
    .select("id, slug, name_de, short_name_de")
    .order("sort_order")
    .returns<CityFilterOption[]>();
  return data ?? [];
}

export interface ActiveCityFilter {
  /** "all" = kein Stadtfilter (Standard), sonst die gewählte Stadt. */
  slug: string;
  cityId: string | null;
}

/** Liest den aktuell gewählten globalen Stadtfilter aus dem Cookie und löst
 * ihn (falls gesetzt) gegen city_regions auf. Fällt auf "all" zurück, wenn
 * der Cookie fehlt oder eine inzwischen nicht mehr existierende Stadt
 * referenziert. */
export async function getActiveCityFilter(): Promise<ActiveCityFilter> {
  const cookieStore = await cookies();
  const slug = cookieStore.get(CITY_FILTER_COOKIE)?.value ?? ALL_CITIES;
  if (slug === ALL_CITIES) return { slug: ALL_CITIES, cityId: null };

  const options = await getCityFilterOptions();
  const match = options.find((c) => c.slug === slug);
  return match ? { slug: match.slug, cityId: match.id } : { slug: ALL_CITIES, cityId: null };
}
