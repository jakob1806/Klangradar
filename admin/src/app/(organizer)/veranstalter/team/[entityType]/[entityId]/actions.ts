"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { getResend } from "@/lib/resend";
import { resolveEntityNames, type ClaimableEntityType } from "@/lib/entity-tables";

// Gleiches Muster wie notifyClaimant in entity-claims/actions.ts: E-Mail-
// Fehler dürfen den bereits erfolgten Status-Wechsel nicht beeinträchtigen.
async function notifyTeamMember(
  supabase: Awaited<ReturnType<typeof createClient>>,
  claim: { entity_type: ClaimableEntityType; entity_id: string; verification_email: string | null },
  outcome: "approved" | "removed",
) {
  if (!claim.verification_email) return;
  try {
    const names = await resolveEntityNames(supabase, [{ entityType: claim.entity_type, entityId: claim.entity_id }]);
    const name = names.get(`${claim.entity_type}:${claim.entity_id}`) ?? "dem Team";
    const subject = outcome === "approved" ? `Team-Zugriff für ${name} freigeschaltet` : `Team-Zugriff für ${name} entzogen`;
    const html =
      outcome === "approved"
        ? `<p>Du hast jetzt Zugriff auf <strong>${name}</strong> im Klangradar-Veranstalterportal.</p><p><a href="https://klangradar.com/veranstalter">Jetzt öffnen</a></p>`
        : `<p>Dein Zugriff auf <strong>${name}</strong> im Klangradar-Veranstalterportal wurde entfernt bzw. deine Anfrage wurde abgelehnt.</p>`;
    await getResend().emails.send({ from: "Klangradar <noreply@klangradar.com>", to: claim.verification_email, subject, html });
  } catch (error) {
    console.error("Konnte Team-Benachrichtigung nicht senden:", error);
  }
}

// Alle drei Aktionen verlassen sich vollständig auf RLS
// ("Owner verwaltet Team-Claims der eigenen Entität", Team-Rechte-Migration)
// für die eigentliche Berechtigungsprüfung — kein doppelter Check hier,
// eine unautorisierte Anfrage bleibt einfach wirkungslos (0 betroffene
// Zeilen) statt einer expliziten Fehlermeldung, das reicht für dieses
// Owner-only-Werkzeug.
export async function approveTeamClaim(claimId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: claim } = await supabase
    .from("entity_claims")
    .select("entity_type, entity_id, verification_email")
    .eq("id", claimId)
    .maybeSingle();
  const { error } = await supabase
    .from("entity_claims")
    .update({ status: "approved", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", claimId);
  if (error) throw new Error(error.message);
  if (claim) await notifyTeamMember(supabase, claim, "approved");
  revalidatePath("/veranstalter/team", "layout");
}

// Dient sowohl zum Ablehnen eines offenen Antrags als auch zum Entfernen
// eines bereits genehmigten Team-Mitglieds — beides ist derselbe
// Status-Übergang nach 'rejected'. Der Last-Owner-Trigger verhindert, dass
// dabei der letzte verbleibende Owner entfernt wird.
export async function rejectTeamClaim(claimId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: claim } = await supabase
    .from("entity_claims")
    .select("entity_type, entity_id, verification_email")
    .eq("id", claimId)
    .maybeSingle();
  const { error } = await supabase
    .from("entity_claims")
    .update({ status: "rejected", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", claimId);
  if (error) throw new Error(error.message);
  if (claim) await notifyTeamMember(supabase, claim, "removed");
  revalidatePath("/veranstalter/team", "layout");
}

export async function setTeamMemberRole(claimId: string, role: "owner" | "editor" | "marketing" | "finance") {
  const supabase = await createClient();
  const { error } = await supabase.from("entity_claims").update({ role }).eq("id", claimId);
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/team", "layout");
}
