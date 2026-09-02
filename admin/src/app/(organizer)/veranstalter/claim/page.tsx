import { SubmitButton } from "@/components/organizer/submit-button";
import { createOwnOrganizer } from "./actions";
import { ClaimSearch } from "./claim-search";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/organizer/ui/card";
import { Input, Textarea } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";

export const dynamic = "force-dynamic";

// Nutzerfeedback: getrennte Links zu venue/person/ensemble/claim plus eine
// Suche, die NUR Institutionen fand und erst nach "Suchen" reagierte,
// zwangen zu Rätselraten. ClaimSearch bietet jetzt Live-Vorschläge (Debounce
// statt Button) über alle vier find_matching_*-RPCs, inkl. Miniaturbild
// (Venue/Ensemble eckig, Person rund -- siehe Thumbnail in claim-search.tsx).
export default function ClaimOrganizerPage() {
  return (
    <div>
      <PageHeader
        eyebrow="Beanspruchen"
        title="Institution, Venue, Person oder Ensemble beanspruchen"
        description="Suche nach deiner Institution, deinem Veranstaltungsort oder dir/deinem Ensemble. Findest du deine Institution nicht, kannst du sie unten neu anlegen. Jede Anfrage wird mit Nachweis von der Redaktion geprüft, bevor Verwaltungsrechte entstehen."
      />
      <PageBody className="mx-auto flex max-w-2xl flex-col gap-8">
        <ClaimSearch />

        <Card>
          <CardHeader>
            <CardTitle>Nicht gefunden? Neue Institution anlegen</CardTitle>
            <CardDescription>Auch neue Institutionen werden erst nach Prüfung des Nachweises freigeschaltet.</CardDescription>
          </CardHeader>
          <CardContent>
            <form action={createOwnOrganizer} className="flex flex-col gap-4">
              <div className="flex flex-col gap-1.5">
                <Label>
                  Name <span className="text-[#a91551]">*</span>
                </Label>
                <Input type="text" name="name" required />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Kontakt-E-Mail</Label>
                <Input type="email" name="contact_email" />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Website</Label>
                <Input type="url" name="website_url" placeholder="https://…" />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>
                  Geschäftliche E-Mail <span className="text-[#a91551]">*</span>
                </Label>
                <Input type="email" name="verification_email" required placeholder="name@institution.de" />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>
                  Nachweis-Link <span className="text-[#a91551]">*</span>
                </Label>
                <Input type="url" name="evidence_url" required placeholder="https://www.beispiel.de/impressum" />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>
                  Warum bist du berechtigt? <span className="text-[#a91551]">*</span>
                </Label>
                <Textarea name="justification" rows={3} required placeholder="Funktion bei der Institution und Bezug zum Nachweis" />
              </div>
              <div>
                <SubmitButton>Institution anlegen</SubmitButton>
              </div>
            </form>
          </CardContent>
        </Card>
      </PageBody>
    </div>
  );
}
