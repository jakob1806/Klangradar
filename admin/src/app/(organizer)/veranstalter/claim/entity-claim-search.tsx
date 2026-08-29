import { createClient } from "@/lib/supabase/server";
import { TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { requestEntityClaim } from "./entity-claim-actions";

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
    <div className="mx-auto max-w-2xl px-6 py-10">
      <h1 className="type-heading mb-2 text-2xl text-[#1d1d1f]">{title}</h1>
      <p className="mb-6 text-sm text-[#86868b]">{description}</p>

      <form method="get" className="mb-6 flex gap-2">
        <TextInput type="search" name="q" defaultValue={query} placeholder={placeholder} className="flex-1" />
        <button
          type="submit"
          className="rounded-lg border border-black/10 px-4 py-2 text-sm font-medium text-neutral-700 hover:bg-black/[0.04]"
        >
          Suchen
        </button>
      </form>

      {query &&
        (results.length > 0 ? (
          <ul className="divide-y divide-neutral-200 overflow-hidden rounded-xl border border-black/[0.06] bg-white">
            {results.map((r) => (
              <li key={r.id} className="flex items-center justify-between px-4 py-3">
                <span className="font-medium text-[#1d1d1f]">{r.name}</span>
                <form action={requestEntityClaim.bind(null, entityType, r.id)}>
                  <SubmitButton pendingLabel="Sende…">Beanspruchen</SubmitButton>
                </form>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-[#86868b]">
            Keine Treffer für „{query}“. Bitte kontaktiere die Redaktion, falls die Einrichtung fehlt.
          </p>
        ))}
    </div>
  );
}
