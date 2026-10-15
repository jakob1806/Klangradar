import { createAdminClient } from "@/lib/supabase/admin";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Button } from "@/components/organizer/ui/button";
import { FeedForm } from "./feed-form";
import { removeFeed } from "./actions";

export const dynamic = "force-dynamic";

type SourceRow = {
  id: string;
  url: string;
  type: string;
  status: string;
  organizer_id: string;
  last_success_at: string | null;
  consecutive_failures: number | null;
  config: { selfService?: boolean; previewCount?: number } | null;
};

const STATUS: Record<string, { label: string; variant: "success" | "warning" | "danger" | "default" }> = {
  active: { label: "Aktiv", variant: "success" },
  under_review: { label: "Wird geprüft", variant: "warning" },
  error: { label: "Fehler", variant: "danger" },
  paused: { label: "Pausiert", variant: "default" },
};

export default async function FeedImportPage() {
  const organizers = await getEventOrganizerOptions();
  const organizerIds = organizers.map((o) => o.id);
  const names = new Map(organizers.map((o) => [o.id, o.name]));
  const { data } = organizerIds.length
    ? await createAdminClient()
        .from("sources")
        .select("id, url, type, status, organizer_id, last_success_at, consecutive_failures, config")
        .in("organizer_id", organizerIds)
        .order("created_at", { ascending: false })
        .returns<SourceRow[]>()
    : { data: [] as SourceRow[] };
  const sources = data ?? [];

  return (
    <div>
      <PageHeader
        eyebrow="Programm"
        title="Termine automatisch importieren"
        description="Hinterlege deinen Kalender-Feed oder Spielplan. Klangradar liest neue und geänderte Termine zweimal täglich ein – ohne dass du jeden Termin einzeln anlegst."
      />
      <PageBody className="flex flex-col gap-10">
        {organizers.length === 0 ? (
          <Card>
            <CardContent className="pt-5 text-sm text-[#4A4A4A]">Beanspruche zuerst deine Institution, dann kannst du hier einen Feed hinterlegen.</CardContent>
          </Card>
        ) : (
          <FeedForm organizers={organizers} />
        )}

        <section className="flex flex-col gap-3">
          <h2 className="text-base font-semibold text-[#111111]">Deine Quellen</h2>
          {sources.length === 0 ? (
            <p className="text-sm text-[#6B6B6B]">Noch keine Quelle hinterlegt.</p>
          ) : (
            <Card>
              <CardContent className="divide-y divide-[#111111]/[0.06] p-0">
                {sources.map((source) => {
                  const status = STATUS[source.status] ?? STATUS.paused;
                  return (
                    <div key={source.id} className="flex flex-wrap items-center gap-3 px-5 py-4">
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-[#111111]">{source.url}</p>
                        <p className="mt-0.5 text-xs text-[#6B6B6B]">
                          {names.get(source.organizer_id)} · {source.type.toUpperCase()}
                          {source.last_success_at ? ` · zuletzt gelesen ${formatMunichDateTime(source.last_success_at)}` : ""}
                          {(source.consecutive_failures ?? 0) > 0 ? ` · ${source.consecutive_failures} Fehlversuche` : ""}
                        </p>
                      </div>
                      <Badge variant={status.variant}>{status.label}</Badge>
                      {source.config?.selfService && source.status !== "paused" ? (
                        <form action={removeFeed}>
                          <input type="hidden" name="source_id" value={source.id} />
                          <Button type="submit" variant="ghost" size="sm">Pausieren</Button>
                        </form>
                      ) : null}
                    </div>
                  );
                })}
              </CardContent>
            </Card>
          )}
          <p className="text-xs leading-5 text-[#6B6B6B]">
            Neue Quellen prüft die Redaktion, bevor Termine erscheinen – in der Regel innerhalb eines Werktags. Importierte Termine findest du danach unter „Meine Events“ und kannst sie dort ergänzen.
          </p>
        </section>
      </PageBody>
    </div>
  );
}
