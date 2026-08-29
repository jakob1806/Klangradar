import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Field, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { requestOrganizerClaim, createOwnOrganizer } from "./actions";

export const dynamic = "force-dynamic";

interface OrganizerMatch {
  id: string;
  name: string;
}

export default async function ClaimOrganizerPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  const query = (q ?? "").trim();
  const supabase = await createClient();

  let results: OrganizerMatch[] = [];
  if (query) {
    const { data } = await supabase.rpc("find_matching_organizer", {
      p_name: query,
      p_similarity_threshold: 0.3,
      p_result_limit: 10,
    });
    results = ((data ?? []) as { id: string; name: string }[]).map((r) => ({ id: r.id, name: r.name }));
  }

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <h1 className="type-heading mb-2 text-2xl text-[#1d1d1f]">Institution beanspruchen</h1>
      <p className="mb-4 text-sm text-[#86868b]">
        Suche nach deiner Institution/deinem Veranstalter. Findest du sie nicht, kannst du sie unten neu
        anlegen. Jede Anfrage wird mit Nachweis von der Redaktion geprüft, bevor Verwaltungsrechte entstehen.
      </p>

      <div className="mb-6 flex gap-3 text-sm">
        <Link href="/veranstalter/claim/venue" className="font-medium text-[#0071e3] hover:underline">
          Venue beanspruchen →
        </Link>
        <Link href="/veranstalter/claim/person" className="font-medium text-[#0071e3] hover:underline">
          Person beanspruchen →
        </Link>
        <Link href="/veranstalter/claim/ensemble" className="font-medium text-[#0071e3] hover:underline">
          Ensemble beanspruchen →
        </Link>
      </div>

      <form method="get" className="mb-6 flex gap-2">
        <TextInput type="search" name="q" defaultValue={query} placeholder="Name der Institution…" className="flex-1" />
        <button
          type="submit"
          className="rounded-lg border border-black/10 px-4 py-2 text-sm font-medium text-neutral-700 hover:bg-black/[0.04]"
        >
          Suchen
        </button>
      </form>

      {query && (
        <div className="mb-10">
          {results.length > 0 ? (
            <ul className="divide-y divide-neutral-200 overflow-hidden rounded-xl border border-black/[0.06] bg-white">
              {results.map((r) => (
                <li key={r.id} className="px-4 py-4">
                  <span className="font-medium text-[#1d1d1f]">{r.name}</span>
                  <form action={requestOrganizerClaim.bind(null, r.id)} className="mt-3 grid gap-3 sm:grid-cols-2">
                    <Field label="Geschäftliche E-Mail" required><TextInput name="verification_email" type="email" required placeholder="name@institution.de" /></Field>
                    <Field label="Nachweis-Link" required><TextInput name="evidence_url" type="url" required placeholder="https://www.beispiel.de/impressum" /></Field>
                    <div className="sm:col-span-2"><Field label="Warum bist du berechtigt?" required><TextArea name="justification" rows={2} required placeholder="Funktion bei der Institution und Bezug zum Nachweis" /></Field></div>
                    <div className="sm:col-span-2"><SubmitButton pendingLabel="Sende…">Mit Nachweis beantragen</SubmitButton></div>
                  </form>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-[#86868b]">Keine Treffer für „{query}“.</p>
          )}
        </div>
      )}

      <div className="rounded-xl border border-black/[0.06] bg-white p-6">
        <h2 className="mb-2 text-sm font-semibold text-[#86868b]">Nicht gefunden? Neue Institution anlegen</h2>
        <p className="mb-4 text-sm text-[#48484a]">Auch neue Institutionen werden erst nach Prüfung des Nachweises freigeschaltet.</p>
        <form action={createOwnOrganizer} className="flex flex-col gap-4">
          <Field label="Name" required>
            <TextInput type="text" name="name" required defaultValue={query} />
          </Field>
          <Field label="Kontakt-E-Mail">
            <TextInput type="email" name="contact_email" />
          </Field>
          <Field label="Website">
            <TextInput type="url" name="website_url" placeholder="https://…" />
          </Field>
          <Field label="Geschäftliche E-Mail" required>
            <TextInput type="email" name="verification_email" required placeholder="name@institution.de" />
          </Field>
          <Field label="Nachweis-Link" required>
            <TextInput type="url" name="evidence_url" required placeholder="https://www.beispiel.de/impressum" />
          </Field>
          <Field label="Warum bist du berechtigt?" required>
            <TextArea name="justification" rows={3} required placeholder="Funktion bei der Institution und Bezug zum Nachweis" />
          </Field>
          <div>
            <SubmitButton>Institution anlegen</SubmitButton>
          </div>
        </form>
      </div>
    </div>
  );
}
