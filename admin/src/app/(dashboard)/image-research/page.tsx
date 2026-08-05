import { createClient } from "@/lib/supabase/server";
import { ImageResearchClient, type ImageEntityOption } from "./image-research-client";
import type { ImageEntityType } from "./actions";

export const dynamic = "force-dynamic";

const TABLE_FOR_TYPE: Record<ImageEntityType, string> = {
  person: "persons",
  venue: "venues",
  ensemble: "ensembles",
  event: "events",
};
const NAME_COLUMN_FOR_TYPE: Record<ImageEntityType, string> = {
  person: "full_name",
  venue: "name",
  ensemble: "name",
  event: "title",
};
const TYPE_LABEL: Record<ImageEntityType, string> = {
  person: "Personen",
  venue: "Venues",
  ensemble: "Ensembles",
  event: "Veranstaltungen",
};

async function loadEntities(entityType: ImageEntityType): Promise<ImageEntityOption[]> {
  const supabase = await createClient();
  const nameColumn = NAME_COLUMN_FOR_TYPE[entityType];

  if (entityType === "event") {
    const { data } = await supabase
      .from("events")
      .select("id, title, image_urls")
      .order("start_datetime", { ascending: false })
      .limit(300)
      .returns<Array<{ id: string; title: string; image_urls: string[] | null }>>();
    return (data ?? []).map((row) => ({
      id: row.id,
      name: row.title,
      hasImage: (row.image_urls?.length ?? 0) > 0,
    }));
  }

  const { data } = await supabase
    .from(TABLE_FOR_TYPE[entityType])
    .select(`id, ${nameColumn}, photo_url`)
    .order(nameColumn, { ascending: true })
    .limit(500)
    .returns<Array<Record<string, unknown>>>();
  return (data ?? []).map((row) => ({
    id: row.id as string,
    name: row[nameColumn] as string,
    hasImage: Boolean(row.photo_url),
  }));
}

export default async function ImageResearchPage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string }>;
}) {
  const { type } = await searchParams;
  const entityType = (type && TABLE_FOR_TYPE[type as ImageEntityType] ? type : "person") as ImageEntityType;
  const entities = await loadEntities(entityType);

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Bilder recherchieren</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Personen, Venues, Ensembles oder Veranstaltungen auswählen, dann Schritt für Schritt: automatische
        KI-Recherche, ein selbst angegebener Link, oder direkt eine eigene Datei hochladen — jedes Bild wird vor dem
        Übernehmen angezeigt, nichts landet ungeprüft live.
      </p>

      <div className="mt-4 flex gap-2">
        {(Object.keys(TYPE_LABEL) as ImageEntityType[]).map((t) => (
          <a
            key={t}
            href={`/image-research?type=${t}`}
            className={`rounded-md px-3 py-1.5 text-sm font-medium ${
              t === entityType ? "bg-neutral-900 text-white" : "border border-neutral-300 text-neutral-700 hover:bg-neutral-100"
            }`}
          >
            {TYPE_LABEL[t]}
          </a>
        ))}
      </div>

      <div className="mt-6">
        <ImageResearchClient key={entityType} entityType={entityType} entities={entities} />
      </div>
    </div>
  );
}
