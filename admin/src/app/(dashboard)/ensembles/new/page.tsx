import { createClient } from "@/lib/supabase/server";
import { createEnsemble } from "../actions";
import { EnsembleForm } from "../ensemble-form";

export default async function NewEnsemblePage() {
  const supabase = await createClient();
  const [{ data: venues }, { data: ensembles }] = await Promise.all([
    supabase.from("venues").select("id, name").order("name"),
    supabase.from("ensembles").select("id, name").order("name").returns<{ id: string; name: string }[]>(),
  ]);

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Neues Ensemble</h1>
      <div className="mt-6">
        <EnsembleForm action={createEnsemble} venues={venues ?? []} ensembles={ensembles ?? []} />
      </div>
    </div>
  );
}
