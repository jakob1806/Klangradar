import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { OrganizerEventForm } from "../../organizer-event-form";
import { createOrganizerEvent } from "../actions";
import { getEventOrganizerOptions } from "../../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";

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
      <div>
        <PageHeader eyebrow="Events" title="Neues Event" />
        <PageBody>
          <Card>
            <CardContent className="flex flex-col items-center gap-3 pt-5 text-center">
              <p className="text-[#4a4550]">
                Du hast noch kein genehmigtes Profil. Beanspruche zuerst eine Institution, Venue, Person oder ein Ensemble.
              </p>
              <Link href="/veranstalter/claim" className="font-semibold text-[#2D2A6E] hover:underline">
                Jetzt beanspruchen
              </Link>
            </CardContent>
          </Card>
        </PageBody>
      </div>
    );
  }

  return (
    <div>
      <PageHeader eyebrow="Events" title="Neues Event" />
      <PageBody>
        <OrganizerEventForm action={createOrganizerEvent} organizers={organizers} genres={genres ?? []} />
      </PageBody>
    </div>
  );
}
