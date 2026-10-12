"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function saveInvoiceSettings(_state: { error?: string; ok?: boolean }, formData: FormData): Promise<{ error?: string; ok?: boolean }> {
  const text = (name: string, max = 200) => {
    const value = String(formData.get(name) ?? "").trim().slice(0, max);
    return value || null;
  };
  const issuerName = text("issuer_name");
  const street = text("issuer_street");
  const zip = text("issuer_zip", 20);
  const city = text("issuer_city", 120);
  if (!issuerName || !street || !zip || !city) return { error: "Name, Straße, PLZ und Ort sind Pflicht." };
  const iban = text("iban", 40)?.replace(/\s+/g, " ").toUpperCase() ?? null;
  const vatRate = Number(String(formData.get("vat_rate") ?? "19").replace(",", "."));
  if (!Number.isFinite(vatRate) || vatRate < 0 || vatRate > 30) return { error: "Bitte einen gültigen USt-Satz angeben." };

  const supabase = await createClient();
  const { error } = await supabase.from("invoice_settings").update({
    issuer_name: issuerName,
    issuer_street: street,
    issuer_zip: zip,
    issuer_city: city,
    issuer_country: text("issuer_country", 80) ?? "Deutschland",
    tax_number: text("tax_number", 40),
    vat_id: text("vat_id", 30),
    iban,
    bic: text("bic", 20),
    email: text("email"),
    phone: text("phone", 40),
    small_business: formData.get("small_business") === "on",
    vat_rate: vatRate,
    updated_at: new Date().toISOString(),
  }).eq("id", 1);
  if (error) return { error: error.message };
  revalidatePath("/invoice-settings");
  return { ok: true };
}
