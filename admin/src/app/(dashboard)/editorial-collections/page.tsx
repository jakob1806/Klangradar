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
          className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700"
        >
          Neu anlegen
        </Link>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Sammlungen nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 overflow-hidden rounded-lg border border-neutral-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-3 font-medium">Titel</th>
                <th className="px-4 py-3 font-medium">Events</th>
                <th className="px-4 py-3 font-medium">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
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
                        className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${
                          c.is_published ? "bg-emerald-50 text-emerald-700" : "bg-neutral-100 text-neutral-500"
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
