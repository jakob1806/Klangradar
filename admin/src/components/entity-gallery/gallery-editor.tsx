"use client";

import { useRef, useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  addGalleryImage,
  confirmGalleryImage,
  deleteGalleryImage,
  markGalleryImageTooSmall,
  moveGalleryImage,
  recheckGalleryImage,
  rejectGalleryImage,
  saveGalleryImageCrop,
  setEventFallbackImage,
  setGalleryImageVenue,
  setPrimaryGalleryImage,
  type GalleryImage,
  type GalleryOriginType,
} from "@/lib/gallery-actions";
import { CropTool } from "./crop-tool";
import { CroppedImagePreview } from "./cropped-image-preview";

const BUCKET = "entity-photos";
const MAX_BYTES = 5 * 1024 * 1024;
const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];

// Nur die Fälle mit eigenem Badge — "valid"/"approved" sind der Normalfall
// und brauchen keine visuelle Warnung (Nutzervorgabe: Qualitäts-/Review-
// Status sichtbar machen, vor allem die PROBLEMATISCHEN Zustände, allen
// voran die drei bekannten zu kleinen Bestandsbilder).
const QUALITY_BADGES: Partial<Record<string, { label: string; className: string }>> = {
  low_resolution: { label: "Zu klein", className: "bg-red-100 text-red-700" },
  blurry: { label: "Unscharf", className: "bg-red-100 text-red-700" },
  unreachable: { label: "Nicht erreichbar", className: "bg-red-100 text-red-700" },
  invalid_format: { label: "Ungültiges Format", className: "bg-red-100 text-red-700" },
  duplicate: { label: "Duplikat", className: "bg-amber-100 text-amber-800" },
  copyright_unclear: { label: "Lizenz unklar", className: "bg-amber-100 text-amber-800" },
};
const REVIEW_BADGES: Partial<Record<string, { label: string; className: string }>> = {
  pending: { label: "Ausstehend", className: "bg-neutral-200 text-neutral-700" },
  rejected: { label: "Abgelehnt", className: "bg-red-100 text-red-700" },
  needs_manual_review: { label: "Manuelle Prüfung", className: "bg-amber-100 text-amber-800" },
};

/** Mehrfach-Bilder-Galerie für eine Person/ein Ensemble: Upload, Reihenfolge
 * (= Wisch-Reihenfolge in der App, niedrigster sort_order ist die
 * Miniaturansicht/das Titelbild), Querformat-Zuschnitt pro Bild, Löschen.
 * Serverseitig geladene Anfangsliste (images), danach rein clientseitiger
 * State + revalidatePath in den Server Actions hält es synchron. */
export function GalleryEditor({
  originType,
  originId,
  path,
  images,
  onChanged,
  venueId = null,
  venues,
  showEventFallbackToggle = false,
  storagePrefix,
}: {
  originType: GalleryOriginType;
  originId: string;
  path: string;
  images: GalleryImage[];
  /** Optional: wird nach jeder erfolgreichen Änderung aufgerufen — nötig für
   * Aufrufer, die `images` nicht aus einem serverseitig gerenderten Baum
   * beziehen (revalidatePath() aktualisiert dann nichts von selbst), z.B.
   * die manuelle Werk-Bild-Verknüpfung auf /work-image-reuse. */
  onChanged?: () => void;
  /** Nur für originType "work": Venue, die NEU hinzugefügten Bildern
   * zugeordnet wird (null = werkweit, jede Venue). */
  venueId?: string | null;
  /** Nur für originType "work": Liste zur Auswahl, gleichzeitig das Signal,
   * den Venue-Selector pro Bild überhaupt anzuzeigen. */
  venues?: { id: string; name: string }[];
  /** Nur für originType "person"/"ensemble": zeigt pro Bild einen Umschalter
   * "Als Veranstaltungs-Standardbild verwenden" (siehe
   * setEventFallbackImage()). */
  showEventFallbackToggle?: boolean;
  /** Claim-Portal: eigener Nutzerpfad statt der redaktionellen Standardordner. */
  storagePrefix?: string;
}) {
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cropTarget, setCropTarget] = useState<GalleryImage | null>(null);
  const [pending, startTransition] = useTransition();
  const [linkUrl, setLinkUrl] = useState("");
  const [addingLink, setAddingLink] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    if (files.length === 0) return;
    setError(null);

    setUploading(true);
    try {
      const supabase = createClient();
      // Sequenziell statt Promise.all: addGalleryImage bestimmt den
      // nächsten sort_order aus dem aktuellen Maximum — parallel liefe
      // das Risiko, dass zwei Uploads denselben sort_order lesen und
      // vergeben.
      for (const file of files) {
        if (!ACCEPTED_TYPES.includes(file.type)) {
          setError(`"${file.name}": Nur JPEG, PNG oder WebP erlaubt.`);
          continue;
        }
        if (file.size > MAX_BYTES) {
          setError(`"${file.name}": Datei zu groß (max. 5 MB).`);
          continue;
        }

        const ext = file.name.split(".").pop() ?? "jpg";
        const path_ = `${storagePrefix ?? `${originType}s`}/${crypto.randomUUID()}.${ext}`;

        const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path_, file, {
          cacheControl: "3600",
          upsert: false,
        });
        if (uploadError) throw uploadError;

        const { data } = supabase.storage.from(BUCKET).getPublicUrl(path_);
        await addGalleryImage(originType, originId, data.publicUrl, path, venueId);
        onChanged?.();
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload fehlgeschlagen.");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  async function handleAddLink() {
    const url = linkUrl.trim();
    if (!url) return;
    setError(null);
    setAddingLink(true);
    try {
      new URL(url);
    } catch {
      setError(`"${url}" ist keine gültige URL.`);
      setAddingLink(false);
      return;
    }
    try {
      await addGalleryImage(originType, originId, url, path, venueId);
      setLinkUrl("");
      onChanged?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Verknüpfen fehlgeschlagen.");
    } finally {
      setAddingLink(false);
    }
  }

  function handleDelete(imageId: string) {
    startTransition(async () => {
      try {
        await deleteGalleryImage(imageId, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Löschen fehlgeschlagen.");
      }
    });
  }

  function handleMove(imageId: string, direction: "up" | "down") {
    startTransition(async () => {
      try {
        await moveGalleryImage(originType, originId, imageId, direction, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Verschieben fehlgeschlagen.");
      }
    });
  }

  function handleSetPrimary(imageId: string) {
    startTransition(async () => {
      try {
        await setPrimaryGalleryImage(originType, originId, imageId, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Als Miniaturansicht festlegen fehlgeschlagen.");
      }
    });
  }

  function handleConfirm(imageId: string) {
    startTransition(async () => {
      try {
        await confirmGalleryImage(imageId, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Bestätigen fehlgeschlagen.");
      }
    });
  }

  function handleReject(imageId: string) {
    startTransition(async () => {
      try {
        await rejectGalleryImage(imageId, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Ablehnen fehlgeschlagen.");
      }
    });
  }

  function handleMarkTooSmall(imageId: string) {
    startTransition(async () => {
      try {
        await markGalleryImageTooSmall(imageId, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Markieren fehlgeschlagen.");
      }
    });
  }

  function handleRecheck(imageId: string) {
    startTransition(async () => {
      try {
        await recheckGalleryImage(imageId, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Erneute Prüfung fehlgeschlagen.");
      }
    });
  }

  function handleSetVenue(imageId: string, newVenueId: string) {
    startTransition(async () => {
      try {
        await setGalleryImageVenue(imageId, newVenueId || null, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Venue-Zuordnung fehlgeschlagen.");
      }
    });
  }

  function handleToggleEventFallback(imageId: string, flag: boolean) {
    startTransition(async () => {
      try {
        await setEventFallbackImage(originType, originId, imageId, flag, path);
        onChanged?.();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Standardbild-Markierung fehlgeschlagen.");
      }
    });
  }

  const sorted = [...images].sort((a, b) => a.sort_order - b.sort_order);

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-neutral-600">
          Bildergalerie {sorted.length > 0 && `(${sorted.length})`}
        </span>
        <div>
          {/* Verstecktes <input>, echter Button löst es aus — siehe
           * image-upload-field.tsx für die Begründung. `multiple`: mehrere
           * Bilder in einem Rutsch auswählen statt einzeln nacheinander. */}
          <input
            ref={fileInputRef}
            type="file"
            accept={ACCEPTED_TYPES.join(",")}
            multiple
            disabled={uploading}
            onChange={handleFileChange}
            className="hidden"
          />
          <button
            type="button"
            disabled={uploading}
            onClick={() => fileInputRef.current?.click()}
            className="rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
          >
            Bilder hochladen
          </button>
          {uploading && <span className="ml-2 text-xs text-neutral-500">Lädt hoch…</span>}
        </div>
      </div>

      <div className="flex items-center gap-2">
        <input
          type="url"
          value={linkUrl}
          onChange={(e) => setLinkUrl(e.target.value)}
          placeholder="Bild-URL einfügen…"
          disabled={addingLink}
          className="w-full max-w-xs rounded-md border border-neutral-300 px-2 py-1 text-xs disabled:opacity-50"
        />
        <button
          type="button"
          disabled={addingLink || !linkUrl.trim()}
          onClick={handleAddLink}
          className="shrink-0 rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
        >
          {addingLink ? "Fügt hinzu…" : "Per Link hinzufügen"}
        </button>
      </div>

      {error && <p className="text-xs text-red-600">{error}</p>}

      {sorted.length === 0 ? (
        <div className="flex h-24 items-center justify-center rounded-md border border-dashed border-neutral-300 bg-neutral-50 text-xs text-neutral-400">
          Noch keine Bilder. Erstes Bild hochladen legt automatisch die Miniaturansicht fest.
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {sorted.map((image, index) => {
            const crop =
              image.crop_x != null && image.crop_y != null && image.crop_width != null && image.crop_height != null
                ? { x: image.crop_x, y: image.crop_y, width: image.crop_width, height: image.crop_height }
                : null;
            const qualityBadge = QUALITY_BADGES[image.quality_status];
            const reviewBadge = REVIEW_BADGES[image.review_status];
            return (
              <div key={image.id} className="flex flex-col gap-1.5 rounded-md border border-neutral-200 p-2">
                <CroppedImagePreview src={image.source_url} crop={crop} className="rounded" />
                <div className="flex flex-wrap gap-1">
                  {index === 0 && (
                    <span className="w-fit rounded-full bg-neutral-900 px-2 py-0.5 text-[10px] font-medium text-white">
                      Miniaturansicht
                    </span>
                  )}
                  {qualityBadge && (
                    <span className={`w-fit rounded-full px-2 py-0.5 text-[10px] font-medium ${qualityBadge.className}`}>
                      {qualityBadge.label}
                    </span>
                  )}
                  {reviewBadge && (
                    <span className={`w-fit rounded-full px-2 py-0.5 text-[10px] font-medium ${reviewBadge.className}`}>
                      {reviewBadge.label}
                    </span>
                  )}
                  {image.use_as_event_fallback && (
                    <span className="w-fit rounded-full bg-violet-100 px-2 py-0.5 text-[10px] font-medium text-violet-800">
                      Veranstaltungs-Standardbild
                    </span>
                  )}
                </div>
                {venues && (
                  <select
                    value={image.venue_id ?? ""}
                    disabled={pending}
                    onChange={(e) => handleSetVenue(image.id, e.target.value)}
                    className="rounded-md border border-neutral-300 px-1.5 py-1 text-[11px] disabled:opacity-50"
                  >
                    <option value="">Alle Venues (werkweit)</option>
                    {venues.map((v) => (
                      <option key={v.id} value={v.id}>
                        {v.name}
                      </option>
                    ))}
                  </select>
                )}
                {showEventFallbackToggle && (
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => handleToggleEventFallback(image.id, !image.use_as_event_fallback)}
                    className="w-fit text-[11px] font-medium text-violet-700 hover:text-violet-900 disabled:opacity-50"
                  >
                    {image.use_as_event_fallback
                      ? "Nicht mehr als Veranstaltungs-Standardbild verwenden"
                      : "Als Veranstaltungs-Standardbild verwenden"}
                  </button>
                )}
                {(image.source_name || image.confidence_score != null) && (
                  <p className="truncate text-[10px] text-neutral-400" title={image.source_name ?? undefined}>
                    {image.source_name}
                    {image.confidence_score != null && ` · Konfidenz ${image.confidence_score.toFixed(1)}`}
                  </p>
                )}
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
                  <div className="flex gap-2">
                    <button
                      type="button"
                      disabled={pending || index === 0}
                      onClick={() => handleMove(image.id, "up")}
                      className="text-neutral-500 hover:text-neutral-900 disabled:opacity-30"
                      aria-label="Nach vorne"
                    >
                      ↑
                    </button>
                    <button
                      type="button"
                      disabled={pending || index === sorted.length - 1}
                      onClick={() => handleMove(image.id, "down")}
                      className="text-neutral-500 hover:text-neutral-900 disabled:opacity-30"
                      aria-label="Nach hinten"
                    >
                      ↓
                    </button>
                  </div>
                  {index !== 0 && (
                    <button
                      type="button"
                      disabled={pending}
                      onClick={() => handleSetPrimary(image.id)}
                      className="text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                    >
                      Als Titelbild
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={() => setCropTarget(image)}
                    className="text-neutral-600 hover:text-neutral-900"
                  >
                    Zuschneiden
                  </button>
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => handleDelete(image.id)}
                    className="text-red-600 hover:text-red-800 disabled:opacity-50"
                  >
                    Löschen
                  </button>
                </div>
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1 border-t border-neutral-100 pt-1.5 text-xs">
                  {image.review_status !== "approved" && (
                    <button
                      type="button"
                      disabled={pending}
                      onClick={() => handleConfirm(image.id)}
                      className="text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
                    >
                      Bestätigen
                    </button>
                  )}
                  {image.review_status !== "rejected" && (
                    <button
                      type="button"
                      disabled={pending}
                      onClick={() => handleReject(image.id)}
                      className="text-red-600 hover:text-red-800 disabled:opacity-50"
                    >
                      Ablehnen
                    </button>
                  )}
                  {image.quality_status !== "low_resolution" && (
                    <button
                      type="button"
                      disabled={pending}
                      onClick={() => handleMarkTooSmall(image.id)}
                      className="text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                    >
                      Als zu klein markieren
                    </button>
                  )}
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => handleRecheck(image.id)}
                    className="text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  >
                    Erneut prüfen
                  </button>
                </div>
                {image.last_checked_at && (
                  <p className="text-[10px] text-neutral-400">
                    Zuletzt geprüft: {new Date(image.last_checked_at).toLocaleString("de-DE")}
                  </p>
                )}
              </div>
            );
          })}
        </div>
      )}

      {cropTarget && (
        <CropTool
          src={cropTarget.source_url}
          initialCrop={
            cropTarget.crop_x != null && cropTarget.crop_y != null && cropTarget.crop_width != null && cropTarget.crop_height != null
              ? { x: cropTarget.crop_x, y: cropTarget.crop_y, width: cropTarget.crop_width, height: cropTarget.crop_height }
              : null
          }
          onSave={(crop) => saveGalleryImageCrop(cropTarget.id, crop, path)}
          onReset={() => saveGalleryImageCrop(cropTarget.id, null, path)}
          onClose={() => setCropTarget(null)}
        />
      )}
    </div>
  );
}
