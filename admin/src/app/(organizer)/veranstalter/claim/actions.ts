"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { generateUniqueSlug } from "@/lib/slug";
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

// Eigenständig statt requestEntityClaim("organizer", ...) wiederzuverwenden:
// Next.js' "use server"-Mechanismus serialisiert exportierte Funktionen
// anhand ihrer Referenz im Quellmodul — ein re-exportierter/gebundener
// Verweis aus einer anderen "use server"-Datei ist hier riskanter als die
// paar Zeilen doppelter Insert-Logik.
export async function requestOrganizerClaim(organizerId: string, formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet");

  const { verificationEmail, evidenceUrl, justification } = claimEvidence(formData);

  const { error } = await supabase.from("entity_claims").insert({
    entity_type: "organizer",
    entity_id: organizerId,
    user_id: user.id,
    status: "pending",
    justification,
    verification_email: verificationEmail,
    evidence_url: evidenceUrl,
  });
  if (error) {
    if (error.code === "23505") {
      throw new Error("Du hast für diese Institution bereits eine Anfrage gestellt.");
    }
    throw new Error(error.message);
  }

  await getResend().emails.send({ from: "Klangradar <noreply@klangradar.com>", to: "redaktion@klangradar.com", subject: "Neue Institution-Claim-Anfrage", html: `<p>Eine Institution-Claim-Anfrage wartet auf Prüfung.</p><p>Antragsteller: ${verificationEmail}</p><p><a href="https://klangradar.com/entity-claims">Im Redaktions-Dashboard öffnen</a></p>` });

  revalidatePath("/veranstalter");
  redirect("/veranstalter");
}

// Selbstbedienungs-Neuanlage: legt die Institution an, aber der Claim bleibt
// bis zur Prüfung durch die Redaktion bewusst offen.
export async function createOwnOrganizer(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet");

  const name = String(formData.get("name") ?? "").trim();
  if (!name) throw new Error("Name ist erforderlich");
  const { verificationEmail, evidenceUrl, justification } = claimEvidence(formData);
  const contactEmail = String(formData.get("contact_email") ?? "").trim() || verificationEmail;
  const websiteUrl = String(formData.get("website_url") ?? "").trim() || null;

  const slug = await generateUniqueSlug(supabase, "organizers", name);
  const { data: organizer, error } = await supabase
    .from("organizers")
    .insert({ name, slug, contact_email: contactEmail, website_url: websiteUrl, created_by: user.id })
    .select("id")
    .single();
  if (error || !organizer) throw new Error(error?.message ?? "Anlegen fehlgeschlagen");

  const { error: claimError } = await supabase.from("entity_claims").insert({
    entity_type: "organizer",
    entity_id: organizer.id,
    user_id: user.id,
    status: "pending",
    justification,
    verification_email: verificationEmail,
    evidence_url: evidenceUrl,
  });
  if (claimError) throw new Error(claimError.message);

  await getResend().emails.send({ from: "Klangradar <noreply@klangradar.com>", to: "redaktion@klangradar.com", subject: "Neue Institution zur Prüfung", html: `<p>Eine neue Institution und ein Claim warten auf Prüfung.</p><p>Antragsteller: ${verificationEmail}</p><p><a href="https://klangradar.com/entity-claims">Im Redaktions-Dashboard öffnen</a></p>` });

  revalidatePath("/veranstalter");
  redirect("/veranstalter");
}
