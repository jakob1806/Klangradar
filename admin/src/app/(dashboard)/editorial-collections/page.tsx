import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

interface CollectionRow {
  id: string;
  title: string;
  is_published: boolean;
  sort_order: number;
  editorial_collection_events: { count: number }[];
}

export default async function EditorialCollectionsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("editorial_collections")
    .select("id, title, is_published, sort_order, editorial_collection_events(count)")
    .order("sort_order", { ascending: true })
    .returns<CollectionRow[]>();

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Redaktionelle Sammlungen</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Thematische Zusammenstellungen von Veranstaltungen (z. B. &bdquo;Höhepunkte der Woche&ldquo;,
            &bdquo;Für Klassik-Einsteiger&ldquo;) — werden erst nach &bdquo;Veröffentlicht&ldquo; in der App gezeigt.
          </p>
        </div>
        <Link
          href="/editorial-collections/new"
          className="border-2 border-[#171717] bg-[#171717] px-4 py-2 type-label !text-white hover:bg-white hover:!text-[#171717]"
        >
          Neu anlegen
        </Link>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Sammlungen nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 overflow-hidden border-2 border-[#171717] bg-white">
          <table className="w-full text-sm">
            <thead className="border-b-2 border-[#171717] text-left">
              <tr>
                <th className="type-label px-4 py-3">Titel</th>
                <th className="type-label px-4 py-3">Events</th>
                <th className="type-label px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-200">
              {data?.length ? (
                data.map((c) => (
                  <tr key={c.id} className="hover:bg-neutral-50">
                    <td className="px-4 py-3 font-medium text-neutral-900">
                      <Link href={`/editorial-collections/${c.id}`} className="hover:underline">
                        {c.title}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-neutral-600">{c.editorial_collection_events?.[0]?.count ?? 0}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`type-label border px-2 py-1 ${
                          c.is_published ? "border-emerald-700 !text-emerald-700" : "border-neutral-300 !text-neutral-500"
                        }`}
                      >
                        {c.is_published ? "Veröffentlicht" : "Entwurf"}
                      </span>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={3} className="px-4 py-10 text-center text-neutral-400">
                    Keine Sammlungen angelegt.
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
