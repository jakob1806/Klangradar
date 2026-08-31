import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import { requestEntityClaim } from "./entity-claim-actions";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/organizer/ui/card";
import { Input, Textarea } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { Button } from "@/components/organizer/ui/button";

type SearchableEntityType = "venue" | "person" | "ensemble";

// Alle drei RPCs teilen dieselbe Signatur (p_name, p_similarity_threshold,
// p_result_limit) und liefern id + similarity zurück — einzig die
// Namensspalte unterscheidet sich (persons.full_name vs. venues/ensembles.name).
const RPC_FOR_ENTITY_TYPE: Record<SearchableEntityType, string> = {
  venue: "find_matching_venue",
  person: "find_matching_person",
  ensemble: "find_matching_ensemble",
};
const NAME_KEY_FOR_ENTITY_TYPE: Record<SearchableEntityType, string> = {
  venue: "name",
  person: "full_name",
  ensemble: "name",
};

// Genau EINE gemeinsame Such+Beanspruchen-UI für Venue/Person/Ensemble statt
// dreier fast identischer Seiten — im Unterschied zu Organizer (claim/page.tsx)
// gibt es hier bewusst KEINE Selbstbedienungs-Neuanlage (siehe Plan: "Kein
// 'nicht gefunden'-Formular — stattdessen statischer Hinweis, die Redaktion
// zu kontaktieren").
export async function EntityClaimSearch({
  entityType,
  title,
  description,
  placeholder,
  query,
}: {
  entityType: SearchableEntityType;
  title: string;
  description: string;
  placeholder: string;
  query: string;
}) {
  const supabase = await createClient();

  let results: { id: string; name: string }[] = [];
  if (query) {
    const { data } = await supabase.rpc(RPC_FOR_ENTITY_TYPE[entityType], {
      p_name: query,
      p_similarity_threshold: 0.3,
      p_result_limit: 10,
    });
    const nameKey = NAME_KEY_FOR_ENTITY_TYPE[entityType];
    results = ((data ?? []) as Record<string, unknown>[]).map((row) => ({
      id: row.id as string,
      name: row[nameKey] as string,
    }));
  }

  return (
    <div>
      <PageHeader eyebrow="Beanspruchen" title={title} description={description} />
      <PageBody className="mx-auto flex max-w-2xl flex-col gap-8">
        <form method="get" className="flex gap-2">
          <Input type="search" name="q" defaultValue={query} placeholder={placeholder} className="flex-1" />
          <Button type="submit" variant="outline">
            Suchen
          </Button>
        </form>

        {query &&
          (results.length > 0 ? (
            <div className="flex flex-col gap-4">
              {results.map((r) => (
                <Card key={r.id}>
                  <CardHeader>
                    <CardTitle>{r.name}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <form action={requestEntityClaim.bind(null, entityType, r.id)} className="grid gap-3 sm:grid-cols-2">
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
            <p className="text-sm text-[#726c78]">
              Keine Treffer für „{query}“. Bitte kontaktiere die Redaktion, falls die Einrichtung fehlt.
            </p>
          ))}
      </PageBody>
    </div>
  );
}
