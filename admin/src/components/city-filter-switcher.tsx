"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { setCityFilter } from "./city-filter-actions";
import { ALL_CITIES, type CityFilterOption } from "@/lib/city-filter-types";

/** Globaler Stadt-Umschalter im Admin-Dashboard: "Alle Städte" zeigt
 * unverändert alles (Standard, kein neues Verhalten für bestehende
 * Redaktionsarbeit), oder gezielt eine einzelne Stadt für Venues/Quellen/
 * Events-Listen und das Städte-Dashboard. */
export function CityFilterSwitcher({
  cities,
  activeSlug,
}: {
  cities: CityFilterOption[];
  activeSlug: string;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  return (
    <select
      value={activeSlug}
      disabled={isPending}
      onChange={(e) => {
        const slug = e.target.value;
        startTransition(async () => {
          await setCityFilter(slug);
          router.refresh();
        });
      }}
      aria-label="Stadt filtern"
      className="rounded-lg border border-[#DADADA] bg-white px-3 py-1.5 text-[13px] font-medium text-[#111111] transition-colors hover:border-[#111111] disabled:opacity-50"
    >
      <option value={ALL_CITIES}>Alle Städte</option>
      {cities.map((c) => (
        <option key={c.id} value={c.slug}>
          {c.short_name_de ?? c.name_de}
        </option>
      ))}
    </select>
  );
}
