"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function saveBillingProfile(formData: FormData): Promise<{ error?: string; success?: true }> {
  const field = (name: string, max: number) => String(formData.get(name) ?? "").trim().slice(0, max);
  const name = field("name", 200);
  const street = field("street", 200);
  const zip = field("zip", 20);
  const city = field("city", 120);
  const country = field("country", 80) || "Deutschland";
  const vatId = field("vat_id", 30) || null;
  if (!name || !street || !zip || !city) return { error: "Bitte Name, Straße, PLZ und Ort ausfüllen." };

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Bitte melde dich erneut an." };

  const { error } = await supabase.from("billing_profiles").upsert({
    user_id: user.id, name, street, zip, city, country, vat_id: vatId, updated_at: new Date().toISOString(),
  });
  if (error) return { error: `Die Rechnungsanschrift konnte nicht gespeichert werden: ${error.message}` };
  revalidatePath("/veranstalter/finanzen");
  return { success: true };
}
