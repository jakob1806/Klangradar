"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { ClaimableEntityType } from "@/lib/entity-tables";
import { getResend } from "@/lib/resend";

function claimEvidence(formData: FormData) {
  const verificationEmail = String(formData.get("verification_email") ?? "").trim().toLowerCase();
  const evidenceUrl = String(formData.get("evidence_url") ?? "").trim();
  const justification = String(formData.get("justification") ?? "").trim();
  if (!verificationEmail || !/^\S+@\S+\.\S+$/.test(verificationEmail)) throw new Error("Bitte eine gültige geschäftliche E-Mail angeben.");
  try { new URL(evidenceUrl); } catch { throw new Error("Bitte einen gültigen Link zum Nachweis angeben."); }
  if (justification.length < 12) throw new Error("Bitte erläutere kurz deine Berechtigung.");
  return { verificationEmail, evidenceUrl, justification };
}

// Gemeinsame Claim-Anfrage für Venue/Person/Ensemble (und intern auch für
// Organizer, siehe claim/actions.ts) — landet über die RLS-Policy
// "Nutzer beantragt Claim auf bestehende Entität" immer als 'pending' in
// der Redaktionsprüfung (/entity-claims), unabhängig davon, was der Client
// sendet. Letztes Argument ist FormData statt eines einfachen
// justification-Strings, weil dies als per-Zeile gebundene Server Action
// (requestEntityClaim.bind(null, entityType, entityId)) direkt als
// <form action=...> verwendet wird — Next.js ruft den verbleibenden
// Parameter zwingend mit dem FormData des Formulars auf.
export async function requestEntityClaim(entityType: ClaimableEntityType, entityId: string, formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet");

  const { verificationEmail, evidenceUrl, justification } = claimEvidence(formData);

  const { error } = await supabase.from("entity_claims").insert({
    entity_type: entityType,
    entity_id: entityId,
    user_id: user.id,
    status: "pending",
    justification,
    verification_email: verificationEmail,
    evidence_url: evidenceUrl,
  });
  if (error) {
    // unique(entity_type, entity_id, user_id) — derselbe Nutzer hat bereits
    // eine Anfrage (offen oder abgelehnt) für dieselbe Entität gestellt.
    if (error.code === "23505") {
      throw new Error("Du hast für diese Einrichtung bereits eine Anfrage gestellt.");
    }
    throw new Error(error.message);
  }
  await getResend().emails.send({ from: "Klangradar <noreply@klangradar.com>", to: "redaktion@klangradar.com", subject: "Neue Veranstalter-Claim-Anfrage", html: `<p>Eine neue Claim-Anfrage für <strong>${entityType}</strong> wartet auf Prüfung.</p><p>Antragsteller: ${verificationEmail}</p><p><a href="https://klangradar.com/login?redirectTo=%2Fentity-claims">Im Redaktions-Dashboard öffnen</a></p>` });

  revalidatePath("/veranstalter");
  redirect("/veranstalter");
}
