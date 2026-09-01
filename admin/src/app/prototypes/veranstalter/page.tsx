import { OrganizerPortalMockup } from "./portal-mockup";

export default async function OrganizerPortalPrototypePage({
  searchParams,
}: {
  searchParams: Promise<{ v?: string }>;
}) {
  const requested = Number((await searchParams).v) || 1;
  return <OrganizerPortalMockup initialVariant={Math.min(Math.max(requested - 1, 0), 2)} />;
}
