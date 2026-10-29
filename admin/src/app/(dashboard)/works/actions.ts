"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readWork(formData: FormData) {
  const number = (name: string) => {
    const value = String(formData.get(name) ?? "").trim();
    return value ? Number(value) : null;
  };
  return {
    title: String(formData.get("title") ?? "").trim(),
    composer_id: String(formData.get("composer_id") ?? "") || null,
    catalog_number: String(formData.get("catalog_number") ?? "").trim() || null,
    key_signature: String(formData.get("key_signature") ?? "").trim() || null,
    composition_year: number("composition_year"),
    duration_minutes: number("duration_minutes"),
    genre: String(formData.get("genre") ?? "").trim() || null,
    instrumentation: String(formData.get("instrumentation") ?? "").trim() || null,
    description_de: String(formData.get("description_de") ?? "").trim() || null,
  };
}

export async function createWork(formData: FormData) {
  const supabase = await createClient();
  const intro = String(formData.get("introduction_de") ?? "").trim() || null;
  const movements = String(formData.get("movements") ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
  const { data, error } = await supabase.from("works").insert({
    ...readWork(formData),
    ...(intro ? { introduction_de: intro, introduction_source: "redaktion" } : {}),
    ...(movements.length ? { movements, movements_source: "redaktion" } : {}),
  }).select("id").single<{ id: string }>();
  if (error) throw new Error(error.message);
  revalidatePath("/works");
  redirect(`/works/${data.id}`);
}

/** Einführung/Satzfolge: geänderte Texte gelten als Redaktionstext und
 * werden von der automatischen Recherche nicht mehr überschrieben. */
async function editorialFields(supabase: Awaited<ReturnType<typeof createClient>>, id: string, formData: FormData) {
  const intro = String(formData.get("introduction_de") ?? "").trim() || null;
  const movements = String(formData.get("movements") ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
  const { data: current } = await supabase.from("works").select("introduction_de, movements").eq("id", id).maybeSingle<{ introduction_de: string | null; movements: string[] | null }>();
  const update: Record<string, unknown> = {};
  if ((current?.introduction_de ?? null) !== intro) {
    update.introduction_de = intro;
    update.introduction_source = intro ? "redaktion" : null;
    update.introduction_source_url = null;
  }
  if (JSON.stringify(current?.movements ?? []) !== JSON.stringify(movements)) {
    update.movements = movements.length ? movements : null;
    update.movements_source = movements.length ? "redaktion" : null;
  }
  return update;
}

export async function updateWork(id: string, formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("works").update({ ...readWork(formData), ...(await editorialFields(supabase, id, formData)) }).eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/works");
  revalidatePath(`/works/${id}`);
}

async function callWorkIntroduction(body: Record<string, unknown>) {
  const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/work-introduction`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
      Authorization: `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? ""}`,
      "x-internal-secret": process.env.INTERNAL_FUNCTION_SECRET ?? "",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Recherche fehlgeschlagen (HTTP ${res.status})`);
  return res.json();
}

/** "Automatisch recherchieren": Wikipedia-Einführung + Satzfolge für ein Werk
 * neu suchen (überschreibt keine Redaktionstexte). */
export async function researchWork(id: string) {
  await callWorkIntroduction({ work_id: id, force: true });
  revalidatePath(`/works/${id}`);
  revalidatePath("/works");
}

/** Recherche für alle noch nicht geprüften Werke anstoßen. Ein Lauf
 * bearbeitet bis zu 40 Werke; der Rest läuft automatisch alle 5 Minuten. */
export async function researchAllWorks() {
  // Im Hintergrund über pg_net anstoßen (wie der 5-Minuten-Cron). Vorher
  // wartete die Server Action auf den ganzen Lauf (bis ~2 Minuten) und lief
  // in den Vercel-Timeout → Fehlerseite (Nutzermeldung 29.10.2026).
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_trigger_work_introductions");
  if (error) throw new Error(error.message);
  revalidatePath("/works");
  revalidatePath("/werkeinfuehrungen");
}
