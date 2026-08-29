import { EntityClaimSearch } from "../entity-claim-search";

export const dynamic = "force-dynamic";

export default async function ClaimEnsemblePage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  return (
    <EntityClaimSearch
      entityType="ensemble"
      title="Ensemble beanspruchen"
      description="Suche nach deinem Ensemble oder Orchester."
      placeholder="Name des Ensembles…"
      query={(q ?? "").trim()}
    />
  );
}
