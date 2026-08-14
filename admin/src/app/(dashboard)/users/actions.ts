"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type AppRole = "admin" | "editor";

export async function assignRole(userId: string, role: AppRole) {
  const supabase = await createClient();
  const { error } = await supabase.from("user_roles").insert({ user_id: userId, role });
  if (error) throw new Error(error.message);

  revalidatePath("/users");
}

export async function removeRole(userId: string, role: AppRole) {
  const supabase = await createClient();

  if (role === "admin") {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user?.id === userId) {
      throw new Error("Du kannst dir nicht selbst die Admin-Rolle entziehen.");
    }
  }

  const { error } = await supabase.from("user_roles").delete().eq("user_id", userId).eq("role", role);
  if (error) throw new Error(error.message);

  revalidatePath("/users");
}

export async function deleteUser(userId: string) {
  if (!/^[0-9a-f-]{36}$/i.test(userId)) throw new Error("Ungueltige Benutzer-ID");
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_delete_user", { p_user_id: userId });
  if (error) throw new Error(error.message);
  revalidatePath("/users");
}
