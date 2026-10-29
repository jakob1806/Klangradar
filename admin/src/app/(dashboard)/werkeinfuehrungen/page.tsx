import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import { researchAllWorks, researchWork } from "../works/actions";
import { reviewIntroSubmission } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): eigene Kategorie für
// Werkeinführungen. Zeigt die Abdeckung (alle Werke, Werke kommender
// Konzerte, nächste 30 Tage) und die Werke ohne Einführung, sortiert nach
// Anzahl kommender Konzerte – die wichtigsten Lücken stehen oben. Pro Werk:
// automatisch recherchieren (Wikipedia/Wikidata, Edge Function
// work-introduction) oder selbst schreiben (Werkseite, gilt dann als
// Redaktionstext und wird nie überschrieben).

interface Coverage {
  total: number;
  with_intro: number;
  redaktion: number;
  pending: number;
  upcoming: number;
  upcoming_with_intro: number;
  next30: number;
  next30_with_intro: number;
}

interface Submission {
  submission_id: string;
  work_id: string;
  work_title: string;
  composer_name: string | null;
  organizer_name: string | null;
  text: string;
  source_url: string | null;
  current_intro: string | null;
  created_at: string;
}

interface MissingWork {
  work_id: string;
  title: string;
  catalog_number: string | null;
  composer_name: string | null;
  concerts: number;
  next_start: string | null;
  checked_at: string | null;
}

function percent(part: number, total: number) {
  return total > 0 ? Math.round((part / total) * 100) : 0;
}

function Tile({ label, part, total, hint }: { label: string; part: number; total: number; hint?: string }) {
  const value = percent(part, total);
  return (
    <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums text-neutral-900">{value} %</p>
      <p className="mt-0.5 text-xs text-neutral-500">
        {part.toLocaleString("de-DE")} von {total.toLocaleString("de-DE")}
        {hint ? ` · ${hint}` : ""}
      </p>
      <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-black/[0.06]">
        <div className="h-full rounded-full bg-[#2D2A6E]" style={{ width: `${value}%` }} />
      </div>
    </div>
  );
}

const dateFormat = new Intl.DateTimeFormat("de-DE", { day: "numeric", month: "short", timeZone: "Europe/Berlin" });

export default async function WorkIntroductionsPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  const supabase = await createClient();
  const [{ data: coverageData, error: coverageError }, { data: missingData, error: missingError }, { data: submissionData }] = await Promise.all([
    supabase.rpc("admin_work_introduction_coverage"),
    supabase.rpc("admin_works_missing_introduction", { p_limit: 150, p_query: q ?? null }),
    supabase.rpc("admin_work_intro_submissions"),
  ]);
  const submissions = (submissionData ?? []) as Submission[];
  const coverage = coverageData as Coverage | null;
  const missing = (missingData ?? []) as MissingWork[];
  const error = coverageError ?? missingError;

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Werkeinführungen</h1>
      <p className="mt-1 max-w-2xl text-sm text-neutral-500">
        Einführungen erscheinen in der App unter „Zum Programm“. Die Recherche läuft automatisch alle 5 Minuten
        (Wikipedia, abgeglichen über Wikidata und Werkverzeichnisnummern), kommende Konzerte zuerst. Selbst
        geschriebene Texte gelten als Redaktionstext und werden nie überschrieben.
      </p>

      {error && <p className="mt-4 text-sm text-amber-700">Konnte Daten nicht laden: {error.message}</p>}

      {coverage && (
        <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Tile label="Nächste 30 Tage" part={coverage.next30_with_intro} total={coverage.next30} />
          <Tile label="Kommende Konzerte" part={coverage.upcoming_with_intro} total={coverage.upcoming} />
          <Tile label="Alle Werke" part={coverage.with_intro} total={coverage.total} hint={`${coverage.redaktion} von der Redaktion`} />
          <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
            <p className="text-xs font-medium uppercase tracking-wide text-neutral-500">Warteschlange</p>
            <p className="mt-1 text-2xl font-semibold tabular-nums text-neutral-900">{coverage.pending.toLocaleString("de-DE")}</p>
            <p className="mt-0.5 text-xs text-neutral-500">Werke noch nicht geprüft</p>
            <form action={researchAllWorks} className="mt-3">
              <SubmitButton pendingLabel="Starte …">Jetzt 40 recherchieren</SubmitButton>
              <p className="mt-1.5 text-xs text-neutral-500">Läuft im Hintergrund, Ergebnisse nach etwa zwei Minuten.</p>
            </form>
          </div>
        </div>
      )}

      {submissions.length > 0 && (
        <section className="mt-8">
          <h2 className="text-base font-semibold text-neutral-900">Von Veranstaltern eingereicht</h2>
          <p className="text-xs text-neutral-500">Übernommene Texte gelten als Redaktionstext und werden nicht mehr automatisch überschrieben.</p>
          <div className="mt-3 flex flex-col gap-3">
            {submissions.map((submission) => (
              <article key={submission.submission_id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <Link href={`/works/${submission.work_id}`} className="font-medium text-neutral-900 hover:underline">
                      {submission.work_title}
                    </Link>
                    <p className="text-xs text-neutral-500">
                      {[submission.composer_name, submission.organizer_name && `eingereicht von ${submission.organizer_name}`, dateFormat.format(new Date(submission.created_at))]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    <form action={reviewIntroSubmission.bind(null, submission.submission_id, true)}>
                      <SubmitButton pendingLabel="Übernehme …">Übernehmen</SubmitButton>
                    </form>
                    <form action={reviewIntroSubmission.bind(null, submission.submission_id, false)}>
                      <button type="submit" className="rounded-lg border border-black/10 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50">
                        Ablehnen
                      </button>
                    </form>
                  </div>
                </div>
                <p className="mt-3 whitespace-pre-line text-sm leading-relaxed text-neutral-800">{submission.text}</p>
                {submission.source_url && (
                  <a href={submission.source_url} target="_blank" rel="noreferrer" className="mt-2 inline-block text-xs text-[#2D2A6E] hover:underline">
                    Quelle ansehen
                  </a>
                )}
                {submission.current_intro && (
                  <details className="mt-3 text-xs text-neutral-500">
                    <summary className="cursor-pointer">Bisherige Einführung anzeigen</summary>
                    <p className="mt-2 whitespace-pre-line text-neutral-600">{submission.current_intro}</p>
                  </details>
                )}
              </article>
            ))}
          </div>
        </section>
      )}

      <div className="mt-8 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold text-neutral-900">Ohne Einführung</h2>
          <p className="text-xs text-neutral-500">Werke kommender Konzerte, die meistgespielten zuerst.</p>
        </div>
        <form className="flex gap-2">
          <input
            name="q"
            defaultValue={q ?? ""}
            placeholder="Werk oder Komponist:in"
            className="w-64 rounded-lg border border-black/10 bg-white px-3 py-2 text-sm outline-none focus:border-[#2D2A6E]"
          />
          <button type="submit" className="rounded-lg border border-black/10 bg-white px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50">
            Suchen
          </button>
        </form>
      </div>

      <div className="mt-3 overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
        <table className="w-full text-sm">
          <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
            <tr>
              <th className="px-4 py-2.5 font-medium">Werk</th>
              <th className="px-4 py-2.5 font-medium">Konzerte</th>
              <th className="px-4 py-2.5 font-medium">Nächstes</th>
              <th className="px-4 py-2.5 font-medium">Zuletzt geprüft</th>
              <th className="px-4 py-2.5" />
            </tr>
          </thead>
          <tbody className="divide-y divide-black/[0.05]">
            {missing.map((work) => (
              <tr key={work.work_id} className="align-top">
                <td className="px-4 py-3">
                  <Link href={`/works/${work.work_id}`} className="font-medium text-neutral-900 hover:underline">
                    {work.title}
                  </Link>
                  <p className="text-xs text-neutral-500">
                    {[work.composer_name, work.catalog_number].filter(Boolean).join(" · ") || "Komponist:in unbekannt"}
                  </p>
                </td>
                <td className="px-4 py-3 tabular-nums">{work.concerts}</td>
                <td className="px-4 py-3 whitespace-nowrap">{work.next_start ? dateFormat.format(new Date(work.next_start)) : "–"}</td>
                <td className="px-4 py-3 whitespace-nowrap text-neutral-500">
                  {work.checked_at ? dateFormat.format(new Date(work.checked_at)) : "ausstehend"}
                </td>
                <td className="px-4 py-3">
                  <div className="flex justify-end gap-2">
                    <form action={researchWork.bind(null, work.work_id)}>
                      <SubmitButton pendingLabel="Sucht …">Recherchieren</SubmitButton>
                    </form>
                    <Link
                      href={`/works/${work.work_id}`}
                      className="rounded-lg border border-black/10 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
                    >
                      Selbst schreiben
                    </Link>
                  </div>
                </td>
              </tr>
            ))}
            {!error && missing.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-sm text-neutral-500">
                  {q ? "Keine Treffer." : "Alle Werke kommender Konzerte haben eine Einführung."}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
