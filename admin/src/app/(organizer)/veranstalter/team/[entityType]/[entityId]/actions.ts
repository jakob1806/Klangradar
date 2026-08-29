"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

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
  const { error } = await supabase
    .from("entity_claims")
    .update({ status: "approved", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", claimId);
  if (error) throw new Error(error.message);
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
  const { error } = await supabase
    .from("entity_claims")
    .update({ status: "rejected", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", claimId);
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/team", "layout");
}

export async function setTeamMemberRole(claimId: string, role: "owner" | "editor") {
  const supabase = await createClient();
  const { error } = await supabase.from("entity_claims").update({ role }).eq("id", claimId);
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/team", "layout");
}
