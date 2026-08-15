import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { BioResearchWorkflow, type BioWorkflowEntity } from "./bio-research-workflow";
import { BioResearchPicker, EntityTypeTabs, type BioEntityOption } from "./bio-research-picker";
import type { BioEntityType } from "./actions";
import { ImageResearchClient } from "../image-research/image-research-client";

export const dynamic = "force-dynamic";

const TABLE_FOR_TYPE: Record<BioEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  venue: "venues",
};

const NAME_COLUMN_FOR_TYPE: Record<BioEntityType, string> = {
  person: "full_name",
  ensemble: "name",
  venue: "name",
};

const BIO_COLUMN_FOR_TYPE: Record<BioEntityType, string> = {
  person: "biography_de",
  ensemble: "description_de",
  venue: "description_de",
};

const BACK_LINK: Record<BioEntityType, string> = {
  person: "/persons",
  ensemble: "/ensembles",
  venue: "/venues",
};

/** Lädt ALLE Einträge eines Typs mit hasBio-Status — für den eigenständigen
 * Auswahl-Picker (kein ids= in der URL, siehe EntityTypeTabs/BioResearchPicker
 * unten). Getrennt von der ids-basierten Vorauswahl weiter unten, die von
 * BioResearchBar (Checkbox-Auswahl auf den Listenseiten) kommt und
 * unverändert bleibt. */
async function loadEntities(entityType: BioEntityType): Promise<BioEntityOption[]> {
  const supabase = await createClient();
  const nameColumn = NAME_COLUMN_FOR_TYPE[entityType];
  const bioColumn = BIO_COLUMN_FOR_TYPE[entityType];
  const extraColumns = ", photo_url, ai_biography_status, last_image_search_note, image_search_checked_at";

  // PostgREST begrenzt Antworten projektweit auf 1.000 Zeilen. Die alte
  // feste .limit(500)-Abfrage ließ deshalb mehr als tausend Personen im
  // eigenständigen Bio-Tab vollständig verschwinden. Seitenweise laden,
  // bis wirklich der gesamte Bestand vorliegt.
  const rows: Array<Record<string, unknown>> = [];
  const pageSize = 1_000;
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await supabase
      .from(TABLE_FOR_TYPE[entityType])
      .select(`id, ${nameColumn}, ${bioColumn}${extraColumns}`)
      .order(nameColumn, { ascending: true })
      .range(from, from + pageSize - 1)
      .returns<Array<Record<string, unknown>>>();
    if (error) throw new Error(error.message);
    rows.push(...(data ?? []));
    if (!data || data.length < pageSize) break;
  }

  // Ein recherchiertes Bild kann bereits sicher in unserem Storage liegen,
  // aber noch auf die redaktionelle Lizenzfreigabe warten. photo_url allein
  // bildet diesen Zustand nicht ab. Die echte offene Review-Queue deshalb
  // separat laden, statt Kandidaten aus einem möglicherweise alten
  // Diagnose-Text zu erraten.
  const candidateIds = new Set<string>();
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await supabase
      .from("images")
      .select("origin_id")
      .eq("origin_type", entityType)
      .eq("needs_review", true)
      .range(from, from + pageSize - 1)
      .returns<Array<{ origin_id: string }>>();
    if (error) throw new Error(error.message);
    for (const image of data ?? []) candidateIds.add(image.origin_id);
    if (!data || data.length < pageSize) break;
  }

  return rows.map((row) => ({
    id: row.id as string,
    name: row[nameColumn] as string,
    hasBio: Boolean((row[bioColumn] as string | null)?.trim()),
    currentBio: (row[bioColumn] as string | null) ?? null,
    bioStatus: row.ai_biography_status as BioEntityOption["bioStatus"],
    hasImage: Boolean(row.photo_url),
    imageSearchNote: row.last_image_search_note as string | null,
    imageSearchCheckedAt: row.image_search_checked_at as string | null,
    hasImageCandidate: candidateIds.has(row.id as string),
  }));
}

export default async function BioResearchPage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string; ids?: string; mode?: string }>;
}) {
  const { type, ids, mode: requestedMode } = await searchParams;

  // Kein ids= in der URL: eigenständiger Tab-Einstieg (Sidebar-Link) —
  // eigene Auswahl direkt hier, statt zwingend über die Personen-/Venues-/
  // Ensembles-Listenseite gehen zu müssen (Nutzerwunsch: "Bio recherche
  // soll auch einen eigenen Tab bekommen wie bilder recherchieren").
  if (!ids) {
    const entityType = (type && TABLE_FOR_TYPE[type as BioEntityType] ? type : "person") as BioEntityType;
    const mode = requestedMode === "bio" || requestedMode === "image" ? requestedMode : "automatic";
    const entities = await loadEntities(entityType);
    return (
      <div className="p-8">
        <h1 className="text-xl font-semibold tracking-tight">Recherche &amp; Anreicherung</h1>
        <p className="mt-1 max-w-xl text-sm text-neutral-500">
          Biografien und Bilder laufen hauptsächlich automatisch. Für gezielte Korrekturen bleiben die bisherigen
          manuellen Werkzeuge direkt an derselben Stelle verfügbar.
        </p>

        <div className="mt-5 inline-flex rounded-xl bg-black/[0.04] p-1">
          {([
            ["automatic", "Automatik & Fortschritt"],
            ["bio", "Biografie manuell"],
            ["image", "Bild manuell"],
          ] as const).map(([value, label]) => (
            <Link
              key={value}
              href={`/bio-research?type=${entityType}&mode=${value}`}
              className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                mode === value ? "bg-white text-neutral-900 shadow-sm" : "text-neutral-500 hover:text-neutral-900"
              }`}
            >
              {label}
            </Link>
          ))}
        </div>

        <EntityTypeTabs entityType={entityType} mode={mode} />
        <div className="mt-6">
          {mode === "image" ? (
            <ImageResearchClient
              key={`image:${entityType}`}
              entityType={entityType}
              entities={entities.map((entity) => ({
                id: entity.id,
                name: entity.name,
                hasImage: Boolean(entity.hasImage),
              }))}
              initialOnlyMissing
            />
          ) : (
            <BioResearchPicker
              key={`${mode}:${entityType}`}
              entityType={entityType}
              entities={entities}
              mode={mode === "bio" ? "manual" : "automatic"}
            />
          )}
        </div>
      </div>
    );
  }

  const entityType = type as BioEntityType;
  if (!entityType || !TABLE_FOR_TYPE[entityType]) notFound();

  const idList = ids.split(",").filter(Boolean);
  if (idList.length === 0) notFound();

  const supabase = await createClient();
  const nameColumn = NAME_COLUMN_FOR_TYPE[entityType];
  const bioColumn = BIO_COLUMN_FOR_TYPE[entityType];

  const { data, error } = await supabase
    .from(TABLE_FOR_TYPE[entityType])
    .select(`id, ${nameColumn}, ${bioColumn}`)
    .in("id", idList)
    .returns<Record<string, unknown>[]>();

  if (error) {
    return (
      <div className="p-8">
        <p className="text-sm text-amber-700">Konnte Auswahl nicht laden: {error.message}</p>
      </div>
    );
  }

  // Reihenfolge der übergebenen ids beibehalten statt DB-Reihenfolge, damit
  // die Auswahl-Reihenfolge aus der Liste im Workflow erhalten bleibt.
  const byId = new Map((data ?? []).map((row) => [row.id as string, row]));
  const entities: BioWorkflowEntity[] = idList
    .map((id) => byId.get(id))
    .filter((row): row is NonNullable<typeof row> => Boolean(row))
    .map((row) => ({
      id: row.id as string,
      name: (row as Record<string, unknown>)[nameColumn] as string,
      currentBio: ((row as Record<string, unknown>)[bioColumn] as string | null) ?? null,
    }));

  return (
    <div className="p-8">
      <Link href={BACK_LINK[entityType]} className="text-sm text-neutral-500 hover:text-neutral-700">
        ← Zurück
      </Link>
      <h1 className="mt-2 text-xl font-semibold tracking-tight">Bios recherchieren</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Manuelle Nachbearbeitung einer Auswahl. Neue und fehlende Personenbiografien werden unabhängig davon bereits
        automatisch im Hintergrund recherchiert und gespeichert.
      </p>

      <div className="mt-8">
        <BioResearchWorkflow entityType={entityType} entities={entities} />
      </div>
    </div>
  );
}
