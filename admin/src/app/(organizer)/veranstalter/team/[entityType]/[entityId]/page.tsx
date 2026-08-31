import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { NAME_COLUMN_FOR_ENTITY_TYPE, TABLE_FOR_ENTITY_TYPE, type ClaimableEntityType } from "@/lib/entity-tables";
import { TeamMemberActions } from "./team-member-actions";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Table, TableBody, TableRow, TableCell } from "@/components/organizer/ui/table";

export const dynamic = "force-dynamic";

const VALID_ENTITY_TYPES: ClaimableEntityType[] = ["organizer", "venue", "person", "ensemble"];

const STATUS_LABEL: Record<string, string> = {
  pending: "Offen",
  approved: "Aktiv",
  rejected: "Abgelehnt/Entfernt",
};

const ROLE_LABEL: Record<string, string> = {
  owner: "Admin / Owner",
  editor: "Redaktion",
  marketing: "Marketing",
  finance: "Finanzen",
};

interface ClaimRow {
  id: string;
  user_id: string;
  status: "pending" | "approved" | "rejected";
  role: "owner" | "editor" | "marketing" | "finance";
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
      <div className="mx-auto max-w-xl px-6 py-16 text-center text-[#726c78]">
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
    <div>
      <PageHeader
        eyebrow="Team"
        title={`Team — ${entityName}`}
        description={
          isOwner
            ? "Als Owner kannst du offene Anfragen direkt selbst genehmigen und Rollen passend zu Redaktion, Marketing oder Finanzen vergeben."
            : `Deine Rolle: ${ROLE_LABEL[myClaim.role] ?? myClaim.role}. Nur Owner können Team-Mitglieder verwalten.`
        }
      />
      <PageBody className="mx-auto flex max-w-3xl flex-col gap-8">
        {pending.length > 0 && (
          <section className="flex flex-col gap-3">
            <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Offene Anfragen ({pending.length})</h2>
            <TeamTable claims={pending} nameByUserId={nameByUserId} isOwner={isOwner} />
          </section>
        )}

        <section className="flex flex-col gap-3">
          <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Aktive Mitglieder ({approved.length})</h2>
          <TeamTable claims={approved} nameByUserId={nameByUserId} isOwner={isOwner} />
        </section>

        {rejected.length > 0 && (
          <section className="flex flex-col gap-3">
            <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Abgelehnt/Entfernt ({rejected.length})</h2>
            <TeamTable claims={rejected} nameByUserId={nameByUserId} isOwner={false} />
          </section>
        )}
      </PageBody>
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
  if (claims.length === 0) {
    return (
      <Card>
        <CardContent className="pt-5 text-sm text-[#726c78]">Keine Einträge.</CardContent>
      </Card>
    );
  }

  return (
    <Table>
      <TableBody>
        {claims.map((claim) => (
          <TableRow key={claim.id}>
            <TableCell className="font-medium">{nameByUserId.get(claim.user_id) ?? claim.user_id}</TableCell>
            <TableCell className="text-[#726c78]">{ROLE_LABEL[claim.role] ?? claim.role}</TableCell>
            <TableCell className="text-[#726c78]">{STATUS_LABEL[claim.status]}</TableCell>
            <TableCell className="text-right">{isOwner && <TeamMemberActions claimId={claim.id} status={claim.status} role={claim.role} />}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
