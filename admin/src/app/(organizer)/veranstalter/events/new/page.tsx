import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { OrganizerEventForm } from "../../organizer-event-form";
import { createOrganizerEvent } from "../actions";
import { getEventOrganizerOptions } from "../../event-organizer-context";

export const dynamic = "force-dynamic";

export default async function NewOrganizerEventPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [organizers, { data: genres }] = await Promise.all([
    getEventOrganizerOptions(),
    supabase.from("genres").select("id, label_de").order("sort_order"),
  ]);
  if (organizers.length === 0) {
    return (
      <div className="mx-auto max-w-xl px-6 py-16 text-center">
        <p className="text-[#48484a]">
          Du hast noch kein genehmigtes Profil. Beanspruche zuerst eine Institution, Venue, Person oder ein Ensemble.
        </p>
        <Link href="/veranstalter/claim" className="mt-4 inline-block font-medium text-[#0071e3] hover:underline">
          Jetzt beanspruchen
        </Link>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <h1 className="type-heading mb-6 text-2xl text-[#1d1d1f]">Neues Event</h1>
      <OrganizerEventForm action={createOrganizerEvent} organizers={organizers} genres={genres ?? []} />
    </div>
  );
}
