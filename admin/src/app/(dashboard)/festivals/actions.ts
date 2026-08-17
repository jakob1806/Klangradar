"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

function readFestivalFields(formData: FormData) {
  return {
    name: String(formData.get("name") ?? "").trim(),
    slug: String(formData.get("slug") ?? "").trim(),
    description_de: String(formData.get("description_de") ?? "").trim() || null,
    organizer_id: String(formData.get("organizer_id") ?? "").trim() || null,
    recurring: formData.get("recurring") === "on",
    website_url: String(formData.get("website_url") ?? "").trim() || null,
    photo_url: String(formData.get("photo_url") ?? "").trim() || null,
    start_date: String(formData.get("start_date") ?? "").trim() || null,
    end_date: String(formData.get("end_date") ?? "").trim() || null,
  };
}

export async function createFestival(formData: FormData) {
  const supabase = await createClient();
  const payload = readFestivalFields(formData);

  const { data, error } = await supabase.from("festivals").insert(payload).select("id").single();
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "festival",
    entityId: data.id,
    action: "created",
    actor: user?.email ?? user?.id ?? "unknown",
    after: payload,
  });

  revalidatePath("/festivals");
  redirect("/festivals");
}

export async function updateFestival(festivalId: string, formData: FormData) {
  const supabase = await createClient();
  const payload = readFestivalFields(formData);

  const { error } = await supabase.from("festivals").update(payload).eq("id", festivalId);
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "festival",
    entityId: festivalId,
    action: "updated",
    actor: user?.email ?? user?.id ?? "unknown",
    after: payload,
  });

  revalidatePath("/festivals");
  redirect("/festivals");
}

export async function deleteFestival(festivalId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("festivals").delete().eq("id", festivalId);
  if (error) throw new Error(error.message);

  revalidatePath("/festivals");
  redirect("/festivals");
}
