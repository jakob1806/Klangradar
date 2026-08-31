"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";
import { getResend } from "@/lib/resend";
import { resolveEntityNames, type ClaimableEntityType } from "@/lib/entity-tables";

// Bewusst ohne await im Aufrufer und mit eigenem try/catch: eine fehlgeschlagene
// Benachrichtigungsmail (z. B. Resend down) darf den bereits erfolgten
// Status-Flip nicht rückgängig machen oder dem Redakteur einen Fehler zeigen
// — dieselbe Nachsichtigkeit wie bei logSystemAction, das ebenfalls nach dem
// eigentlichen Update passiert.
async function notifyClaimant(
  supabase: Awaited<ReturnType<typeof createClient>>,
  claim: { entity_type: ClaimableEntityType; entity_id: string; verification_email: string | null },
  outcome: "approved" | "rejected",
) {
  if (!claim.verification_email) return;
  try {
    const names = await resolveEntityNames(supabase, [{ entityType: claim.entity_type, entityId: claim.entity_id }]);
    const name = names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "deine Anfrage";
    const subject = outcome === "approved" ? `Dein Claim für ${name} wurde genehmigt` : `Dein Claim für ${name} wurde abgelehnt`;
    const html =
      outcome === "approved"
        ? `<p>Dein Antrag, <strong>${name}</strong> auf Klangradar zu verwalten, wurde genehmigt.</p><p><a href="https://klangradar.com/veranstalter">Jetzt im Veranstalterportal loslegen</a></p>`
        : `<p>Dein Antrag, <strong>${name}</strong> auf Klangradar zu verwalten, wurde leider abgelehnt.</p><p>Bei Fragen antworte gerne auf diese E-Mail.</p>`;
    await getResend().emails.send({ from: "Klangradar <noreply@klangradar.com>", to: claim.verification_email, subject, html });
  } catch (error) {
    console.error("Konnte Claim-Benachrichtigung nicht senden:", error);
  }
}

// Postfach-Eintrag im Veranstalterportal selbst (organizer_notifications,
// siehe 20261201000001) — unabhängig von der E-Mail oben, die z. B. bei
// fehlender verification_email gar nicht verschickt wird. Gleiche
// Nachsichtigkeit: ein Fehler hier darf den Status-Flip nicht gefährden.
async function pushOrganizerNotification(
  supabase: Awaited<ReturnType<typeof createClient>>,
  claim: { entity_type: ClaimableEntityType; entity_id: string; user_id: string },
  outcome: "approved" | "rejected",
) {
  try {
    const names = await resolveEntityNames(supabase, [{ entityType: claim.entity_type, entityId: claim.entity_id }]);
    const name = names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "deine Anfrage";
    await supabase.from("organizer_notifications").insert({
      user_id: claim.user_id,
      organizer_id: claim.entity_type === "organizer" ? claim.entity_id : null,
      type: outcome === "approved" ? "claim_approved" : "claim_rejected",
      title: outcome === "approved" ? `Claim für ${name} genehmigt` : `Claim für ${name} abgelehnt`,
      body:
        outcome === "approved"
          ? `Du kannst ${name} jetzt im Veranstalterportal verwalten.`
          : `Dein Antrag für ${name} wurde abgelehnt.`,
      link_href: "/veranstalter",
    });
  } catch (error) {
    console.error("Konnte Postfach-Benachrichtigung nicht anlegen:", error);
  }
}

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
    .select("entity_type, entity_id, user_id, verification_email")
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
  await notifyClaimant(supabase, claim, "approved");
  await pushOrganizerNotification(supabase, claim, "approved");

  revalidatePath("/entity-claims");
}

export async function rejectEntityClaim(claimId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: claim, error: fetchError } = await supabase
    .from("entity_claims")
    .select("entity_type, entity_id, user_id, verification_email")
    .eq("id", claimId)
    .maybeSingle();
  if (fetchError || !claim) throw new Error(fetchError?.message ?? "Claim nicht gefunden");

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
  await notifyClaimant(supabase, claim, "rejected");
  await pushOrganizerNotification(supabase, claim, "rejected");

  revalidatePath("/entity-claims");
}
