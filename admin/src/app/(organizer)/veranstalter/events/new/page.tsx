import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { resolveEntityNames } from "@/lib/entity-tables";
import { OrganizerEventForm } from "../../organizer-event-form";
import { createOrganizerEvent } from "../actions";

export const dynamic = "force-dynamic";

export default async function NewOrganizerEventPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [{ data: claims }, { data: genres }] = await Promise.all([
    supabase
      .from("entity_claims")
      .select("entity_id")
      .eq("entity_type", "organizer")
      .eq("user_id", user!.id)
      .eq("status", "approved"),
    supabase.from("genres").select("id, label_de").order("sort_order"),
  ]);

  const organizerIds = (claims ?? []).map((c) => c.entity_id as string);
  if (organizerIds.length === 0) {
    return (
      <div className="mx-auto max-w-xl px-6 py-16 text-center">
        <p className="text-[#48484a]">
          Du hast noch keine genehmigte Institution. Beanspruche zuerst eine bestehende Institution oder
          lege deine eigene an.
        </p>
        <Link href="/veranstalter/claim" className="mt-4 inline-block font-medium text-[#0071e3] hover:underline">
          Jetzt beanspruchen
        </Link>
      </div>
    );
  }

  const names = await resolveEntityNames(
    supabase,
    organizerIds.map((id) => ({ entityType: "organizer" as const, entityId: id })),
  );
  const organizers = organizerIds.map((id) => ({ id, name: names.get(`organizer:${id}`) ?? "(unbekannt)" }));

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <h1 className="type-heading mb-6 text-2xl text-[#1d1d1f]">Neues Event</h1>
      <OrganizerEventForm action={createOrganizerEvent} organizers={organizers} genres={genres ?? []} />
    </div>
  );
}
