import { createClient } from "@/lib/supabase/server";
import { createPerson } from "../actions";
import { PersonForm } from "../person-form";

export default async function NewPersonPage() {
  const supabase = await createClient();
  const { data: ensembles } = await supabase
    .from("ensembles")
    .select("id, name")
    .eq("is_resolution_placeholder", false)
    .eq("is_family_root", false)
    .order("name")
    .returns<{ id: string; name: string }[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Neue Person</h1>
      <div className="mt-6">
        <PersonForm action={createPerson} ensembles={ensembles ?? []} />
      </div>
    </div>
  );
}
