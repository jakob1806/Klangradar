"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

const text = (formData: FormData, key: string) => String(formData.get(key) ?? "").trim() || null;

export async function createAffiliateRule(formData: FormData): Promise<void> {
  const host = text(formData, "host_suffix")?.toLowerCase().replace(/^https?:\/\//, "").replace(/^www\./, "").replace(/\/.*$/, "");
  const template = text(formData, "url_template");
  const paramsRaw = text(formData, "append_params");
  const params = Object.fromEntries(
    (paramsRaw ?? "").split("&").map((pair) => pair.split("=").map((part) => part.trim())).filter(([key, value]) => key && value),
  );
  if (!host || (!template && !Object.keys(params).length)) return;
  if (template && !template.includes("{url}")) return;
  const supabase = await createClient();
  await supabase.from("affiliate_rules").insert({ label: text(formData, "label") ?? host, host_suffix: host, url_template: template, append_params: params });
  revalidatePath("/partner");
}

export async function createPartnerOffer(formData: FormData): Promise<void> {
  const partner = text(formData, "partner_name");
  const title = text(formData, "title");
  if (!partner || !title) return;
  const supabase = await createClient();
  await supabase.from("partner_offers").insert({
    partner_name: partner,
    title,
    description: text(formData, "description"),
    code: text(formData, "code"),
    url: text(formData, "url"),
    valid_until: text(formData, "valid_until"),
  });
  revalidatePath("/partner");
}

export async function toggleActive(formData: FormData): Promise<void> {
  const table = String(formData.get("table"));
  if (table !== "affiliate_rules" && table !== "partner_offers") return;
  const supabase = await createClient();
  await supabase.from(table).update({ active: formData.get("active") === "true" }).eq("id", String(formData.get("id")));
  revalidatePath("/partner");
}
