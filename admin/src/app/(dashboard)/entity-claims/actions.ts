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

  const { data: claim, error: fetchError } = await supabase
    .from("entity_claims")
    .select("entity_type, entity_id")
    .eq("id", claimId)
    .maybeSingle();
  if (fetchError || !claim) throw new Error(fetchError?.message ?? "Claim nicht gefunden");

  // Der ERSTE genehmigte Claim einer Entität wird automatisch Owner — sonst
  // hätte eine ausschließlich per Redaktion freigegebene Entität nie einen
  // Owner und niemand könnte je weitere Team-Mitglieder selbst freischalten
  // (siehe is_owner_of_entity()/Team-Rechte-Migration). Jeder weitere
  // Claim auf dieselbe Entität bleibt beim Default 'editor' — ein
  // bestehender Owner kann ihn bei Bedarf selbst befördern.
  const { count: existingOwnerCount } = await supabase
    .from("entity_claims")
    .select("id", { count: "exact", head: true })
    .eq("entity_type", claim.entity_type)
    .eq("entity_id", claim.entity_id)
    .eq("status", "approved")
    .eq("role", "owner");
  const role = existingOwnerCount && existingOwnerCount > 0 ? "editor" : "owner";

  const { error } = await supabase
    .from("entity_claims")
    .update({ status: "approved", role, reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
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
