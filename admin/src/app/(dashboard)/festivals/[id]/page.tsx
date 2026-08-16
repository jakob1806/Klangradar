import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DeleteButton } from "@/components/delete-button";
import { deleteFestival, updateFestival } from "../actions";
import { FestivalForm, type FestivalFormValues } from "../festival-form";

export default async function EditFestivalPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const [{ data, error }, { data: organizers }] = await Promise.all([
    supabase
      .from("festivals")
      .select("name, slug, description_de, organizer_id, recurring, website_url, photo_url, start_date, end_date")
      .eq("id", id)
      .maybeSingle<FestivalFormValues>(),
    supabase.from("organizers").select("id, name").order("name"),
  ]);

  if (error || !data) notFound();

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{data.name} bearbeiten</h1>
        <DeleteButton action={deleteFestival.bind(null, id)} confirmMessage={`"${data.name}" wirklich löschen?`} />
      </div>
      <div className="mt-6">
        <FestivalForm action={updateFestival.bind(null, id)} initial={data} organizers={organizers ?? []} />
      </div>
    </div>
  );
}
