// Erstellt von Claude Code (26.10.2026): Nutzeranfragen aus dem
// Konzert-Journal der App. Die Einträge werden beim Anfragen bereits
// automatisch angelegt und angereichert; hier prüft die Redaktion nach.
import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { setEntityRequestStatus } from "./actions";

export const dynamic = "force-dynamic";

interface RequestRow {
  id: string;
  entity_type: "person" | "ensemble" | "venue" | "work";
  name: string;
  context: string | null;
  status: "pending" | "created" | "existing" | "needs_review" | "rejected" | "done";
  created_entity_id: string | null;
  note: string | null;
  created_at: string;
}

const TYPE_LABEL: Record<RequestRow["entity_type"], string> = {
  person: "Person", ensemble: "Ensemble", venue: "Ort", work: "Werk",
};
const TYPE_PATH: Record<RequestRow["entity_type"], string> = {
  person: "/persons", ensemble: "/ensembles", venue: "/venues", work: "/works",
};
const STATUS: Record<RequestRow["status"], { label: string; style: string }> = {
  pending: { label: "Offen", style: "bg-gray-50 text-gray-700 border-gray-200" },
  created: { label: "Angelegt – Anreicherung läuft", style: "bg-blue-50 text-blue-800 border-blue-200" },
  existing: { label: "Gab es schon", style: "bg-green-50 text-green-800 border-green-200" },
  needs_review: { label: "Manuell anlegen", style: "bg-amber-50 text-amber-800 border-amber-200" },
  rejected: { label: "Abgelehnt", style: "bg-red-50 text-red-700 border-red-200" },
  done: { label: "Geprüft", style: "bg-green-50 text-green-800 border-green-200" },
};

export default async function EntityRequestsPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("entity_requests")
    .select("id, entity_type, name, context, status, created_entity_id, note, created_at")
    .in("status", ["pending", "created", "needs_review"])
    .order("created_at", { ascending: false })
    .limit(200)
    .returns<RequestRow[]>();
  const rows = data ?? [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Nutzeranfragen</h1>
        <p className="text-sm text-gray-600">
          Fehlende Personen, Ensembles, Orte und Werke aus eigenen Konzerteinträgen der App. Neue Einträge werden sofort angelegt
          und automatisch mit Biografie, Bildern, Lebensdaten bzw. Werkeinführung angereichert – bitte kurz prüfen.
        </p>
      </div>
      {rows.length === 0 ? (
        <p className="text-sm text-gray-500">Keine offenen Anfragen.</p>
      ) : (
        <ul className="divide-y rounded-lg border bg-white">
          {rows.map((row) => (
            <li key={row.id} className="flex flex-wrap items-center gap-3 p-4">
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-medium uppercase tracking-wide text-gray-500">{TYPE_LABEL[row.entity_type]}</span>
                  <span className={`rounded border px-2 py-0.5 text-xs ${STATUS[row.status].style}`}>{STATUS[row.status].label}</span>
                </div>
                <p className="font-medium">
                  {row.created_entity_id ? (
                    <Link className="hover:underline" href={`${TYPE_PATH[row.entity_type]}/${row.created_entity_id}`}>{row.name}</Link>
                  ) : row.name}
                  {row.context ? <span className="text-gray-500"> · {row.context}</span> : null}
                </p>
                {row.note ? <p className="text-sm text-gray-500">{row.note}</p> : null}
                <p className="text-xs text-gray-400">{new Date(row.created_at).toLocaleString("de-DE")}</p>
              </div>
              <form action={setEntityRequestStatus.bind(null, row.id, "done")}>
                <button className="rounded border px-3 py-1.5 text-sm hover:bg-gray-50" type="submit">Geprüft</button>
              </form>
              <ConfirmButton action={setEntityRequestStatus.bind(null, row.id, "rejected")} label="Ablehnen" pendingLabel="Wird abgelehnt …" confirmMessage="Anfrage wirklich ablehnen?" />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
