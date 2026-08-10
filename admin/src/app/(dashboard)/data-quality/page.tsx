import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { markEventVerified } from "./actions";
import { fetchCompletenessRows, type CompletenessRow } from "./completeness";
import { fetchImageCoverageReport } from "./image-coverage";
import { fetchBiographyCoverageReport } from "./biography-coverage";

const ENTITY_TYPE_LABEL: Record<CompletenessRow["entityType"], string> = {
  venue: "Venue",
  person: "Person",
  ensemble: "Ensemble",
  work: "Werk",
};

function formatShortDate(iso: string | null) {
  if (!iso) return "Nie geprüft";
  return new Date(iso).toLocaleDateString("de-DE", { dateStyle: "medium" });
}

export const dynamic = "force-dynamic";

// Ab wann gilt ein bevorstehendes Event als "veraltet" i.S.d. wöchentlichen
// Datenqualitäts-Review (siehe docs/07-roadmap.md, "Kontinuierlich")? 14 Tage
// ohne erneute Quellen-Verifikation heißt: Preis/Absage-Status könnte sich
// unbemerkt geändert haben, seit last_verified_at zuletzt gesetzt wurde.
const STALE_AFTER_DAYS = 14;

interface EventRow {
  id: string;
  slug: string;
  title: string;
  start_datetime: string;
  image_urls: string[] | null;
  last_verified_at: string | null;
  venues: { name: string } | { name: string }[] | null;
}

function venueName(venues: EventRow["venues"]) {
  if (!venues) return null;
  return Array.isArray(venues) ? venues[0]?.name ?? null : venues.name;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export default async function DataQualityPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("events")
    .select("id, slug, title, start_datetime, image_urls, last_verified_at, venues(name)")
    .in("status", ["scheduled", "sold_out", "postponed"])
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true })
    .returns<EventRow[]>();

  const { rows: completenessRows, error: completenessError } = await fetchCompletenessRows();
  const incompleteRows = completenessRows.filter((r) => r.missingFields.length > 0).slice(0, 50);
  // Abschnitt 8: priorisierte Arbeitsliste — innerhalb der ohnehin schon auf
  // die nächsten 90 Tage eingegrenzten (also "high-visibility") Menge nach
  // schlechtestem Gesamtscore zuerst, statt nur nach Termin.
  const worstQualityRows = [...completenessRows]
    .sort((a, b) => a.quality.totalScore - b.quality.totalScore)
    .slice(0, 15);
  const { report: imageCoverage, error: imageCoverageError } = await fetchImageCoverageReport();
  const {
    report: biographyCoverage,
    missingPersons,
    error: biographyCoverageError,
  } = await fetchBiographyCoverageReport();

  const events = data ?? [];
  const missingImages = events.filter((e) => !e.image_urls || e.image_urls.length === 0);

  const staleCutoff = new Date().getTime() - STALE_AFTER_DAYS * 24 * 60 * 60 * 1000;
  const staleEvents = events
    .filter((e) => !e.last_verified_at || new Date(e.last_verified_at).getTime() < staleCutoff)
    .sort((a, b) => {
      if (!a.last_verified_at) return -1;
      if (!b.last_verified_at) return 1;
      return new Date(a.last_verified_at).getTime() - new Date(b.last_verified_at).getTime();
    });

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Datenqualität</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Wöchentliche Review-Basis für bevorstehende Veranstaltungen: fehlende Bilder und Events, deren
        Quelle seit mehr als {STALE_AFTER_DAYS} Tagen nicht erneut geprüft wurde.
      </p>

      {error && (
        <p className="mt-6 text-sm text-amber-700">Konnte Events nicht laden: {error.message}</p>
      )}

      <section className="mt-8">
        <h2 className="text-sm font-semibold text-neutral-700">Bild-Abdeckung (gesamter Bestand)</h2>
        {imageCoverageError && (
          <p className="mt-2 text-sm text-amber-700">Konnte Bild-Abdeckung nicht laden: {imageCoverageError}</p>
        )}
        {imageCoverage && (
          <>
            <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
              <CoverageTile label="Venues" covered={imageCoverage.venues.withImage} total={imageCoverage.venues.total} />
              <CoverageTile label="Personen" covered={imageCoverage.persons.withImage} total={imageCoverage.persons.total} />
              <CoverageTile
                label="Ensembles"
                covered={imageCoverage.ensembles.withImage}
                total={imageCoverage.ensembles.total}
              />
              <CoverageTile label="Events" covered={imageCoverage.events.withImage} total={imageCoverage.events.total} />
            </div>
            <p className="mt-3 text-xs text-neutral-500">
              {imageCoverage.totalImages} Bilder insgesamt · {imageCoverage.needsReviewCount} mit offener
              redaktioneller Prüfung ·{" "}
              {imageCoverage.duplicateContentHashGroups > 0
                ? `${imageCoverage.duplicateContentHashGroups} Dubletten-Gruppen (identischer Bildinhalt, unterschiedliche Entität)`
                : "keine Dubletten über verschiedene Entitäten hinweg"}
            </p>
            <p className="mt-1 text-xs text-neutral-500">
              Lizenzstatus:{" "}
              {Object.entries(imageCoverage.licenseStatusCounts)
                .map(([status, count]) => `${status}: ${count}`)
                .join(" · ") || "keine Bilder"}
            </p>
          </>
        )}
      </section>

      <section className="mt-8">
        <h2 className="text-sm font-semibold text-neutral-700">Biografie-Abdeckung (gesamter Bestand)</h2>
        {biographyCoverageError && (
          <p className="mt-2 text-sm text-amber-700">Konnte Biografie-Abdeckung nicht laden: {biographyCoverageError}</p>
        )}
        {biographyCoverage && (
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
            <CoverageTile
              label="Personen"
              covered={biographyCoverage.persons.withBiography}
              total={biographyCoverage.persons.total}
            />
            <CoverageTile
              label="Ensembles"
              covered={biographyCoverage.ensembles.withDescription}
              total={biographyCoverage.ensembles.total}
            />
            <CoverageTile
              label="Venues"
              covered={biographyCoverage.venues.withDescription}
              total={biographyCoverage.venues.total}
            />
          </div>
        )}
      </section>

      {!error && (
        <>
          <section className="mt-8">
            <h2 className="text-sm font-semibold text-neutral-700">
              Fehlende Biografien — Personen ({missingPersons.length})
            </h2>
            <div className="mt-3 flex flex-col gap-2">
              {missingPersons.length ? (
                <>
                  {missingPersons.slice(0, 50).map((p) => (
                    <div
                      key={p.id}
                      className="flex items-center justify-between gap-4 rounded-xl border border-black/[0.06] bg-white px-4 py-3 shadow-sm"
                    >
                      <p className="text-sm font-medium text-neutral-900">{p.full_name}</p>
                      <Link
                        href={`/persons/${p.id}`}
                        className="shrink-0 text-sm font-medium text-blue-600 hover:underline"
                      >
                        Bearbeiten
                      </Link>
                    </div>
                  ))}
                  {missingPersons.length > 50 && (
                    <p className="text-xs text-neutral-400">
                      … und {missingPersons.length - 50} weitere.
                    </p>
                  )}
                </>
              ) : (
                <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-8 text-center text-sm text-neutral-400">
                  Alle Personen haben eine Biografie.
                </div>
              )}
            </div>
          </section>

          <section className="mt-8">
            <h2 className="text-sm font-semibold text-neutral-700">
              Fehlende Bilder ({missingImages.length})
            </h2>
            <div className="mt-3 flex flex-col gap-2">
              {missingImages.length ? (
                missingImages.map((e) => (
                  <div
                    key={e.id}
                    className="flex items-center justify-between gap-4 rounded-xl border border-black/[0.06] bg-white px-4 py-3 shadow-sm"
                  >
                    <div>
                      <p className="text-sm font-medium text-neutral-900">{e.title}</p>
                      <p className="text-xs text-neutral-400">
                        {venueName(e.venues) ?? "—"} · {formatDate(e.start_datetime)}
                      </p>
                    </div>
                    <Link
                      href={`/events/${e.id}`}
                      className="shrink-0 text-sm font-medium text-blue-600 hover:underline"
                    >
                      Bearbeiten
                    </Link>
                  </div>
                ))
              ) : (
                <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-8 text-center text-sm text-neutral-400">
                  Alle bevorstehenden Events haben mindestens ein Bild.
                </div>
              )}
            </div>
          </section>

          <section className="mt-10">
            <h2 className="text-sm font-semibold text-neutral-700">
              Veraltete Events ({staleEvents.length})
            </h2>
            <div className="mt-3 flex flex-col gap-2">
              {staleEvents.length ? (
                staleEvents.map((e) => (
                  <div
                    key={e.id}
                    className="flex items-center justify-between gap-4 rounded-xl border border-black/[0.06] bg-white px-4 py-3 shadow-sm"
                  >
                    <div>
                      <p className="text-sm font-medium text-neutral-900">{e.title}</p>
                      <p className="text-xs text-neutral-400">
                        {venueName(e.venues) ?? "—"} · {formatDate(e.start_datetime)}
                      </p>
                      <p className="mt-1 text-xs text-amber-700">
                        {e.last_verified_at
                          ? `Zuletzt geprüft: ${formatDate(e.last_verified_at)}`
                          : "Nie geprüft"}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-3">
                      <Link
                        href={`/events/${e.id}`}
                        className="text-sm font-medium text-blue-600 hover:underline"
                      >
                        Bearbeiten
                      </Link>
                      <ConfirmButton
                        action={markEventVerified.bind(null, e.id)}
                        confirmMessage="Quelle wurde geprüft, als aktuell markieren?"
                        label="Als geprüft markieren"
                        pendingLabel="…"
                        className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
                      />
                    </div>
                  </div>
                ))
              ) : (
                <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-8 text-center text-sm text-neutral-400">
                  Keine veralteten Events — alles innerhalb von {STALE_AFTER_DAYS} Tagen geprüft.
                </div>
              )}
            </div>
          </section>

          <section className="mt-10">
            <h2 className="text-sm font-semibold text-neutral-700">
              Priorisierte Arbeitsliste — schlechtester Datenqualitäts-Score zuerst ({worstQualityRows.length})
            </h2>
            <p className="mt-1 max-w-2xl text-xs text-neutral-500">
              Gewichteter Score (Vollständigkeit kritischer Felder, Quellenlage, Aktualität, Bildabdeckung,
              Match-Sicherheit) statt reiner Feldanzahl — siehe quality-score.ts. &bdquo;Offene
              Prüfung&ldquo; zeigt Unsicherheit, die der Score allein verdecken könnte.
            </p>
            <div className="mt-3 overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
              <table className="w-full text-sm">
                <thead className="border-b border-black/[0.06] text-left">
                  <tr>
                    <th className="type-label px-4 py-3">Typ</th>
                    <th className="type-label px-4 py-3">Name</th>
                    <th className="type-label px-4 py-3">Score</th>
                    <th className="type-label px-4 py-3">Offene Prüfung</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-200">
                  {worstQualityRows.map((r) => (
                    <tr key={`quality-${r.entityType}-${r.id}`} className="hover:bg-neutral-50">
                      <td className="px-4 py-3 text-neutral-500">{ENTITY_TYPE_LABEL[r.entityType]}</td>
                      <td className="px-4 py-3 font-medium text-neutral-900">{r.name}</td>
                      <td className="px-4 py-3 text-neutral-600">
                        <span
                          className={
                            r.quality.totalScore < 40
                              ? "font-semibold text-red-700"
                              : r.quality.totalScore < 70
                                ? "font-semibold text-amber-700"
                                : "font-semibold text-emerald-700"
                          }
                        >
                          {r.quality.totalScore}
                        </span>
                        <span className="ml-1 text-xs text-neutral-400">
                          ({r.quality.completeness.reason})
                        </span>
                      </td>
                      <td className="px-4 py-3 text-xs text-neutral-600">
                        {r.quality.openReviewReasons.length ? r.quality.openReviewReasons.join(", ") : "—"}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {r.editHref ? (
                          <Link href={r.editHref} className="text-sm font-medium text-blue-600 hover:underline">
                            Bearbeiten
                          </Link>
                        ) : (
                          <span className="text-xs text-neutral-300">—</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="mt-10">
            <h2 className="text-sm font-semibold text-neutral-700">
              Profil-Vollständigkeit — Venues/Personen/Ensembles/Werke mit Veranstaltungen in den nächsten{" "}
              {HORIZON_DAYS_LABEL} ({incompleteRows.length}
              {completenessRows.length > incompleteRows.length ? ` von ${completenessRows.length}` : ""})
            </h2>
            <p className="mt-1 max-w-2xl text-xs text-neutral-500">
              Nur die Felder, die die automatische Anreicherung befüllt (Biografie, Instrumentierung, Leitung
              etc.) — nicht jede denkbare Datenlücke. Sortiert nach dem nächsten Veranstaltungstermin.
            </p>
            {completenessError && (
              <p className="mt-4 text-sm text-amber-700">Konnte Vollständigkeit nicht laden: {completenessError}</p>
            )}
            {!completenessError && (
              <div className="mt-3 overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
                <table className="w-full text-sm">
                  <thead className="border-b border-black/[0.06] text-left">
                    <tr>
                      <th className="type-label px-4 py-3">Typ</th>
                      <th className="type-label px-4 py-3">Name</th>
                      <th className="type-label px-4 py-3">Fehlende Felder</th>
                      <th className="type-label px-4 py-3">Score</th>
                      <th className="type-label px-4 py-3">Letzte Prüfung</th>
                      <th className="type-label px-4 py-3">Quellen</th>
                      <th className="px-4 py-3" />
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-neutral-200">
                    {incompleteRows.length ? (
                      incompleteRows.map((r) => (
                        <tr key={`${r.entityType}-${r.id}`} className="hover:bg-neutral-50">
                          <td className="px-4 py-3 text-neutral-500">{ENTITY_TYPE_LABEL[r.entityType]}</td>
                          <td className="px-4 py-3 font-medium text-neutral-900">{r.name}</td>
                          <td className="px-4 py-3 text-neutral-600">
                            {r.missingFields.length}/{r.totalFields}
                            <span className="ml-1 text-xs text-neutral-400">({r.missingFields.join(", ")})</span>
                          </td>
                          <td className="px-4 py-3 text-neutral-600">{r.quality.totalScore}</td>
                          <td className="px-4 py-3 text-neutral-600">{formatShortDate(r.profileCheckedAt)}</td>
                          <td className="px-4 py-3 text-neutral-600">
                            {r.sourceCount > 0 ? `${r.sourceCount} (${r.confidenceLabel})` : "—"}
                          </td>
                          <td className="px-4 py-3 text-right">
                            {r.editHref ? (
                              <Link
                                href={r.editHref}
                                className="text-sm font-medium text-blue-600 hover:underline"
                              >
                                Bearbeiten
                              </Link>
                            ) : (
                              <span className="text-xs text-neutral-300">—</span>
                            )}
                          </td>
                        </tr>
                      ))
                    ) : (
                      <tr>
                        <td colSpan={7} className="px-4 py-10 text-center text-neutral-400">
                          Alle bevorstehenden Einträge sind vollständig.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}

const HORIZON_DAYS_LABEL = "90 Tagen";

function CoverageTile({ label, covered, total }: { label: string; covered: number; total: number }) {
  const percent = total > 0 ? Math.round((covered / total) * 100) : 0;
  return (
    <div className="rounded-xl border border-black/[0.06] bg-white p-3 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">{label}</p>
      <p className="mt-1 text-lg font-semibold text-neutral-900">{percent}%</p>
      <p className="text-xs text-neutral-500">
        {covered} von {total}
      </p>
    </div>
  );
}
