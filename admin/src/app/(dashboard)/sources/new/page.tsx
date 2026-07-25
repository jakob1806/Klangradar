import { createClient } from "@/lib/supabase/server";
import { createSource } from "../actions";
import { SourceForm, type SourceFormValues } from "../source-form";

export default async function NewSourcePage({
  searchParams,
}: {
  searchParams: Promise<{ url?: string; type?: string }>;
}) {
  const { url, type } = await searchParams;
  const supabase = await createClient();
  const [{ data: venues }, { data: organizers }, { data: persons }, { data: ensembles }] = await Promise.all([
    supabase.from("venues").select("id, name").order("name"),
    supabase.from("organizers").select("id, name").order("name"),
    supabase.from("persons").select("id, full_name").order("full_name"),
    supabase.from("ensembles").select("id, name").order("name"),
  ]);

  // Vorbelegung aus dem Onboarding-Assistenten (/sources/onboard) — der Rest
  // bleibt bewusst leer/Default, der Admin füllt Name/Legal-Basis/Bindung
  // an Venue etc. selbst aus.
  const initial: SourceFormValues | undefined = url
    ? {
        name: "",
        type: type ?? "manual",
        url,
        venue_id: null,
        organizer_id: null,
        person_id: null,
        ensemble_id: null,
        crawl_frequency_minutes: 1440,
        legal_basis: null,
        status: "under_review",
        config: null,
      }
    : undefined;

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Neue Datenquelle</h1>
      <div className="mt-6">
        <SourceForm
          action={createSource}
          initial={initial}
          venues={venues ?? []}
          organizers={organizers ?? []}
          persons={persons ?? []}
          ensembles={ensembles ?? []}
        />
      </div>
    </div>
  );
}
