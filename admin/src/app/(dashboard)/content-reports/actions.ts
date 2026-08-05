"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// content_reports ändert nie direkt Daten (siehe Migration
// 20261002000013_content_reports.sql) — "Erledigt" heißt nur, die
// Redaktion hat die zugrundeliegende Änderung woanders (Event-/Venue-/
// Personen-Formular) selbst vorgenommen, "Verwerfen" heißt: kein
// Handlungsbedarf (z.B. bereits behoben oder unzutreffend).
export async function resolveContentReport(reportId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("content_reports")
    .update({ status: "resolved", reviewed_at: new Date().toISOString() })
    .eq("id", reportId);
  if (error) throw new Error(error.message);
  revalidatePath("/content-reports");
}

export async function dismissContentReport(reportId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("content_reports")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .eq("id", reportId);
  if (error) throw new Error(error.message);
  revalidatePath("/content-reports");
}
