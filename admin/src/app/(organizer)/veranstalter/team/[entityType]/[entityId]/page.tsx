import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { NAME_COLUMN_FOR_ENTITY_TYPE, TABLE_FOR_ENTITY_TYPE, type ClaimableEntityType } from "@/lib/entity-tables";
import { TeamMemberActions } from "./team-member-actions";

export const dynamic = "force-dynamic";

const VALID_ENTITY_TYPES: ClaimableEntityType[] = ["organizer", "venue", "person", "ensemble"];

const STATUS_LABEL: Record<string, string> = {
  pending: "Offen",
  approved: "Aktiv",
  rejected: "Abgelehnt/Entfernt",
};

interface ClaimRow {
  id: string;
  user_id: string;
  status: "pending" | "approved" | "rejected";
  role: "owner" | "editor";
  justification: string | null;
  created_at: string;
}

export default async function TeamPage({
  params,
}: {
  params: Promise<{ entityType: string; entityId: string }>;
}) {
  const { entityType: rawType, entityId } = await params;
  if (!VALID_ENTITY_TYPES.includes(rawType as ClaimableEntityType)) notFound();
  const entityType = rawType as ClaimableEntityType;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [{ data: entity }, { data: claims }] = await Promise.all([
    supabase
      .from(TABLE_FOR_ENTITY_TYPE[entityType])
      .select("*")
      .eq("id", entityId)
      .maybeSingle(),
    supabase
      .from("entity_claims")
      .select("id, user_id, status, role, justification, created_at")
      .eq("entity_type", entityType)
      .eq("entity_id", entityId)
      .order("created_at", { ascending: true })
      .returns<ClaimRow[]>(),
  ]);

  if (!entity) notFound();
  const entityName = (entity as unknown as Record<string, unknown>)[NAME_COLUMN_FOR_ENTITY_TYPE[entityType]] as string;

  const allClaims = claims ?? [];
  const myClaim = allClaims.find((c) => c.user_id === user!.id);
  if (!myClaim || myClaim.status !== "approved") {
    return (
      <div className="mx-auto max-w-xl px-6 py-16 text-center text-[#48484a]">
        Du hast keinen genehmigten Zugriff auf dieses Team.
      </div>
    );
  }
  const isOwner = myClaim.role === "owner";

  const userIds = [...new Set(allClaims.map((c) => c.user_id))];
  const { data: profiles } = await supabase.from("profiles").select("id, display_name").in("id", userIds);
  const nameByUserId = new Map((profiles ?? []).map((p) => [p.id as string, (p.display_name as string | null) ?? (p.id as string)]));

  const pending = allClaims.filter((c) => c.status === "pending");
  const approved = allClaims.filter((c) => c.status === "approved");
  const rejected = allClaims.filter((c) => c.status === "rejected");

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <h1 className="type-heading mb-1 text-2xl text-[#1d1d1f]">Team — {entityName}</h1>
      <p className="mb-8 text-sm text-[#86868b]">
        {isOwner
          ? "Als Owner kannst du offene Anfragen direkt selbst genehmigen und Rollen anpassen."
          : "Du bist Editor — nur Owner können Team-Mitglieder verwalten."}
      </p>

      {pending.length > 0 && (
        <section className="mb-8">
          <h2 className="mb-3 text-sm font-semibold text-[#86868b]">Offene Anfragen ({pending.length})</h2>
          <TeamTable claims={pending} nameByUserId={nameByUserId} isOwner={isOwner} />
        </section>
      )}

      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-[#86868b]">Aktive Mitglieder ({approved.length})</h2>
        <TeamTable claims={approved} nameByUserId={nameByUserId} isOwner={isOwner} />
      </section>

      {rejected.length > 0 && (
        <section>
          <h2 className="mb-3 text-sm font-semibold text-[#86868b]">Abgelehnt/Entfernt ({rejected.length})</h2>
          <TeamTable claims={rejected} nameByUserId={nameByUserId} isOwner={false} />
        </section>
      )}
    </div>
  );
}

function TeamTable({
  claims,
  nameByUserId,
  isOwner,
}: {
  claims: ClaimRow[];
  nameByUserId: Map<string, string>;
  isOwner: boolean;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white">
      <table className="w-full text-sm">
        <tbody className="divide-y divide-neutral-200">
          {claims.map((claim) => (
            <tr key={claim.id}>
              <td className="px-4 py-3 font-medium text-[#1d1d1f]">{nameByUserId.get(claim.user_id) ?? claim.user_id}</td>
              <td className="px-4 py-3 text-[#86868b]">{claim.role === "owner" ? "Owner" : "Editor"}</td>
              <td className="px-4 py-3 text-[#86868b]">{STATUS_LABEL[claim.status]}</td>
              <td className="px-4 py-3 text-right">{isOwner && <TeamMemberActions claimId={claim.id} status={claim.status} role={claim.role} />}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
