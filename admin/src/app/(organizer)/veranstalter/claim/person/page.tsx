import { EntityClaimSearch } from "../entity-claim-search";

export const dynamic = "force-dynamic";

export default async function ClaimPersonPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  return (
    <EntityClaimSearch
      entityType="person"
      title="Person beanspruchen"
      description="Suche nach deinem eigenen Profil (z.B. als Solist:in oder Dirigent:in)."
      placeholder="Name der Person…"
      query={(q ?? "").trim()}
    />
  );
}
