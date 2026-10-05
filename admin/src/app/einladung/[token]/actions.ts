"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function acceptInvitation(token: string): Promise<{ error: string } | never> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("accept_team_invitation", { p_token: token });
  if (error) return { error: error.message };
  const row = Array.isArray(data) ? data[0] : data;
  redirect(row?.entity_type && row?.entity_id ? `/veranstalter/team/${row.entity_type}/${row.entity_id}` : "/veranstalter");
}

export async function declineInvitation(token: string): Promise<{ error: string } | never> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("decline_team_invitation", { p_token: token });
  if (error) return { error: error.message };
  redirect(`/einladung/${token}`);
}
