import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { getEventOrganizerOptions } from "../event-organizer-context";

export const dynamic = "force-dynamic";

// Einstiegsseite für den neuen Nav-Punkt "Team" — ein Nutzer kann mehrere
// Institutionen verwalten (mehrere approved entity_claims), deshalb erst
// auswählen, welche Team-Seite (team/[entityType]/[entityId]) gemeint ist,
// statt direkt zu raten. Nutzt denselben Helper wie Dashboard/Analytics.
export default async function TeamIndexPage() {
  const organizers = await getEventOrganizerOptions();

  return (
    <div>
      <PageHeader eyebrow="Team" title="Mitglieder & Rollen" description="Verwalte, wer in deinem Namen Events und Marketing bearbeiten darf." />
      <PageBody className="mx-auto max-w-3xl">
        {organizers.length === 0 ? (
          <Card>
            <CardContent className="pt-5 text-sm text-[#726c78]">
              Du verwaltest aktuell keine Institution. Unter Beanspruchen kannst du eine bestehende Institution beanspruchen oder
              eine neue anlegen.
            </CardContent>
          </Card>
        ) : (
          <div className="flex flex-col gap-2">
            {organizers.map((organizer) => (
              <Link key={organizer.id} href={`/veranstalter/team/organizer/${organizer.id}`}>
                <Card className="transition hover:border-[#7d1a3a]/30">
                  <CardContent className="flex items-center justify-between pt-5">
                    <span className="text-sm font-semibold text-[#15131a]">{organizer.name}</span>
                    <span className="flex items-center gap-1 text-sm font-semibold text-[#7d1a3a]">
                      Team verwalten <ArrowRight className="size-3.5" />
                    </span>
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>
        )}
      </PageBody>
    </div>
  );
}
