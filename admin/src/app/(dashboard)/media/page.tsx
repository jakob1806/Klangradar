import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { confirmImageFree, confirmImageLicensed, rejectImage, updateImageMetadata } from "./actions";
import { EnrichImagesButton } from "./enrich-images-button";
import { MediaBulkBar, MediaSelectableCard, MediaSelectAllCheckbox, MediaSelectionProvider } from "./media-select";

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
  const [{ data, error }, { count: missingPersons }, { count: missingEnsembles }] = await Promise.all([
    supabase
      .from("images")
      .select("id, source_url, origin_type, origin_id, photographer, copyright_notice, license_notes, imported_at, source_page_url, source_name, credits, license_name, license_url, license_status, confidence_score, match_reason, warnings, thumbnail_path, storage_path")
      .eq("needs_review", true)
      .order("imported_at", { ascending: false })
      .returns<ImageRow[]>(),
    supabase.from("persons").select("id", { count: "exact", head: true }).is("photo_url", null),
    supabase.from("ensembles").select("id", { count: "exact", head: true }).is("photo_url", null),
  ]);

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
    <div className="mx-auto max-w-[1480px] p-6 lg:p-8">
      <div className="rounded-2xl border border-black/[0.06] bg-gradient-to-br from-white to-neutral-50 p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[#0071e3]">Redaktion</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">Bilderfreigabe</h1>
          <p className="mt-1 max-w-2xl text-sm text-neutral-500">
            Bildvorschläge prüfen, bequem auswählen und einzeln oder gesammelt freigeben. Ein Klick auf Bild
            oder Kartenfläche fügt einen Vorschlag zur Auswahl hinzu.
          </p>
        </div>
        <EnrichImagesButton />
      </div>
      </div>

      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <div className="rounded-2xl border border-black/[0.06] bg-white p-5 shadow-sm">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.08em] text-neutral-400">Personen</p>
              <p className="mt-2 text-3xl font-semibold tabular-nums text-neutral-900">{missingPersons ?? 0}</p>
              <p className="mt-1 text-sm text-neutral-500">Profile ohne Bild</p>
            </div>
            <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-medium text-blue-700">Offene Bildlücken</span>
          </div>
          <Link
            href="/image-research?type=person&missing=1"
            className="mt-5 block rounded-xl bg-[#0071e3] px-4 py-2.5 text-center text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
          >
            Fehlende Personenbilder bearbeiten
          </Link>
        </div>

        <div className="rounded-2xl border border-black/[0.06] bg-white p-5 shadow-sm">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.08em] text-neutral-400">Ensembles</p>
              <p className="mt-2 text-3xl font-semibold tabular-nums text-neutral-900">{missingEnsembles ?? 0}</p>
              <p className="mt-1 text-sm text-neutral-500">Profile ohne Bild</p>
            </div>
            <span className="rounded-full bg-purple-50 px-3 py-1 text-xs font-medium text-purple-700">Offene Bildlücken</span>
          </div>
          <Link
            href="/image-research?type=ensemble&missing=1"
            className="mt-5 block rounded-xl bg-[#0071e3] px-4 py-2.5 text-center text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
          >
            Fehlende Ensemblebilder bearbeiten
          </Link>
        </div>
      </div>

      <div className="mt-10 flex items-end justify-between gap-4 border-t border-black/[0.06] pt-8">
        <div>
          <h2 className="text-base font-semibold tracking-tight text-neutral-900">Vorschläge zur Freigabe</h2>
          <p className="mt-1 max-w-2xl text-sm text-neutral-500">
            Nur Fremdbilder mit noch ungeklärter Lizenz landen hier. Bilder von einer verifizierten offiziellen
            Profilseite können direkt übernommen werden und erscheinen deshalb nicht in dieser Liste.
          </p>
        </div>
        <span className="rounded-full bg-neutral-100 px-3 py-1 text-xs font-medium tabular-nums text-neutral-600">
          {data?.length ?? 0} offen
        </span>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Bilder nicht laden: {error.message}</p>}

      {!error && (
        <MediaSelectionProvider>
          <div className="mt-6">
            {(data?.length ?? 0) > 0 && (
              <div className="mb-4 flex items-center justify-between rounded-xl border border-black/[0.06] bg-white px-4 py-3 shadow-sm">
                <MediaSelectAllCheckbox ids={(data ?? []).map((i) => i.id)} />
                <span className="text-xs text-neutral-400">Karte oder Bild anklicken</span>
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
              <MediaSelectableCard key={image.id} id={image.id}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={thumbnailSrc(supabase, image)} alt="" className="h-52 w-full bg-neutral-100 object-cover transition-transform duration-300 group-hover:scale-[1.015]" />
                <div className="p-4">
                  <div className="flex items-center gap-2 pr-1">
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
                  <p className="mt-1 text-xs text-neutral-400">Eingegangen {formatDate(image.imported_at)}</p>
                  {image.photographer && (
                    <p className="mt-1 text-xs text-neutral-500">Foto: {image.photographer}</p>
                  )}
                  {image.copyright_notice && (
                    <p className="mt-1 text-xs text-neutral-500">© {image.copyright_notice}</p>
                  )}
                  {image.license_notes && (
                    <p className="mt-1 text-xs text-neutral-500">{image.license_notes}</p>
                  )}
                  {image.match_reason && <p className="mt-3 rounded-xl bg-neutral-50 px-3 py-2 text-xs leading-5 text-neutral-700"><strong>Warum dieses Bild?</strong> {image.match_reason}</p>}
                  <div className="mt-3 flex flex-wrap items-center gap-2 text-xs">
                    <span className="rounded-full bg-blue-50 px-2.5 py-1 font-medium text-blue-700">{image.source_name ?? "Quelle unbekannt"}</span>
                    {image.confidence_score !== null && <span className="rounded-full bg-neutral-100 px-2.5 py-1 text-neutral-600">{Math.round(image.confidence_score * 100)} % Sicherheit</span>}
                  </div>
                  <div className="mt-3 flex gap-3 text-xs font-medium">
                    <a href={image.source_url} target="_blank" rel="noreferrer" className="text-[#0071e3] hover:underline">Bildquelle öffnen ↗</a>
                    {image.source_page_url && <a href={image.source_page_url} target="_blank" rel="noreferrer" className="text-[#0071e3] hover:underline">Quellseite ↗</a>}
                  </div>
                  {image.warnings?.map((warning) => <p key={warning} className="mt-1 text-xs text-amber-700">⚠ {warning}</p>)}
                  <details className="mt-4 rounded-xl border border-black/[0.07] bg-neutral-50/70">
                    <summary className="cursor-pointer list-none px-3 py-2 text-xs font-medium text-neutral-700">Lizenzdetails und Metadaten bearbeiten</summary>
                  <form action={updateImageMetadata} className="grid grid-cols-2 gap-2 border-t border-black/[0.06] p-3">
                    <input type="hidden" name="imageId" value={image.id} />
                    <input name="photographer" defaultValue={image.photographer ?? ""} placeholder="Fotograf" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="credits" defaultValue={image.credits ?? ""} placeholder="Credit-Text" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="licenseName" defaultValue={image.license_name ?? ""} placeholder="Lizenz" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="licenseUrl" defaultValue={image.license_url ?? ""} placeholder="Lizenz-URL" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <input name="confidenceScore" type="number" min="0" max="1" step="0.01" defaultValue={image.confidence_score ?? ""} placeholder="Confidence 0–1" className="rounded-md border border-black/10 px-2 py-1 text-xs focus:border-[#0071e3] outline-none" />
                    <button type="submit" className="rounded-md border border-black/10 px-2 py-1 text-xs font-medium hover:bg-black/[0.04]">Metadaten speichern</button>
                  </form>
                  </details>
                  <div className="mt-4 grid grid-cols-3 gap-2 border-t border-black/[0.06] pt-4">
                    <ConfirmButton
                      action={confirmImageFree.bind(null, image.id)}
                      confirmMessage="Als frei nutzbar freigeben?"
                      label="Frei nutzbar"
                      pendingLabel="…"
                      className="w-full rounded-lg bg-emerald-50 px-2 py-2 text-xs font-semibold text-emerald-700 hover:bg-emerald-100 disabled:opacity-50"
                    />
                    <ConfirmButton
                      action={confirmImageLicensed.bind(null, image.id)}
                      confirmMessage="Als lizenziert (mit Quellenangabe) freigeben?"
                      label="Lizenziert"
                      pendingLabel="…"
                      className="w-full rounded-lg bg-amber-50 px-2 py-2 text-xs font-semibold text-amber-700 hover:bg-amber-100 disabled:opacity-50"
                    />
                    <ConfirmButton
                      action={rejectImage.bind(null, image.id)}
                      confirmMessage="Bild ablehnen? Wird nie ausgespielt."
                      label="Ablehnen"
                      pendingLabel="…"
                      className="w-full rounded-lg bg-neutral-100 px-2 py-2 text-xs font-semibold text-neutral-600 hover:bg-neutral-200 disabled:opacity-50"
                    />
                  </div>
                </div>
              </MediaSelectableCard>
              );
            })
          ) : (
            <div className="col-span-full rounded-xl border border-dashed border-neutral-300 bg-white px-4 py-10 text-center">
              <p className="text-sm font-medium text-neutral-700">Aktuell wartet kein Bild auf Lizenzfreigabe.</p>
              <p className="mt-1 text-xs text-neutral-400">
                Die offenen Profilbild-Lücken bleiben oben trotzdem sichtbar und können jederzeit bearbeitet werden.
              </p>
            </div>
          )}
            </div>
          </div>
        </MediaSelectionProvider>
      )}
    </div>
  );
}
