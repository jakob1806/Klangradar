"use client";

import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

const BUCKET = "entity-photos";
const MAX_BYTES = 5 * 1024 * 1024;
const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];
// Gleiche Mindestauflösung wie die Bilder-Pipeline (MIN_WIDTH/MIN_HEIGHT in
// backend/supabase/functions/_shared/imagePipeline.ts) — Bugfix: dieser
// Upload-Weg prüfte bisher NUR Dateityp/-größe, kein Bildmaß. Live
// beobachtet: ein 225×225px-Foto (11,5 KB) landete so unbemerkt als
// venues.photo_url und scheiterte erst später, an ganz anderer Stelle
// (Bilder-Recherche-Fallback auf dieses Venue-Foto), mit einer für die
// Redaktion kryptischen Fehlermeldung.
const MIN_WIDTH = 640;
const MIN_HEIGHT = 480;

function readImageDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("Datei konnte nicht als Bild gelesen werden."));
    };
    img.src = url;
  });
}

/** Datei-Upload für Venue-/Ensemble-/Festival-/Personen-Fotos, direkt aus
 * dem Admin-Formular heraus (statt bisher nur eine externe URL einzutragen).
 * Lädt clientseitig in den "entity-photos"-Storage-Bucket hoch (public=true,
 * Schreibzugriff über storage.objects-RLS auf is_admin_or_editor()
 * beschränkt, siehe 20260825000001_entity_photo_uploads.sql) und schreibt
 * die resultierende öffentliche URL in ein verstecktes Formularfeld — die
 * Server Actions der jeweiligen Entität kennen weiterhin nur eine
 * photo_url-Zeichenkette, unabhängig davon, ob sie hochgeladen oder
 * manuell eingetragen wurde.
 *
 * shape="circle" für Personen (rundes Profilfoto), "rounded" für
 * Venues/Ensembles/Festivals (rechteckiges Vorschaubild). */
export function ImageUploadField({
  name,
  initialUrl,
  entityType,
  shape = "rounded",
  label = "Foto",
}: {
  name: string;
  initialUrl?: string | null;
  entityType: string;
  shape?: "circle" | "rounded";
  label?: string;
}) {
  const [url, setUrl] = useState(initialUrl ?? "");
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setError(null);

    if (!ACCEPTED_TYPES.includes(file.type)) {
      setError("Nur JPEG, PNG oder WebP erlaubt.");
      return;
    }
    if (file.size > MAX_BYTES) {
      setError("Datei zu groß (max. 5 MB).");
      return;
    }

    try {
      const { width, height } = await readImageDimensions(file);
      if (width < MIN_WIDTH || height < MIN_HEIGHT) {
        setError(`Bild zu klein (${width}×${height}px) — mindestens ${MIN_WIDTH}×${MIN_HEIGHT}px nötig, sonst wirkt es später hochskaliert unscharf.`);
        return;
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Bild konnte nicht gelesen werden.");
      return;
    }

    setUploading(true);
    try {
      const supabase = createClient();
      const ext = file.name.split(".").pop() ?? "jpg";
      const path = `${entityType}/${crypto.randomUUID()}.${ext}`;

      const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, file, {
        cacheControl: "3600",
        upsert: false,
      });
      if (uploadError) throw uploadError;

      const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
      setUrl(data.publicUrl);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload fehlgeschlagen.");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  // shape="circle" bleibt bewusst rund (Profilfoto-Avatar-Konvention, kein
  // dekoratives Abrunden) — nur der Rechteck-Fall folgt dem eckigen
  // Swiss/International-Redesign.
  const previewClass =
    shape === "circle" ? "h-20 w-20 rounded-full object-cover" : "h-20 w-32 object-cover";
  const placeholderClass = shape === "circle" ? "h-20 w-20 rounded-full" : "h-20 w-32";

  return (
    <div className="flex flex-col gap-1.5">
      <span className="type-label !text-neutral-600">{label}</span>
      <div className="flex items-center gap-3">
        {url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={url} alt="" className={`${previewClass} border border-neutral-300 bg-neutral-50`} />
        ) : (
          <div className={`${placeholderClass} flex items-center justify-center border border-dashed border-neutral-300 bg-neutral-50 text-xs text-neutral-400`}>
            Kein Foto
          </div>
        )}
        <div className="flex flex-col gap-1">
          {/* Natives <input type="file"> selbst versteckt und über einen
           * echten, beschrifteten Button ausgelöst — die bisherige
           * file:-Pseudoklassen-Styling-Variante blieb browserabhängig ein
           * winziges, kaum sichtbares Element ohne erkennbare Beschriftung
           * (Nutzerfeedback). */}
          <input
            ref={fileInputRef}
            type="file"
            accept={ACCEPTED_TYPES.join(",")}
            disabled={uploading}
            onChange={handleFileChange}
            className="hidden"
          />
          <button
            type="button"
            disabled={uploading}
            onClick={() => fileInputRef.current?.click()}
            className="self-start border border-neutral-300 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:border-[#171717] hover:text-[#171717] disabled:opacity-50"
          >
            {url ? "Foto ersetzen" : "Foto auswählen"}
          </button>
          {uploading && <span className="text-xs text-neutral-500">Lädt hoch…</span>}
          {error && <span className="text-xs text-red-600">{error}</span>}
          {url && !uploading && (
            <button
              type="button"
              onClick={() => setUrl("")}
              className="self-start text-xs text-neutral-500 hover:text-red-600"
            >
              Foto entfernen
            </button>
          )}
        </div>
      </div>
      <input type="hidden" name={name} value={url} />
    </div>
  );
}
