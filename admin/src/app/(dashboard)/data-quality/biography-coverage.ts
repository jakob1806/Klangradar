// Nutzerfeedback: "datenqualität soll auch anhand von fehlenden
// biographien beurteilen, nicht nur anhand fehlender bilder" — der
// Gesamtscore (quality-score.ts) zählte biography_de bei Personen zwar
// schon als kritisches Feld, aber sichtbar war das nur versteckt in der auf
// die nächsten 90 Tage eingegrenzten "Profil-Vollständigkeit"-Tabelle. Bild-
// Abdeckung hatte dagegen einen eigenen, prominenten Abschnitt über den
// GESAMTEN Bestand (image-coverage.ts) — dieselbe Struktur hier für Text-
// Profile (Personen: biography_de, Ensembles/Venues: description_de), damit
// beide Lücken gleichwertig sichtbar sind, nicht nur Bilder.
import { createClient } from "@/lib/supabase/server";

export interface BiographyCoverageReport {
  persons: { total: number; withBiography: number };
  ensembles: { total: number; withDescription: number };
  venues: { total: number; withDescription: number };
}

function isFilled(value: string | null): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

export function aggregateBiographyCoverage(rows: {
  persons: { biography_de: string | null }[];
  ensembles: { description_de: string | null }[];
  venues: { description_de: string | null }[];
}): BiographyCoverageReport {
  return {
    persons: {
      total: rows.persons.length,
      withBiography: rows.persons.filter((p) => isFilled(p.biography_de)).length,
    },
    ensembles: {
      total: rows.ensembles.length,
      withDescription: rows.ensembles.filter((e) => isFilled(e.description_de)).length,
    },
    venues: {
      total: rows.venues.length,
      withDescription: rows.venues.filter((v) => isFilled(v.description_de)).length,
    },
  };
}

export interface MissingBiographyPerson {
  id: string;
  full_name: string;
}

export async function fetchBiographyCoverageReport(): Promise<{
  report: BiographyCoverageReport | null;
  missingPersons: MissingBiographyPerson[];
  error: string | null;
}> {
  const supabase = await createClient();

  const [persons, ensembles, venues] = await Promise.all([
    supabase.from("persons").select("id, full_name, biography_de"),
    supabase.from("ensembles").select("description_de"),
    supabase.from("venues").select("description_de"),
  ]);

  if (persons.error || ensembles.error || venues.error) {
    const firstError = persons.error ?? ensembles.error ?? venues.error;
    return { report: null, missingPersons: [], error: firstError?.message ?? "Unbekannter Fehler" };
  }

  const personRows = persons.data ?? [];
  const missingPersons = personRows
    .filter((p) => !isFilled(p.biography_de))
    .map((p) => ({ id: p.id as string, full_name: p.full_name as string }));

  return {
    report: aggregateBiographyCoverage({
      persons: personRows,
      ensembles: ensembles.data ?? [],
      venues: venues.data ?? [],
    }),
    missingPersons,
    error: null,
  };
}
