"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readSourceFields(formData: FormData) {
  // "scrape"/"api" sources need per-site config (CSS selectors, secret-name
  // for auth) that has no dedicated UI — a raw JSON textarea, consistent
  // with how ingest-source/index.ts already treats sources.config as a free
  // jsonb bag (see ScrapeConfig in parsers/scrape.ts and authHeaderEnvVar).
  // Without this, a source created via "Neu anlegen" as type "Scraping"/
  // "API" had NO way to ever get a working config and would fail every run
  // forever ("itemSelector is required").
  const configRaw = String(formData.get("config_json") ?? "").trim();
  let config: Record<string, unknown> = {};
  if (configRaw) {
    try {
      const parsed = JSON.parse(configRaw);
      if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
        throw new Error("Konfiguration muss ein JSON-Objekt sein, z. B. {\"itemSelector\": \"...\"}");
      }
      config = parsed;
    } catch (err) {
      throw new Error(
        `Konfiguration ist kein gültiges JSON: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  return {
    name: String(formData.get("name") ?? "").trim(),
    type: String(formData.get("type") ?? "manual"),
    url: String(formData.get("url") ?? "").trim(),
    venue_id: String(formData.get("venue_id") ?? "") || null,
    organizer_id: String(formData.get("organizer_id") ?? "") || null,
    person_id: String(formData.get("person_id") ?? "") || null,
    ensemble_id: String(formData.get("ensemble_id") ?? "") || null,
    crawl_frequency_minutes: Number(formData.get("crawl_frequency_minutes") ?? 1440),
    legal_basis: String(formData.get("legal_basis") ?? "").trim() || null,
    status: String(formData.get("status") ?? "active"),
    config,
  };
}

export async function createSource(formData: FormData) {
  const f = readSourceFields(formData);
  const supabase = await createClient();
  const { error } = await supabase.from("sources").insert(f);
  if (error) throw new Error(error.message);

  revalidatePath("/sources");
  redirect("/sources");
}

export async function updateSource(sourceId: string, formData: FormData) {
  const f = readSourceFields(formData);
  const supabase = await createClient();
  const { error } = await supabase.from("sources").update(f).eq("id", sourceId);
  if (error) throw new Error(error.message);

  revalidatePath("/sources");
  redirect("/sources");
}

export async function deleteSource(sourceId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("sources").delete().eq("id", sourceId);
  if (error) throw new Error(error.message);

  revalidatePath("/sources");
  redirect("/sources");
}

// Manueller Trigger für einen sofortigen Ingestion-Lauf ("Jetzt ausführen").
// Ruft die deployte Edge Function direkt auf (gleiches Muster wie die
// Flutter-App, die Supabase-RPCs mit dem anon key aufruft und sich auf
// RLS/Rollen-Checks verlässt — die Admin-App hat keinen Zugriff auf den
// service-role key). Kein redirect(): der Trigger soll die aktuelle Seite
// nur neu laden lassen (via revalidatePath), nicht navigieren.
// eslint-disable-next-line @typescript-eslint/no-unused-vars -- form actions must accept FormData as their trailing parameter
export async function runSourceNow(sourceId: string, _formData: FormData) {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  try {
    const res = await fetch(`${baseUrl}/functions/v1/ingest-source`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey ?? "",
        Authorization: `Bearer ${anonKey ?? ""}`,
      },
      body: JSON.stringify({ source_id: sourceId }),
    });
    if (!res.ok) {
      console.error(`ingest-source (${sourceId}) antwortete mit ${res.status}: ${await res.text()}`);
    }
  } catch (err) {
    console.error(`ingest-source (${sourceId}) nicht erreichbar:`, err);
  } finally {
    // Egal ob Erfolg oder Fehlschlag: der neue ingestion_runs-Eintrag bzw.
    // last_run_at der Quelle soll sichtbar werden.
    revalidatePath("/sources");
    revalidatePath(`/sources/${sourceId}`);
  }
}
