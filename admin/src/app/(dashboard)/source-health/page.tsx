import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

// Nutzeranfrage: "kurz die Quellengesundheit" — Übersicht über die
// automatischen hydrate-<quelle>-events-Pipelines (Staatsoper, BRSO,
// Münchner Philharmoniker, Gasteig, MKO, Gärtnerplatztheater, BR-Chor,
// Münchener Biennale), die alle 10 Minuten per Cron laufen. Bisher nirgends
// sichtbar, ob sie erfolgreich laufen oder scheitern — das hier zeigt pro
// Quelle: wie viele anstehende Termine erfasst/verarbeitet wurden, wie
// viele noch ausstehen und wie viele mit Fehler stehen geblieben sind.
// Bewusst getrennt von /sources (dort geht es um die generische
// Ingestion-Pipeline über die sources-Tabelle, nicht um diese
// Detailseiten-Anreicherung einzelner bereits erfasster Events).
interface HydrateSource {
  key: string;
  label: string;
  domainPattern: string;
  syncedAtColumn: string;
  syncErrorColumn: string;
}

const HYDRATE_SOURCES: HydrateSource[] = [
  { key: "staatsoper", label: "Bayerische Staatsoper", domainPattern: "%staatsoper.de/%", syncedAtColumn: "staatsoper_detail_synced_at", syncErrorColumn: "staatsoper_detail_sync_error" },
  { key: "brso", label: "BRSO", domainPattern: "%brso.de/%", syncedAtColumn: "brso_detail_synced_at", syncErrorColumn: "brso_detail_sync_error" },
  { key: "br_chor", label: "BR-Chor", domainPattern: "%br-chor.de/%", syncedAtColumn: "br_chor_detail_synced_at", syncErrorColumn: "br_chor_detail_sync_error" },
  { key: "mphil", label: "Münchner Philharmoniker", domainPattern: "%mphil.de/%", syncedAtColumn: "mphil_detail_synced_at", syncErrorColumn: "mphil_detail_sync_error" },
  { key: "gasteig", label: "Gasteig HP8", domainPattern: "%gasteig.de/%", syncedAtColumn: "gasteig_detail_synced_at", syncErrorColumn: "gasteig_detail_sync_error" },
  { key: "mko", label: "Münchener Kammerorchester", domainPattern: "%m-k-o.eu/%", syncedAtColumn: "mko_detail_synced_at", syncErrorColumn: "mko_detail_sync_error" },
  { key: "gaertnerplatz", label: "Staatstheater am Gärtnerplatz", domainPattern: "%gaertnerplatztheater.de/%", syncedAtColumn: "gaertnerplatz_detail_synced_at", syncErrorColumn: "gaertnerplatz_detail_sync_error" },
  { key: "biennale", label: "Münchener Biennale", domainPattern: "%muenchener-biennale.de/%", syncedAtColumn: "biennale_detail_synced_at", syncErrorColumn: "biennale_detail_sync_error" },
];

interface EventSyncRow {
  id: string;
  title: string;
  start_datetime: string;
  synced_at: string | null;
  sync_error: string | null;
}

interface SourceHealth {
  source: HydrateSource;
  total: number;
  ok: number;
  errored: number;
  pending: number;
  errorSample: { title: string; error: string }[];
  error?: string;
}

async function loadHealth(supabase: Awaited<ReturnType<typeof createClient>>, source: HydrateSource): Promise<SourceHealth> {
  const { data, error } = await supabase
    .from("events")
    .select(`id, title, start_datetime, synced_at:${source.syncedAtColumn}, sync_error:${source.syncErrorColumn}`)
    .ilike("website_url", source.domainPattern)
    .gte("start_datetime", new Date().toISOString())
    .in("status", ["scheduled", "sold_out"])
    .returns<EventSyncRow[]>();

  if (error) return { source, total: 0, ok: 0, errored: 0, pending: 0, errorSample: [], error: error.message };

  const rows = data ?? [];
  const errored = rows.filter((r) => r.sync_error);
  const ok = rows.filter((r) => r.synced_at && !r.sync_error).length;
  const pending = rows.filter((r) => !r.synced_at).length;

  return {
    source,
    total: rows.length,
    ok,
    errored: errored.length,
    pending,
    errorSample: errored.slice(0, 3).map((r) => ({ title: r.title, error: r.sync_error! })),
  };
}

function HealthBadge({ health }: { health: SourceHealth }) {
  if (health.error) {
    return <span className="type-label border border-red-700 !text-red-700 px-2 py-1">Abfragefehler</span>;
  }
  if (health.total === 0) {
    return <span className="type-label border border-neutral-300 !text-neutral-500 px-2 py-1">keine Termine</span>;
  }
  if (health.errored > 0) {
    return <span className="type-label border border-red-700 !text-red-700 px-2 py-1">{health.errored} fehlgeschlagen</span>;
  }
  if (health.pending > 0) {
    return <span className="type-label border border-amber-700 !text-amber-700 px-2 py-1">{health.pending} ausstehend</span>;
  }
  return <span className="type-label border border-emerald-700 !text-emerald-700 px-2 py-1">läuft sauber</span>;
}

export default async function SourceHealthPage() {
  const supabase = await createClient();
  const results = await Promise.all(HYDRATE_SOURCES.map((source) => loadHealth(supabase, source)));

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Quellen-Gesundheit</h1>
      <p className="mt-1 max-w-2xl text-sm text-neutral-500">
        Status der automatischen Detailseiten-Anreicherung (Besetzung, teils Bilder) — läuft alle 10 Minuten per Cron
        pro Quelle für anstehende Veranstaltungen. Zeigt nur, ob die Anreicherung funktioniert, nicht die
        grundsätzliche Ersterfassung neuer Termine (siehe dafür{" "}
        <span className="font-medium text-neutral-700">Datenquellen &amp; Import</span>).
      </p>

      <div className="mt-6 flex flex-col gap-3">
        {results.map((health) => (
          <div key={health.source.key} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="font-medium text-neutral-900">{health.source.label}</p>
                <p className="mt-0.5 text-xs text-neutral-500">
                  {health.total} anstehende Termine · {health.ok} erfolgreich · {health.pending} ausstehend ·{" "}
                  {health.errored} fehlgeschlagen
                </p>
              </div>
              <HealthBadge health={health} />
            </div>
            {health.error && <p className="mt-2 text-xs text-red-700">{health.error}</p>}
            {health.errorSample.length > 0 && (
              <div className="mt-3 flex flex-col gap-1.5 border-t border-black/[0.06] pt-3">
                {health.errorSample.map((sample, index) => (
                  <p key={index} className="text-xs text-neutral-600">
                    <span className="font-medium text-neutral-800">{sample.title}:</span> {sample.error}
                  </p>
                ))}
                {health.errored > health.errorSample.length && (
                  <p className="text-xs text-neutral-400">
                    … und {health.errored - health.errorSample.length} weitere
                  </p>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
