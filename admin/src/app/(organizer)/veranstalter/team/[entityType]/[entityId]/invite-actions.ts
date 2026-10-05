"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { getResend } from "@/lib/resend";
import { teamInvitationEmail } from "@/lib/team-invitation";

type Role = "owner" | "editor" | "marketing" | "finance";
export type InviteResult = { ok: true; message: string } | { ok: false; error: string };

async function createAndSend(entityType: string, entityId: string, email: string, role: Role): Promise<InviteResult> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("create_team_invitation", { p_entity_type: entityType, p_entity_id: entityId, p_email: email, p_role: role })
    .single<{ id: string; token: string; entity_name: string | null; inviter_name: string | null }>();
  if (error || !data) return { ok: false, error: error?.message ?? "Einladung konnte nicht angelegt werden." };

  const mail = teamInvitationEmail({
    entityName: data.entity_name ?? "dem Team",
    inviterName: data.inviter_name ?? "Ein Teammitglied",
    role,
    token: data.token,
  });
  try {
    await getResend().emails.send({
      from: "Klangradar <noreply@klangradar.com>",
      to: email.trim(),
      subject: mail.subject,
      html: mail.html,
      text: mail.text,
    });
  } catch (sendError) {
    console.error("Einladungs-Mail konnte nicht gesendet werden:", sendError);
    revalidatePath("/veranstalter/team", "layout");
    return {
      ok: false,
      error: "Die Einladung wurde angelegt, aber die E-Mail konnte nicht gesendet werden. Bitte über „Erneut senden“ versuchen.",
    };
  }
  revalidatePath("/veranstalter/team", "layout");
  return { ok: true, message: `Einladung an ${email.trim()} gesendet.` };
}

export async function inviteTeamMember(entityType: string, entityId: string, email: string, role: Role): Promise<InviteResult> {
  return createAndSend(entityType, entityId, email, role);
}

export async function resendTeamInvitation(invitationId: string): Promise<InviteResult> {
  const supabase = await createClient();
  const { data: invitation } = await supabase
    .from("team_invitations")
    .select("entity_type, entity_id, email, role, status")
    .eq("id", invitationId)
    .maybeSingle();
  if (!invitation || invitation.status !== "pending") return { ok: false, error: "Diese Einladung ist nicht mehr offen." };
  return createAndSend(invitation.entity_type, invitation.entity_id, invitation.email, invitation.role as Role);
}

export async function revokeTeamInvitation(invitationId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("revoke_team_invitation", { p_invitation_id: invitationId });
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/team", "layout");
}
