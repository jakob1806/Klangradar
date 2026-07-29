import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { BioResearchWorkflow, type BioWorkflowEntity } from "./bio-research-workflow";
import type { BioEntityType } from "./actions";

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

export default async function BioResearchPage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string; ids?: string }>;
}) {
  const { type, ids } = await searchParams;
  const entityType = type as BioEntityType;
  if (!entityType || !TABLE_FOR_TYPE[entityType] || !ids) notFound();

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
        Für jeden ausgewählten Eintrag sucht die KI in Wikipedia nach einer Kurzbiografie/-beschreibung — vor dem
        Übernehmen bearbeitbar, keine automatische Speicherung.
      </p>

      <div className="mt-8">
        <BioResearchWorkflow entityType={entityType} entities={entities} />
      </div>
    </div>
  );
}
