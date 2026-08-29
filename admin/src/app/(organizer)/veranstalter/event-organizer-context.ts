import { resolveEntityNames, type ClaimableEntityType } from "@/lib/entity-tables";
import { createClient } from "@/lib/supabase/server";

export async function getEventOrganizerOptions() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];

  const { data: claims } = await supabase
    .from("entity_claims")
    .select("entity_id, entity_type")
    .eq("user_id", user.id)
    .eq("status", "approved");
  const approved = claims ?? [];
  const directOrganizerIds = approved
    .filter((claim) => claim.entity_type === "organizer")
    .map((claim) => claim.entity_id as string);
  const profileClaims = approved.filter((claim) => ["person", "ensemble", "venue"].includes(claim.entity_type));

  const generatedIds = (await Promise.all(profileClaims.map(async (claim) => {
    const { data, error } = await supabase.rpc("ensure_profile_event_organizer_context", {
      p_entity_type: claim.entity_type,
      p_entity_id: claim.entity_id,
    });
    if (error) throw new Error(error.message);
    return data as string;
  }))).filter(Boolean);

  const ids = [...new Set([...directOrganizerIds, ...generatedIds])];
  const names = await resolveEntityNames(supabase, ids.map((entityId) => ({ entityType: "organizer" as ClaimableEntityType, entityId })));
  return ids.map((id) => ({ id, name: names.get(`organizer:${id}`) ?? "(unbekannt)" }));
}
