import { DeleteButton } from "@/components/delete-button";
import { createClient } from "@/lib/supabase/server";
import { deleteTag } from "./actions";

export const dynamic = "force-dynamic";

interface TagRow {
  id: string;
  name: string;
  is_ai_generated: boolean;
  usage_count: number;
}

export default async function TagsPage() {
  const supabase = await createClient();
  const [{ data: tags, error }, { data: eventTags }] = await Promise.all([
    supabase.from("tags").select("id, name, is_ai_generated").order("name"),
    supabase.from("event_tags").select("tag_id"),
  ]);

  const usageByTag = new Map<string, number>();
  for (const et of eventTags ?? []) {
    usageByTag.set(et.tag_id, (usageByTag.get(et.tag_id) ?? 0) + 1);
  }
  const rows: TagRow[] = (tags ?? []).map((t) => ({ ...t, usage_count: usageByTag.get(t.id) ?? 0 }));

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Tags</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Von der KI beim Anreichern automatisch vorgeschlagene Schlagworte (siehe enrich-event-references) plus
        redaktionelle Tags. Rauschen hier löschen, statt es weiter mitzuschleppen — betroffene Events verlieren nur
        die Verknüpfung, nicht sich selbst.
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Tags nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 overflow-hidden border-2 border-[#171717] bg-white">
          <table className="w-full text-sm">
            <thead className="border-b-2 border-[#171717] text-left">
              <tr>
                <th className="type-label px-4 py-3">Name</th>
                <th className="type-label px-4 py-3">Herkunft</th>
                <th className="type-label px-4 py-3">Verwendet</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-200">
              {rows.length ? (
                rows
                  .sort((a, b) => b.usage_count - a.usage_count)
                  .map((tag) => (
                    <tr key={tag.id} className="hover:bg-neutral-50">
                      <td className="px-4 py-3 font-medium text-neutral-900">{tag.name}</td>
                      <td className="px-4 py-3 text-neutral-600">{tag.is_ai_generated ? "KI" : "Redaktion"}</td>
                      <td className="px-4 py-3 text-neutral-600">{tag.usage_count}</td>
                      <td className="px-4 py-3 text-right">
                        <DeleteButton
                          action={deleteTag.bind(null, tag.id)}
                          confirmMessage={`Tag "${tag.name}" löschen? Wird von allen ${tag.usage_count} Event(s) entfernt.`}
                        />
                      </td>
                    </tr>
                  ))
              ) : (
                <tr>
                  <td colSpan={4} className="px-4 py-10 text-center text-neutral-400">
                    Noch keine Tags vorhanden.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
