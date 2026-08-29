"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { generateUniqueSlug } from "@/lib/slug";

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

  const justification = String(formData.get("justification") ?? "").trim() || null;

  const { error } = await supabase.from("entity_claims").insert({
    entity_type: "organizer",
    entity_id: organizerId,
    user_id: user.id,
    status: "pending",
    justification,
  });
  if (error) {
    if (error.code === "23505") {
      throw new Error("Du hast für diese Institution bereits eine Anfrage gestellt.");
    }
    throw new Error(error.message);
  }

  revalidatePath("/veranstalter");
  redirect("/veranstalter");
}

// Selbstbedienungs-Neuanlage: legt die organizers-Zeile UND direkt einen
// sofort genehmigten Claim darauf an (RLS-Policy "Ersteller-Claim auf eigene
// neue Institution ist sofort genehmigt" verlangt organizers.created_by =
// auth.uid() — deshalb erst die Zeile mit created_by anlegen, dann den Claim).
export async function createOwnOrganizer(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet");

  const name = String(formData.get("name") ?? "").trim();
  if (!name) throw new Error("Name ist erforderlich");
  const contactEmail = String(formData.get("contact_email") ?? "").trim() || null;
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
    status: "approved",
    role: "owner",
  });
  if (claimError) throw new Error(claimError.message);

  revalidatePath("/veranstalter");
  redirect("/veranstalter");
}
