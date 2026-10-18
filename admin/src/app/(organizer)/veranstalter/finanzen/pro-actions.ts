"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createProCheckoutSession, createProPortalSession, getProStatus } from "@/lib/portal-pro";
import { getEventOrganizerOptions } from "../event-organizer-context";

async function origin(): Promise<string> {
  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host");
  const proto = headerList.get("x-forwarded-proto") ?? "https";
  return host ? `${proto}://${host}` : (process.env.NEXT_PUBLIC_APP_URL ?? "https://klangradar.com");
}

/** Abschließen (Checkout) oder, bei bestehendem Abo, Stripe-Kundenportal. */
export async function openPortalPro(formData: FormData): Promise<void> {
  const organizerId = String(formData.get("organizer_id") ?? "");
  const organizer = (await getEventOrganizerOptions()).find((o) => o.id === organizerId);
  if (!organizer) redirect("/veranstalter/finanzen?pro=forbidden");

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const status = await getProStatus(organizerId);
  const base = await origin();

  let target: string | null = null;
  try {
    target = status.active && status.customerId
      ? await createProPortalSession(status.customerId, base)
      : await createProCheckoutSession({ organizerId, organizerName: organizer.name, email: user?.email, origin: base, customerId: status.customerId });
  } catch (cause) {
    console.error("Portal Pro checkout failed", cause);
  }
  redirect(target ?? "/veranstalter/finanzen?pro=error");
}
