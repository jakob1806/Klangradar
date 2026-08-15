import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { AliasManager, type CanonicalEntity } from "./alias-manager";
import type { AliasEntityType } from "./actions";

export const dynamic = "force-dynamic";

const TYPES: Record<AliasEntityType, { label: string; table: string; column: string }> = {
  person: { label: "Personen", table: "persons", column: "full_name" },
  ensemble: { label: "Ensembles", table: "ensembles", column: "name" },
  venue: { label: "Venues", table: "venues", column: "name" },
  work: { label: "Werke", table: "works", column: "title" },
};

async function loadEntities(supabase: Awaited<ReturnType<typeof createClient>>, type: AliasEntityType) {
  async function allRows(table: string, columns: string, orderColumn: string) {
    const rows: Record<string, unknown>[] = [];
    for (let from = 0; ; from += 1000) {
      const { data, error } = await supabase.from(table).select(columns).order(orderColumn).range(from, from + 999)
        .returns<Record<string, unknown>[]>();
      if (error) return { data: null, error };
      rows.push(...(data ?? []));
      if (!data || data.length < 1000) return { data: rows, error: null };
    }
  }
  switch (type) {
    case "person": {
      const result = await allRows("persons", "id, full_name", "full_name");
      return { ...result, data: result.data?.map((row) => ({ id: row.id, name: row.full_name })) };
    }
    case "ensemble": {
      const result = await allRows("ensembles", "id, name", "name");
      return { ...result, data: result.data?.map((row) => ({ id: row.id, name: row.name })) };
    }
    case "venue": {
      const result = await allRows("venues", "id, name", "name");
      return { ...result, data: result.data?.map((row) => ({ id: row.id, name: row.name })) };
    }
    case "work": {
      const result = await allRows("works", "id, title", "title");
      return { ...result, data: result.data?.map((row) => ({ id: row.id, name: row.title })) };
    }
  }
}

export default async function AliasesPage({ searchParams }: { searchParams: Promise<{ type?: string }> }) {
  const requested = (await searchParams).type;
  const type: AliasEntityType = requested && requested in TYPES ? requested as AliasEntityType : "person";
  const config = TYPES[type];
  const supabase = await createClient();
  const [{ data: rows, error }, { data: aliases }] = await Promise.all([
    loadEntities(supabase, type),
    supabase.from("entity_aliases").select("id, entity_id, alias").eq("entity_type", type).order("alias"),
  ]);

  const aliasesByEntity = new Map<string, { id: string; alias: string }[]>();
  for (const alias of aliases ?? []) {
    const list = aliasesByEntity.get(String(alias.entity_id)) ?? [];
    list.push({ id: String(alias.id), alias: String(alias.alias) });
    aliasesByEntity.set(String(alias.entity_id), list);
  }
  const entities: CanonicalEntity[] = (rows ?? []).map((row) => ({
    id: String(row.id),
    name: String(row.name ?? ""),
    aliases: aliasesByEntity.get(String(row.id)) ?? [],
  }));

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Haupt- & Alternativschreibweisen</h1>
      <p className="mt-1 max-w-3xl text-sm text-neutral-500">
        Suchen und Veranstaltungsimporte lösen jede alternative Schreibweise auf diesen Hauptdatensatz auf. Beim Ändern der Hauptschreibweise wird der bisherige Name automatisch als Alias behalten.
      </p>
      <nav className="mt-5 flex flex-wrap gap-2">
        {(Object.entries(TYPES) as [AliasEntityType, (typeof TYPES)[AliasEntityType]][]).map(([key, item]) => (
          <Link key={key} href={`/aliases?type=${key}`} className={`rounded-full px-4 py-2 text-sm font-medium ${key === type ? "bg-[#0071e3] text-white" : "bg-black/[0.05] text-neutral-700 hover:bg-black/[0.08]"}`}>
            {item.label}
          </Link>
        ))}
      </nav>
      {error ? <p className="mt-6 text-sm text-red-700">Einträge konnten nicht geladen werden: {error.message}</p> : <AliasManager type={type} entities={entities} />}
    </div>
  );
}
