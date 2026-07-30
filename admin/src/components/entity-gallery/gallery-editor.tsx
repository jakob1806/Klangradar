"use client";

import { useRef, useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  addGalleryImage,
  deleteGalleryImage,
  moveGalleryImage,
  setPrimaryGalleryImage,
  type GalleryImage,
  type GalleryOriginType,
} from "@/lib/gallery-actions";
import { CropTool } from "./crop-tool";
import { CroppedImagePreview } from "./cropped-image-preview";

const BUCKET = "entity-photos";
const MAX_BYTES = 5 * 1024 * 1024;
const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];

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
}: {
  originType: GalleryOriginType;
  originId: string;
  path: string;
  images: GalleryImage[];
}) {
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cropTarget, setCropTarget] = useState<GalleryImage | null>(null);
  const [pending, startTransition] = useTransition();
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
        const path_ = `${originType}s/${crypto.randomUUID()}.${ext}`;

        const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path_, file, {
          cacheControl: "3600",
          upsert: false,
        });
        if (uploadError) throw uploadError;

        const { data } = supabase.storage.from(BUCKET).getPublicUrl(path_);
        await addGalleryImage(originType, originId, data.publicUrl, path);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload fehlgeschlagen.");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  function handleDelete(imageId: string) {
    startTransition(async () => {
      try {
        await deleteGalleryImage(imageId, path);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Löschen fehlgeschlagen.");
      }
    });
  }

  function handleMove(imageId: string, direction: "up" | "down") {
    startTransition(async () => {
      try {
        await moveGalleryImage(originType, originId, imageId, direction, path);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Verschieben fehlgeschlagen.");
      }
    });
  }

  function handleSetPrimary(imageId: string) {
    startTransition(async () => {
      try {
        await setPrimaryGalleryImage(originType, originId, imageId, path);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Als Miniaturansicht festlegen fehlgeschlagen.");
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
            return (
              <div key={image.id} className="flex flex-col gap-1.5 rounded-md border border-neutral-200 p-2">
                <CroppedImagePreview src={image.source_url} crop={crop} className="rounded" />
                {index === 0 && (
                  <span className="w-fit rounded-full bg-neutral-900 px-2 py-0.5 text-[10px] font-medium text-white">
                    Miniaturansicht
                  </span>
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
              </div>
            );
          })}
        </div>
      )}

      {cropTarget && (
        <CropTool
          imageId={cropTarget.id}
          src={cropTarget.source_url}
          initialCrop={
            cropTarget.crop_x != null && cropTarget.crop_y != null && cropTarget.crop_width != null && cropTarget.crop_height != null
              ? { x: cropTarget.crop_x, y: cropTarget.crop_y, width: cropTarget.crop_width, height: cropTarget.crop_height }
              : null
          }
          path={path}
          onClose={() => setCropTarget(null)}
        />
      )}
    </div>
  );
}
