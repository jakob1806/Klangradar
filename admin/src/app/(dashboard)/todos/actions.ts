"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function createTodo(formData: FormData) {
  const supabase = await createClient();
  const title = String(formData.get("title") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  if (!title || !description) throw new Error("Titel und Beschreibung sind erforderlich.");

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase.from("todos").insert({
    title,
    description,
    created_by: user?.email ?? user?.id ?? null,
  });
  if (error) throw new Error(error.message);
  revalidatePath("/todos");
}

export async function markTodoDone(todoId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("todos").update({ status: "done", done_at: new Date().toISOString() }).eq("id", todoId);
  if (error) throw new Error(error.message);
  revalidatePath("/todos");
}

export async function reopenTodo(todoId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("todos").update({ status: "open", done_at: null }).eq("id", todoId);
  if (error) throw new Error(error.message);
  revalidatePath("/todos");
}

export async function deleteTodo(todoId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("todos").delete().eq("id", todoId);
  if (error) throw new Error(error.message);
  revalidatePath("/todos");
}
