"use server";

import { createClient } from "@/lib/supabase/server";

export type ClaimMatchType = "organizer" | "venue" | "person" | "ensemble";

export interface ClaimMatch {
  id: string;
  name: string;
  type: ClaimMatchType;
  photoUrl: string | null;
}

// Live-Vorschläge für die Claim-Suche (siehe ClaimSearch-Client-Komponente):
// Nutzerfeedback "man soll nicht erst auf Suchen klicken müssen" — als
// Server Action statt Route Handler, weil der Rest von claim/ (actions.ts,
// entity-claim-actions.ts) demselben Muster folgt statt eigener API-Routen.
export async function searchClaimCandidates(query: string): Promise<ClaimMatch[]> {
  const trimmed = query.trim();
  if (trimmed.length < 2) return [];
  const supabase = await createClient();

  const [organizers, venues, persons, ensembles] = await Promise.all([
    supabase.rpc("find_matching_organizer", { p_name: trimmed, p_similarity_threshold: 0.3, p_result_limit: 5 }),
    supabase.rpc("find_matching_venue", { p_name: trimmed, p_similarity_threshold: 0.3, p_result_limit: 5 }),
    supabase.rpc("find_matching_person_with_photo", { p_name: trimmed, p_similarity_threshold: 0.3, p_result_limit: 5 }),
    supabase.rpc("find_matching_ensemble", { p_name: trimmed, p_similarity_threshold: 0.3, p_result_limit: 5 }),
  ]);

  return [
    ...((organizers.data ?? []) as { id: string; name: string; photo_url: string | null }[]).map(
      (r): ClaimMatch => ({ id: r.id, name: r.name, type: "organizer", photoUrl: r.photo_url })
    ),
    ...((venues.data ?? []) as { id: string; name: string; photo_url: string | null }[]).map(
      (r): ClaimMatch => ({ id: r.id, name: r.name, type: "venue", photoUrl: r.photo_url })
    ),
    ...((persons.data ?? []) as { id: string; full_name: string; photo_url: string | null }[]).map(
      (r): ClaimMatch => ({ id: r.id, name: r.full_name, type: "person", photoUrl: r.photo_url })
    ),
    ...((ensembles.data ?? []) as { id: string; name: string; photo_url: string | null }[]).map(
      (r): ClaimMatch => ({ id: r.id, name: r.name, type: "ensemble", photoUrl: r.photo_url })
    ),
  ];
}
