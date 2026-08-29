import { createClient } from "@/lib/supabase/server";
import { resolveEntityNames, type ClaimableEntityType } from "@/lib/entity-tables";
import { ClaimList, type UiClaim } from "./claim-list";

export const dynamic = "force-dynamic";

interface ClaimRow {
  id: string;
  entity_type: ClaimableEntityType;
  entity_id: string;
  user_id: string;
  justification: string | null;
  verification_email: string | null;
  evidence_url: string | null;
  created_at: string;
}

export default async function EntityClaimsPage() {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("entity_claims")
    .select("id, entity_type, entity_id, user_id, justification, verification_email, evidence_url, created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .returns<ClaimRow[]>();

  const claims = data ?? [];

  // entity_claims hat keinen FK je Typ (polymorph über entity_type/entity_id)
  // — kein eingebetteter Join wie bei entity_candidates möglich, deshalb
  // gebündelte Auflösung über resolveEntityNames (siehe @/lib/entity-tables).
  const [entityNames, requesterProfiles] = await Promise.all([
    resolveEntityNames(supabase, claims.map((c) => ({ entityType: c.entity_type, entityId: c.entity_id }))),
    (async () => {
      const userIds = [...new Set(claims.map((c) => c.user_id))];
      if (userIds.length === 0) return new Map<string, string>();
      const { data: profiles } = await supabase.from("profiles").select("id, display_name").in("id", userIds);
      return new Map((profiles ?? []).map((p) => [p.id as string, (p.display_name as string | null) ?? p.id as string]));
    })(),
  ]);

  const uiClaims: UiClaim[] = claims.map((c) => ({
    id: c.id,
    entityType: c.entity_type,
    entityName: entityNames.get(`${c.entity_type}:${c.entity_id}`) ?? "(unbekannt)",
    requesterLabel: requesterProfiles.get(c.user_id) ?? c.user_id,
    justification: c.justification,
    verificationEmail: c.verification_email,
    evidenceUrl: c.evidence_url,
    createdAt: c.created_at,
  }));

  return (
    <div className="p-8">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Veranstalter-Claims</h1>
        <p className="mt-1 max-w-xl text-sm text-neutral-500">
          Anfragen von Veranstaltern, eine bestehende Institution, Venue, Person oder ein Ensemble zu
          verwalten — nach Genehmigung kann der Nutzer eigene Events für diese Entität einreichen bzw. sieht
          sich als deren Verwalter.
        </p>
        <p className="mt-2 text-xs text-neutral-500">{claims.length} offen</p>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Claims nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6">
          <ClaimList claims={uiClaims} />
        </div>
      )}
    </div>
  );
}
