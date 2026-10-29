import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Input, Textarea } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { SubmitButton } from "@/components/organizer/submit-button";
import { ActionForm } from "@/components/organizer/action-form";
import { submitWorkIntroduction } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Werkeinführungen für
// das eigene Programm selbst schreiben, z. B. aus dem Programmheft. Die
// Einführung erscheint in der App unter "Zum Programm" — nach Freigabe durch
// die Redaktion, weil ein Werk in vielen Konzerten verschiedener Veranstalter
// vorkommt.

interface ProgramWork {
  work_id: string;
  title: string;
  catalog_number: string | null;
  composer_name: string | null;
  concerts: number;
  next_start: string;
  introduction_de: string | null;
  introduction_source: string | null;
  pending: boolean;
}

const SOURCES: Record<string, string> = {
  wikipedia: "aus Wikipedia",
  redaktion: "von der Redaktion",
  programmheft: "aus dem Programmheft",
  veranstalter: "von eurer Website",
};

export default async function OrganizerWorkIntroductionsPage({ searchParams }: { searchParams: Promise<{ show?: string }> }) {
  const { show } = await searchParams;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("organizer_program_works");
  const works = (data ?? []) as ProgramWork[];
  const missing = works.filter((work) => !work.introduction_de);
  const listed = show === "all" ? works : missing;

  return (
    <div>
      <PageHeader
        eyebrow="Programm"
        title="Werkeinführungen"
        description="Kurze Einführungen zu den Werken eures Programms erscheinen in der App unter „Zum Programm“. Fehlt eine oder passt sie nicht, schreibt sie selbst – gern aus dem Programmheft. Die Redaktion prüft jeden Text vor der Veröffentlichung."
      />
      <PageBody>
        {error ? (
          <p className="text-sm text-[#8a5a0c]">Die Werkeinführungen sind nach der nächsten Datenbank-Aktualisierung verfügbar.</p>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-3">
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#6B6B6B]">Werke im kommenden Programm</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{works.length}</p>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#6B6B6B]">Mit Einführung</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">
                    {works.length ? Math.round(((works.length - missing.length) / works.length) * 100) : 0} %
                  </p>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#6B6B6B]">In Prüfung</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{works.filter((work) => work.pending).length}</p>
                </CardContent>
              </Card>
            </div>

            <div className="mt-8 flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">
                {show === "all" ? "Alle Werke" : "Ohne Einführung"}
              </h2>
              <div className="flex gap-1 rounded-lg bg-[#F3F3F3] p-1 text-[13px] font-medium">
                <Link href="/veranstalter/werkeinfuehrungen" aria-current={show !== "all" ? "page" : undefined} className={`rounded-md px-3 py-1 ${show !== "all" ? "bg-white text-[#111111] shadow-sm" : "text-[#6B6B6B]"}`}>
                  Ohne Einführung ({missing.length})
                </Link>
                <Link href="/veranstalter/werkeinfuehrungen?show=all" aria-current={show === "all" ? "page" : undefined} className={`rounded-md px-3 py-1 ${show === "all" ? "bg-white text-[#111111] shadow-sm" : "text-[#6B6B6B]"}`}>
                  Alle ({works.length})
                </Link>
              </div>
            </div>

            {listed.length === 0 ? (
              <Card className="mt-3">
                <CardContent className="pt-5 text-sm text-[#6B6B6B]">
                  {works.length === 0 ? "In euren kommenden Terminen ist noch kein Programm hinterlegt." : "Alle Werke eures Programms haben eine Einführung."}
                </CardContent>
              </Card>
            ) : (
              <div className="mt-3 flex flex-col gap-3">
                {listed.map((work) => (
                  <Card key={work.work_id}>
                    <details className="group">
                      <summary className="flex cursor-pointer list-none flex-wrap items-center justify-between gap-3 p-5">
                        <span className="min-w-0">
                          <span className="block font-medium text-[#111111]">{work.title}</span>
                          <span className="text-[13px] text-[#6B6B6B]">
                            {[work.composer_name, work.catalog_number].filter(Boolean).join(" · ")}
                            {work.composer_name || work.catalog_number ? " · " : ""}
                            {work.concerts === 1 ? "1 Termin" : `${work.concerts} Termine`}, ab {formatMunichDateTime(work.next_start)}
                          </span>
                        </span>
                        <span className="flex items-center gap-2">
                          {work.pending ? (
                            <Badge variant="warning">In Prüfung</Badge>
                          ) : work.introduction_de ? (
                            <Badge variant="success">Einführung {SOURCES[work.introduction_source ?? ""] ?? "vorhanden"}</Badge>
                          ) : (
                            <Badge>Fehlt</Badge>
                          )}
                          <span className="text-[13px] font-medium text-[#2D2A6E] group-open:hidden">{work.introduction_de ? "Ansehen" : "Schreiben"}</span>
                          <span className="hidden text-[13px] font-medium text-[#2D2A6E] group-open:inline">Schließen</span>
                        </span>
                      </summary>
                      <div className="flex flex-col gap-4 border-t border-[#F0F0F0] p-5">
                        {work.introduction_de && (
                          <div>
                            <p className="text-[13px] font-medium text-[#111111]">Aktuelle Einführung</p>
                            <p className="mt-1 whitespace-pre-line text-sm leading-relaxed text-[#4A4A4A]">{work.introduction_de}</p>
                          </div>
                        )}
                        <ActionForm action={submitWorkIntroduction.bind(null, work.work_id)} className="flex flex-col gap-3">
                          <div className="flex flex-col gap-1.5">
                            <Label htmlFor={`text-${work.work_id}`}>{work.introduction_de ? "Eigene Fassung vorschlagen" : "Einführung"}</Label>
                            <Textarea
                              id={`text-${work.work_id}`}
                              name="text"
                              required
                              minLength={80}
                              maxLength={4000}
                              rows={6}
                              placeholder="Entstehung, Besonderheiten, worauf man beim Hören achten kann – 3 bis 6 Sätze."
                            />
                          </div>
                          <div className="flex flex-col gap-1.5">
                            <Label htmlFor={`source-${work.work_id}`}>Quelle (optional)</Label>
                            <Input id={`source-${work.work_id}`} name="source_url" type="url" placeholder="https://… z. B. Link zum Programmheft" />
                          </div>
                          <div>
                            <SubmitButton size="sm" pendingLabel="Reiche ein …">
                              Zur Prüfung einreichen
                            </SubmitButton>
                          </div>
                        </ActionForm>
                      </div>
                    </details>
                  </Card>
                ))}
              </div>
            )}
          </>
        )}
      </PageBody>
    </div>
  );
}
