"use client";

import { useMemo, useState } from "react";
import { addEntityAlias, deleteEntityAlias, setCanonicalEntityName, type AliasEntityType } from "./actions";

export interface AliasRow { id: string; alias: string }
export interface CanonicalEntity { id: string; name: string; aliases: AliasRow[] }

export function AliasManager({ type, entities }: { type: AliasEntityType; entities: CanonicalEntity[] }) {
  const [query, setQuery] = useState("");
  const visible = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase("de");
    if (!needle) return entities;
    return entities.filter((entity) =>
      entity.name.toLocaleLowerCase("de").includes(needle)
      || entity.aliases.some((item) => item.alias.toLocaleLowerCase("de").includes(needle)),
    );
  }, [entities, query]);

  return (
    <div className="mt-6">
      <input
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="Hauptschreibweise oder Alias suchen …"
        className="w-full max-w-xl rounded-xl border border-black/10 bg-white px-4 py-2.5 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/15"
      />
      <p className="mt-2 text-xs text-neutral-500">{visible.length} von {entities.length} Einträgen</p>

      <div className="mt-4 grid gap-3">
        {visible.map((entity) => (
          <article key={entity.id} className="rounded-2xl border border-black/[0.07] bg-white p-4 shadow-sm">
            <form action={setCanonicalEntityName} className="flex flex-wrap items-end gap-2">
              <input type="hidden" name="entity_type" value={type} />
              <input type="hidden" name="entity_id" value={entity.id} />
              <label className="min-w-64 flex-1 text-xs font-medium text-neutral-500">
                Hauptschreibweise
                <input name="canonical_name" defaultValue={entity.name} required className="mt-1 w-full rounded-lg border border-black/10 px-3 py-2 text-sm text-neutral-950" />
              </label>
              <button className="rounded-lg bg-[#0071e3] px-3 py-2 text-sm font-medium text-white hover:bg-[#0077ed]">Hauptschreibweise speichern</button>
            </form>

            <div className="mt-3 flex flex-wrap gap-2">
              {entity.aliases.length === 0 && <span className="text-xs text-neutral-400">Noch keine alternativen Schreibweisen</span>}
              {entity.aliases.map((item) => (
                <form action={deleteEntityAlias} key={item.id}>
                  <input type="hidden" name="alias_id" value={item.id} />
                  <button title="Alias entfernen" className="rounded-full bg-neutral-100 px-3 py-1.5 text-xs text-neutral-700 hover:bg-red-50 hover:text-red-700">
                    {item.alias} <span aria-hidden>×</span>
                  </button>
                </form>
              ))}
            </div>

            <form action={addEntityAlias} className="mt-3 flex max-w-xl gap-2">
              <input type="hidden" name="entity_type" value={type} />
              <input type="hidden" name="entity_id" value={entity.id} />
              <input name="alias" required placeholder="Alternative Schreibweise hinzufügen" className="min-w-0 flex-1 rounded-lg border border-black/10 px-3 py-2 text-sm" />
              <button className="rounded-lg border border-black/10 px-3 py-2 text-sm font-medium hover:bg-neutral-50">Hinzufügen</button>
            </form>
          </article>
        ))}
      </div>
    </div>
  );
}
