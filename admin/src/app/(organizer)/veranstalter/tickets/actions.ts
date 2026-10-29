"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/components/organizer/action-form";

function parsePrice(value: FormDataEntryValue | null): number | null | "invalid" {
  const raw = String(value ?? "").trim().replace(",", ".");
  if (!raw) return null;
  const number = Number(raw);
  return Number.isFinite(number) && number >= 0 && number < 10000 ? number : "invalid";
}

// Erstellt von Claude Code (29.10.2026): Ticket-Link und Preise schnell
// nachtragen. RLS lässt nur Termine durch, die der Nutzer bearbeiten darf.
export async function saveTicketDetails(eventId: string, _state: ActionResult, formData: FormData): Promise<ActionResult> {
  const ticketUrl = String(formData.get("ticket_url") ?? "").trim();
  if (ticketUrl && !/^https?:\/\//i.test(ticketUrl)) return { error: "Der Ticket-Link muss mit http:// oder https:// beginnen." };
  const isFree = formData.get("is_free") === "on";
  const priceMin = parsePrice(formData.get("price_min"));
  const priceMax = parsePrice(formData.get("price_max"));
  if (priceMin === "invalid" || priceMax === "invalid") return { error: "Bitte Preise als Zahl in Euro angeben." };
  if (priceMin !== null && priceMax !== null && priceMax < priceMin) return { error: "Der Höchstpreis ist kleiner als der Mindestpreis." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("events")
    .update({
      ticket_url: ticketUrl || null,
      is_free: isFree,
      price_min: isFree ? null : priceMin,
      price_max: isFree ? null : priceMax,
    })
    .eq("id", eventId)
    .select("id");
  if (error) return { error: error.message };
  if (!data?.length) return { error: "Dieser Termin kann von deinem Konto nicht bearbeitet werden." };
  revalidatePath("/veranstalter/tickets");
  return { success: "Gespeichert." };
}
