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
  revalidatePath("/content-reports-native");
}

export async function dismissContentReport(reportId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("content_reports")
    .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
    .eq("id", reportId);
  if (error) throw new Error(error.message);
  revalidatePath("/content-reports");
  revalidatePath("/content-reports-native");
}

export interface AutoFixResult {
  status: "fixed" | "needs_manual_review" | "error" | "code_bug_suspected";
  diagnosis: string;
}

function functionsUrl(path: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${path}`;
}

function authHeaders() {
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  return {
    "Content-Type": "application/json",
    apikey: anonKey,
    Authorization: `Bearer ${anonKey}`,
  };
}

/** Nutzerwunsch: "baue ein, dass von nutzer gemeldete fehler automatisch
 * (und auf button befehl) gefixxt und behoben werden" — später präzisiert:
 * "ich möchte, dass alle nutzer meldungen, wenn vom admin so veranlasst
 * komplett gefixt werden. auch wenn es in deinen augen risky ist." Ruft
 * die Edge Function auto-fix-content-report gezielt für EINE Meldung auf
 * mit adminInitiated=true — das schaltet dort auch die riskanteren Fixes
 * frei (neue Mitwirkende/Werke anlegen), die der unbeaufsichtigte
 * Cron-Lauf bewusst NICHT macht (siehe dortiger Datei-Kommentar). Übergeht
 * außerdem die "schon mal versucht"-Sperre, die nur der Cron-Lauf beachtet.
 *
 * `retry`: Nutzerwunsch "bei erneut versuchen soll einfach eine KI diese
 * fehler durchgehen und beheben. das ist dann wie, als würde ich dir eine
 * chatnachricht mit der fehlerkorrektur schreiben" — schaltet in der Edge
 * Function auf den freieren fixFreeform-Pfad um (kein Zitat-Zwang mehr,
 * volle Entität + bisheriger Verlauf als Kontext). Wird vom Button nur beim
 * "Erneut versuchen" (also alreadyTried=true) gesetzt, nie beim allerersten
 * Klick. */
export async function autoFixContentReport(reportId: string, retry = false): Promise<AutoFixResult> {
  const res = await fetch(functionsUrl("auto-fix-content-report"), {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ reportId, adminInitiated: true, retry }),
  });
  const data = await res.json().catch(() => null);
  if (!res.ok || !data?.results?.[0]) {
    throw new Error(data?.error ?? "Automatischer Fix fehlgeschlagen.");
  }
  revalidatePath("/content-reports");
  revalidatePath("/content-reports-native");
  return { status: data.results[0].status, diagnosis: data.results[0].diagnosis };
}

/** Sammel-Variante ohne reportId — verarbeitet bis zu `limit` noch nie
 * versuchte offene Meldungen, ebenfalls mit adminInitiated=true (ein
 * Klick auf diesen Button ist genauso ein bewusster Admin-Auftrag wie der
 * Einzel-Fix, nur für mehrere Meldungen auf einmal). */
export async function autoFixAllPendingReports(limit = 10): Promise<{ processed: number }> {
  const res = await fetch(functionsUrl("auto-fix-content-report"), {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ limit, adminInitiated: true }),
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) throw new Error(data?.error ?? "Automatischer Fix fehlgeschlagen.");
  revalidatePath("/content-reports");
  return { processed: data?.processed ?? 0 };
}
