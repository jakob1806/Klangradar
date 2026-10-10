import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { INVITE_ROLE_DESCRIPTION, INVITE_ROLE_LABEL } from "@/lib/team-invitation";
import { InvitationButtons } from "./invitation-actions";
import { DeclineOnlyButton as InvitationDeclineOnly } from "./decline-only";

export const dynamic = "force-dynamic";

interface InvitationInfo {
  entity_type: string;
  entity_id: string;
  entity_name: string | null;
  role: string;
  status: "pending" | "accepted" | "declined" | "revoked";
  expired: boolean;
  inviter_name: string | null;
  email_hint: string;
}

// Eigene Landingpage für eingeladene Personen (kein Portal-Chrome, da die
// Person noch kein Mitglied ist). Zugang über das Token in der URL; zum
// Annehmen ist ein Login mit der eingeladenen Adresse nötig.
export default async function InvitationPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const supabase = await createClient();
  const [{ data: user }, { data: rows }] = await Promise.all([
    supabase.auth.getUser().then((r) => ({ data: r.data.user })),
    supabase.rpc("get_team_invitation", { p_token: token }),
  ]);
  const invitation = (rows as unknown as InvitationInfo[] | null)?.[0];
  const loginHref = `/login?redirectTo=${encodeURIComponent(`/einladung/${token}`)}`;

  return (
    <div className="flex min-h-screen items-center justify-center bg-white px-4 py-12">
      <div className="w-full max-w-lg">
        <div className="mb-6 flex items-center gap-2.5 px-1">
          <Image src="/app-logo.svg" alt="Klangradar" width={36} height={36} className="rounded-[10px]" />
          <span className="flex flex-col leading-none">
            <span className="text-[17px] font-extrabold tracking-tight text-[#111111]">Klangradar</span>
            <span className="text-[11px] text-[#8A8A8A]">Veranstalter-Portal</span>
          </span>
        </div>

        <div className="rounded-3xl border border-[#111111]/[0.06] bg-white p-8 shadow-[0_1px_2px_rgba(0,0,0,0.03)]">
          {!invitation ? (
            <Message title="Einladung nicht gefunden" text="Dieser Link ist ungültig. Bitte prüfe, ob du den vollständigen Link aus der E-Mail verwendet hast." />
          ) : invitation.status === "accepted" ? (
            <Message
              title="Einladung bereits angenommen"
              text={`Du bist Mitglied im Team von „${invitation.entity_name}“.`}
              action={{ href: "/veranstalter", label: "Zum Veranstalterportal" }}
            />
          ) : invitation.status === "declined" ? (
            <Message title="Einladung abgelehnt" text="Du hast diese Einladung abgelehnt. Falls das ein Versehen war, bitte die einladende Person um eine neue Einladung." />
          ) : invitation.status === "revoked" ? (
            <Message title="Einladung zurückgezogen" text="Diese Einladung wurde von der einladenden Person zurückgezogen." />
          ) : invitation.expired ? (
            <Message title="Einladung abgelaufen" text="Diese Einladung ist nicht mehr gültig. Bitte die einladende Person, dir eine neue zu senden." />
          ) : (
            <>
              <span className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#2D2A6E]">Einladung ins Team</span>
              <h1 className="mt-2 text-[1.7rem] font-extrabold leading-tight tracking-tight text-[#111111]">
                Du wurdest zu „{invitation.entity_name}“ eingeladen
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-[#52525B]">
                <strong className="text-[#111111]">{invitation.inviter_name ?? "Ein Teammitglied"}</strong> möchte dich als Teammitglied im
                Klangradar-Veranstalterportal hinzufügen.
              </p>
              <div className="mt-5 rounded-2xl bg-[#FAFAFA] px-5 py-4">
                <div className="text-[11px] font-bold uppercase tracking-wider text-[#8A8A8A]">Deine Rolle</div>
                <div className="mt-0.5 text-[15px] font-bold text-[#111111]">{INVITE_ROLE_LABEL[invitation.role] ?? invitation.role}</div>
                <div className="text-[13px] text-[#6B6B6B]">{INVITE_ROLE_DESCRIPTION[invitation.role]}</div>
              </div>
              <div className="mt-6">
                {user ? (
                  <>
                    <p className="mb-3 text-[13px] text-[#6B6B6B]">
                      Angemeldet als <strong className="text-[#111111]">{user.email}</strong>. Die Einladung gilt für {invitation.email_hint}.
                    </p>
                    <InvitationButtons token={token} />
                  </>
                ) : (
                  <>
                    <p className="mb-3 text-[13px] text-[#6B6B6B]">
                      Melde dich mit {invitation.email_hint} an (per E-Mail-Code, auch ohne bestehendes Konto), um die Einladung anzunehmen.
                    </p>
                    <Link
                      href={loginHref}
                      className="flex h-12 items-center justify-center rounded-full bg-[#2D2A6E] px-6 text-[15px] font-bold text-white transition hover:bg-[#38358a]"
                    >
                      Anmelden und annehmen
                    </Link>
                    <div className="mt-3">
                      <InvitationDeclineOnly token={token} />
                    </div>
                  </>
                )}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function Message({ title, text, action }: { title: string; text: string; action?: { href: string; label: string } }) {
  return (
    <div className="flex flex-col gap-3">
      <h1 className="text-[1.5rem] font-extrabold tracking-tight text-[#111111]">{title}</h1>
      <p className="text-[15px] leading-relaxed text-[#52525B]">{text}</p>
      {action && (
        <Link href={action.href} className="mt-2 flex h-12 items-center justify-center rounded-full bg-[#2D2A6E] px-6 text-[15px] font-bold text-white hover:bg-[#38358a]">
          {action.label}
        </Link>
      )}
    </div>
  );
}

