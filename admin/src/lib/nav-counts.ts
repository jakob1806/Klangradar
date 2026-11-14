"use server";

import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (14.11.2026): Zahlen-Plaketten der Seitenleiste –
// offene Aufgaben je Seite. Nur „head“-Zählungen (keine Zeilen), die
// Seitenleiste ruft das höchstens alle zwei Minuten ab.
export async function getNavCounts(): Promise<Record<string, number>> {
  const supabase = await createClient();
  const head = { count: "exact" as const, head: true };
  const [review, cancellations, reports, requests, claims, edits, duplicates, candidates, images] = await Promise.all([
    supabase.from("events").select("id", head).in("review_status", ["needs_review", "needs_quick_check"]),
    supabase.from("cancellation_candidates").select("id", head).eq("status", "pending"),
    supabase.from("content_reports").select("id", head).eq("status", "pending"),
    supabase.from("entity_requests").select("id", head).eq("status", "pending"),
    supabase.from("entity_claims").select("id", head).eq("status", "pending"),
    supabase.from("entity_edit_suggestions").select("id", head).eq("status", "pending"),
    supabase.from("duplicate_candidates").select("id", head).eq("status", "pending"),
    supabase.from("entity_candidates").select("id", head).eq("status", "pending"),
    supabase.from("images").select("id", head).eq("needs_review", true),
  ]);
  const n = (r: { count: number | null }) => r.count ?? 0;
  const counts: Record<string, number> = {
    "/review-queue": n(review),
    "/cancellations": n(cancellations),
    "/content-reports": n(reports),
    "/entity-requests": n(requests),
    "/entity-claims": n(claims),
    "/entity-edit-suggestions": n(edits),
    "/duplicates": n(duplicates),
    "/entity-candidates": n(candidates),
    "/media/pruefen": n(images),
  };
  counts["/eingang"] = n(review) + n(cancellations) + n(reports) + n(requests) + n(claims) + n(edits) + n(duplicates) + n(candidates);
  return counts;
}
