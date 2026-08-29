"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

// Deutlich einfacher als approveEntityCandidate (entity-candidates/actions.ts):
// die Zielentität existiert bereits, kein Slug, kein "existiert schon"-Check,
// keine Duplikat-Weiterleitung nötig — Genehmigen/Ablehnen ist ein reiner
// Status-Flip. Sobald status='approved', greift has_approved_organizer_claim()
// bzw. die entsprechenden RLS-Policies sofort (kein Cache/Sync-Schritt nötig).
export async function approveEntityClaim(claimId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase
    .from("entity_claims")
    .update({ status: "approved", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", claimId);
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "entity_claim",
    entityId: claimId,
    action: "approved",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/entity-claims");
}

export async function rejectEntityClaim(claimId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase
    .from("entity_claims")
    .update({ status: "rejected", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", claimId);
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "entity_claim",
    entityId: claimId,
    action: "rejected",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/entity-claims");
}
