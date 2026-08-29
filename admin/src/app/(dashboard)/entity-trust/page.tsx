import { createClient } from "@/lib/supabase/server";
import { resolveEntityNames, resolveTrustLevels, type ClaimableEntityType } from "@/lib/entity-tables";
import { TrustList, type UiTrustEntity } from "./trust-list";

export const dynamic = "force-dynamic";

interface ApprovedClaimRow {
  entity_type: ClaimableEntityType;
  entity_id: string;
}

export default async function EntityTrustPage() {
  const supabase = await createClient();

  // Nur Entitäten mit mindestens einem genehmigten Claim sind hier relevant
  // — "unverified" (kein Claim) braucht keine redaktionelle Einstufung.
  const { data, error } = await supabase
    .from("entity_claims")
    .select("entity_type, entity_id")
    .eq("status", "approved")
    .returns<ApprovedClaimRow[]>();

  const claimed = data ?? [];
  const uniqueByKey = new Map<string, { entityType: ClaimableEntityType; entityId: string }>();
  for (const row of claimed) {
    uniqueByKey.set(`${row.entity_type}:${row.entity_id}`, { entityType: row.entity_type, entityId: row.entity_id });
  }
  const refs = Array.from(uniqueByKey.values());

  const [names, levels] = await Promise.all([resolveEntityNames(supabase, refs), resolveTrustLevels(supabase, refs)]);

  const entities: UiTrustEntity[] = refs
    .map((ref) => ({
      entityType: ref.entityType,
      entityId: ref.entityId,
      entityName: names.get(`${ref.entityType}:${ref.entityId}`) ?? "(unbekannt)",
      level: levels.get(`${ref.entityType}:${ref.entityId}`) ?? "claimed",
    }))
    .sort((a, b) => a.entityName.localeCompare(b.entityName, "de"));

  return (
    <div className="p-8">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Verifizierung</h1>
        <p className="mt-1 max-w-xl text-sm text-neutral-500">
          Alle von Veranstaltern beanspruchten Institutionen/Venues/Personen/Ensembles. „Verifiziert“ bzw.
          „Offiziell“ ist eine zusätzliche redaktionelle Einstufung — z.B. nach manueller Prüfung, dass der
          Veranstalter tatsächlich für diese Einrichtung spricht.
        </p>
        <p className="mt-2 text-xs text-neutral-500">{entities.length} beanspruchte Entität(en)</p>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6">
          <TrustList entities={entities} />
        </div>
      )}
    </div>
  );
}
