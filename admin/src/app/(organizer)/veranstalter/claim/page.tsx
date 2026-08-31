import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import { requestOrganizerClaim, createOwnOrganizer } from "./actions";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/organizer/ui/card";
import { Input, Textarea } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { Button } from "@/components/organizer/ui/button";

export const dynamic = "force-dynamic";

interface OrganizerMatch {
  id: string;
  name: string;
}

export default async function ClaimOrganizerPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  const query = (q ?? "").trim();
  const supabase = await createClient();

  let results: OrganizerMatch[] = [];
  if (query) {
    const { data } = await supabase.rpc("find_matching_organizer", {
      p_name: query,
      p_similarity_threshold: 0.3,
      p_result_limit: 10,
    });
    results = ((data ?? []) as { id: string; name: string }[]).map((r) => ({ id: r.id, name: r.name }));
  }

  return (
    <div>
      <PageHeader
        eyebrow="Beanspruchen"
        title="Institution beanspruchen"
        description="Suche nach deiner Institution/deinem Veranstalter. Findest du sie nicht, kannst du sie unten neu anlegen. Jede Anfrage wird mit Nachweis von der Redaktion geprüft, bevor Verwaltungsrechte entstehen."
      />
      <PageBody className="mx-auto flex max-w-2xl flex-col gap-8">
        <div className="flex gap-4 text-sm">
          <Link href="/veranstalter/claim/venue" className="font-semibold text-[#2D2A6E] hover:underline">
            Venue beanspruchen →
          </Link>
          <Link href="/veranstalter/claim/person" className="font-semibold text-[#2D2A6E] hover:underline">
            Person beanspruchen →
          </Link>
          <Link href="/veranstalter/claim/ensemble" className="font-semibold text-[#2D2A6E] hover:underline">
            Ensemble beanspruchen →
          </Link>
        </div>

        <form method="get" className="flex gap-2">
          <Input type="search" name="q" defaultValue={query} placeholder="Name der Institution…" className="flex-1" />
          <Button type="submit" variant="outline">
            Suchen
          </Button>
        </form>

        {query && (
          <div>
            {results.length > 0 ? (
              <div className="flex flex-col gap-4">
                {results.map((r) => (
                  <Card key={r.id}>
                    <CardHeader>
                      <CardTitle>{r.name}</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <form action={requestOrganizerClaim.bind(null, r.id)} className="grid gap-3 sm:grid-cols-2">
                        <div className="flex flex-col gap-1.5">
                          <Label>
                            Geschäftliche E-Mail <span className="text-[#a91551]">*</span>
                          </Label>
                          <Input name="verification_email" type="email" required placeholder="name@institution.de" />
                        </div>
                        <div className="flex flex-col gap-1.5">
                          <Label>
                            Nachweis-Link <span className="text-[#a91551]">*</span>
                          </Label>
                          <Input name="evidence_url" type="url" required placeholder="https://www.beispiel.de/impressum" />
                        </div>
                        <div className="flex flex-col gap-1.5 sm:col-span-2">
                          <Label>
                            Warum bist du berechtigt? <span className="text-[#a91551]">*</span>
                          </Label>
                          <Textarea name="justification" rows={2} required placeholder="Funktion bei der Institution und Bezug zum Nachweis" />
                        </div>
                        <div className="sm:col-span-2">
                          <SubmitButton pendingLabel="Sende…">Mit Nachweis beantragen</SubmitButton>
                        </div>
                      </form>
                    </CardContent>
                  </Card>
                ))}
              </div>
            ) : (
              <p className="text-sm text-[#726c78]">Keine Treffer für „{query}“.</p>
            )}
          </div>
        )}

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
                <Input type="text" name="name" required defaultValue={query} />
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
