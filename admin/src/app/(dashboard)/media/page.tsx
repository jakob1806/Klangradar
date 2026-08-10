import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { confirmImageFree, confirmImageLicensed, rejectImage, updateImageMetadata } from "./actions";
import { EnrichImagesButton } from "./enrich-images-button";
import { MediaBulkBar, MediaRowCheckbox, MediaSelectAllCheckbox, MediaSelectionProvider } from "./media-select";

export const dynamic = "force-dynamic";

const ORIGIN_LABEL: Record<string, string> = {
  event: "Event",
  venue: "Venue",
  ensemble: "Ensemble",
  person: "Person",
  organizer: "Institution",
  festival: "Festival",
};

/** Tabelle/Namensspalte/Admin-Route pro origin_type — damit jede Bildkarte
 * zeigt, WEM das Bild zugeordnet werden soll (bisher nur origin_type +
 * eine rohe origin_id-UUID, praktisch nicht zuordenbar ohne eigene Query).
 * "organizer" hat keine eigene Admin-Detailseite, daher route: null (Name
 * wird trotzdem angezeigt, nur ohne Link). */
const ORIGIN_CONFIG: Record<string, { table: string; nameColumn: string; route: string | null }> = {
  event: { table: "events", nameColumn: "title", route: "/events" },
  venue: { table: "venues", nameColumn: "name", route: "/venues" },
  ensemble: { table: "ensembles", nameColumn: "name", route: "/ensembles" },
  person: { table: "persons", nameColumn: "full_name", route: "/persons" },
  organizer: { table: "organizers", nameColumn: "name", route: null },
  festival: { table: "festivals", nameColumn: "name", route: "/festivals" },
};

interface ImageRow {
  id: string;
  source_url: string;
  origin_type: string;
  origin_id: string;
  photographer: string | null;
  copyright_notice: string | null;
  license_notes: string | null;
  source_page_url: string | null;
  source_name: string | null;
  credits: string | null;
  license_name: string | null;
  license_url: string | null;
  license_status: string;
  confidence_score: number | null;
  match_reason: string | null;
  warnings: string[];
  thumbnail_path: string | null;
  storage_path: string | null;
  imported_at: string;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

/** Zeigt das bereits heruntergeladene, re-encodierte Thumbnail statt des
 * rohen externen Hotlinks — bisher rendere diese Seite ausgerechnet in der
 * Review-Queue selbst denselben Hotlink-Fragilitätsklasse-Fehler (429 bei
 * Wikimedia-Last o.ä.), den die eigentliche Pipeline längst durch
 * Herunterladen/Storage vermeidet.
 *
 * Reihenfolge: thumbnail_path (klein, schnell) -> storage_path (unser
 * eigenes Vollbild — greift, wenn NUR die Thumbnail-Generierung fehlschlug,
 * das Hauptbild aber im Storage liegt; kam bei mehreren og:image-Funden
 * live vor, siehe pHash-Dedupe-Pfad in ensureCoverImageInner, der
 * thumbnail_path der Ursprungszeile 1:1 mitkopiert, auch wenn der dort
 * null war) -> source_url als letzter, unzuverlässigster Rückfall (z.B.
 * ältere, nie verarbeitete Zeilen ganz ohne Storage-Kopie). */
function thumbnailSrc(
  supabase: Awaited<ReturnType<typeof createClient>>,
  image: Pick<ImageRow, "thumbnail_path" | "storage_path" | "source_url">,
): string {
  const path = image.thumbnail_path ?? image.storage_path;
  if (!path) return image.source_url;
  return supabase.storage.from("ingested-images").getPublicUrl(path).data.publicUrl;
}

export default async function MediaPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("images")
    .select("id, source_url, origin_type, origin_id, photographer, copyright_notice, license_notes, imported_at, source_page_url, source_name, credits, license_name, license_url, license_status, confidence_score, match_reason, warnings, thumbnail_path, storage_path")
    .eq("needs_review", true)
    .order("imported_at", { ascending: false })
    .returns<ImageRow[]>();

  // Namen pro (origin_type, origin_id) auflösen — eine Query pro betroffenem
  // Typ statt pro Bild, damit die Seite bei vielen Kandidaten nicht dutzende
  // Einzel-Requests auslöst.
  const idsByType = new Map<string, Set<string>>();
  for (const image of data ?? []) {
    if (!idsByType.has(image.origin_type)) idsByType.set(image.origin_type, new Set());
    idsByType.get(image.origin_type)!.add(image.origin_id);
  }

  const nameByKey = new Map<string, string>();
  await Promise.all(
    Array.from(idsByType.entries()).map(async ([type, ids]) => {
      const config = ORIGIN_CONFIG[type];
      if (!config) return;
      // Spaltenname ist dynamisch (pro origin_type verschieden) — der
      // generierte Supabase-Typ kann ein Template-Literal-select() nicht
      // statisch parsen, daher hier bewusst als unknown[] behandelt.
      const { data: rows } = await supabase
        .from(config.table)
        .select(`id, ${config.nameColumn}`)
        .in("id", Array.from(ids))
        .returns<Array<Record<string, unknown>>>();
      for (const row of rows ?? []) {
        const name = row[config.nameColumn];
        if (typeof name === "string") nameByKey.set(`${type}:${row.id}`, name);
      }
    }),
  );

  return (
    <div className="p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Bilder — Lizenz-Review</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Ein automatischer Lauf (alle 15 Minuten, siehe <code>cron.job</code> &bdquo;image-enrichment&rdquo;)
            sucht laufend Bilder für neue und bestehende Einträge: Events, sowie Venues/Personen/Ensembles/
            Festivals über ihre eigene offizielle Website werden direkt übernommen (kein Fremdbild, daher
            ohne Review). Nur der Wikimedia-Fallback landet hier zur redaktionellen Freigabe — jedes dieser
            Bilder braucht eine Entscheidung (&bdquo;Frei nutzbar&rdquo;/&bdquo;Lizenziert&rdquo;), bevor es live geht.
            Bestehende Bilder werden dabei laufend auf Erreichbarkeit geprüft und bei einem Defekt
            automatisch zurückgesetzt (dann erneut für die Suche vorgemerkt).
          </p>
        </div>
        <div className="flex items-center gap-3">
          <Link
            href="/media/gaps"
            className="rounded-lg border border-black/10 bg-white px-4 py-2 text-sm font-medium text-[#1d1d1f] transition-colors hover:bg-black/[0.04]"
          >
            Bildlücken-Bericht
          </Link>
          <EnrichImagesButton />
        </div>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Bilder nicht laden: {error.message}</p>}

      {!error && (
        <MediaSelectionProvider>
          <div className="mt-6">
            {(data?.length ?? 0) > 0 && (
              <div className="mb-3">
                <MediaSelectAllCheckbox ids={(data ?? []).map((i) => i.id)} />
              </div>
            )}
            <MediaBulkBar />
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {data?.length ? (
            data.map((image) => {
              const config = ORIGIN_CONFIG[image.origin_type];
              const entityName = nameByKey.get(`${image.origin_type}:${image.origin_id}`);
              const entityHref = config?.route ? `${config.route}/${image.origin_id}` : null;
              return (
              <div key={image.id} className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={thumbnailSrc(supabase, image)} alt="" className="h-40 w-full object-cover bg-neutral-100" />
                <div className="p-3">
                  <div className="flex items-center gap-2">
                    <MediaRowCheckbox id={image.id} />
                    <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-[11px] font-medium text-neutral-600">
                      {ORIGIN_LABEL[image.origin_type] ?? image.origin_type}
                    </span>
                    {entityHref ? (
                      <Link
                        href={entityHref}
                        className="truncate text-sm font-semibold text-neutral-900 hover:underline"
                        title={entityName ?? "Bearbeiten"}
                      >
                        {entityName ?? "(Name unbekannt — Eintrag anzeigen)"}
                      </Link>
                    ) : (
                      <span className="truncate text-sm font-semibold text-neutral-900">
                        {entityName ?? "(Name unbekannt)"}
                      </span>
                    )}
                  </div>
                  <p className="mt-0.5 text-xs text-neutral-400">{formatDate(image.imported_at)}</p>
                  <a
                    href={image.source_url}
                    target="_blank"
                    rel="noreferrer"
                    className="mt-1 block truncate text-xs text-blue-600 hover:underline"
                  >
                    {image.source_url}
                  </a>
                  {image.photographer && (
                    <p className="mt-1 text-xs text-neutral-500">Foto: {image.photographer}</p>
                  )}
                  {image.copyright_notice && (
                    <p className="mt-1 text-xs text-neutral-500">© {image.copyright_notice}</p>
                  )}
                  {image.license_notes && (
                    <p className="mt-1 text-xs text-neutral-500">{image.license_notes}</p>
                  )}
                  {image.match_reason && <p className="mt-2 text-xs text-neutral-700"><strong>Zuordnung:</strong> {image.match_reason}</p>}
                  <p className="mt-1 text-xs text-neutral-500">
                    Quelle: {image.source_name ?? "unbekannt"} · Lizenz: {image.license_name ?? image.license_status}
                    {image.confidence_score !== null ? ` · Confidence: ${Math.round(image.confidence_score * 100)} %` : ""}
                  </p>
                  {image.source_page_url && <a href={image.source_page_url} target="_blank" rel="noreferrer" className="mt-1 block truncate text-xs text-blue-600 hover:underline">Quellseite öffnen</a>}
                  {image.warnings?.map((warning) => <p key={warning} className="mt-1 text-xs text-amber-700">⚠ {warning}</p>)}
                  <form action={updateImageMetadata} className="mt-3 grid grid-cols-2 gap-2 border-t pt-3">
                    <input type="hidden" name="imageId" value={image.id} />
                    <input name="photographer" defaultValue={image.photographer ?? ""} placeholder="Fotograf" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="credits" defaultValue={image.credits ?? ""} placeholder="Credit-Text" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="licenseName" defaultValue={image.license_name ?? ""} placeholder="Lizenz" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="licenseUrl" defaultValue={image.license_url ?? ""} placeholder="Lizenz-URL" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="confidenceScore" type="number" min="0" max="1" step="0.01" defaultValue={image.confidence_score ?? ""} placeholder="Confidence 0–1" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <button type="submit" className="rounded-md border border-black/10 px-2 py-1 text-xs font-medium hover:bg-black/[0.04]">Metadaten speichern</button>
                  </form>
                  <div className="mt-3 flex flex-wrap gap-3">
                    <ConfirmButton
                      action={confirmImageFree.bind(null, image.id)}
                      confirmMessage="Als frei nutzbar freigeben?"
                      label="Frei nutzbar"
                      pendingLabel="…"
                      className="text-xs font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
                    />
                    <ConfirmButton
                      action={confirmImageLicensed.bind(null, image.id)}
                      confirmMessage="Als lizenziert (mit Quellenangabe) freigeben?"
                      label="Lizenziert"
                      pendingLabel="…"
                      className="text-xs font-medium text-amber-700 hover:text-amber-900 disabled:opacity-50"
                    />
                    <ConfirmButton
                      action={rejectImage.bind(null, image.id)}
                      confirmMessage="Bild ablehnen? Wird nie ausgespielt."
                      label="Ablehnen"
                      pendingLabel="…"
                      className="text-xs font-medium text-neutral-500 hover:text-neutral-900 disabled:opacity-50"
                    />
                  </div>
                </div>
              </div>
              );
            })
          ) : (
            <div className="col-span-full border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine Bilder zur Prüfung.
            </div>
          )}
            </div>
          </div>
        </MediaSelectionProvider>
      )}
    </div>
  );
}
