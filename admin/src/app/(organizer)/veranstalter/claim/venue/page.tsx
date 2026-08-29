import { EntityClaimSearch } from "../entity-claim-search";

export const dynamic = "force-dynamic";

export default async function ClaimVenuePage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  return (
    <EntityClaimSearch
      entityType="venue"
      title="Venue beanspruchen"
      description="Suche nach deiner Spielstätte, um sie deinem Konto zuzuordnen."
      placeholder="Name der Venue…"
      query={(q ?? "").trim()}
    />
  );
}
