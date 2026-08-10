"use client";

import { useRef, useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";
import { ConfirmButton } from "@/components/confirm-button";
import { CroppedImagePreview } from "@/components/entity-gallery/cropped-image-preview";
import { addGroupImage, removeGroupImage } from "./actions";

const BUCKET = "entity-photos";
const MAX_BYTES = 5 * 1024 * 1024;
const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];

/** Ein Bild hochladen und als Miniaturansicht bei JEDEM Termin der Gruppe
 * eintragen (siehe addGroupImage) — bewusst kein voller Galerie-Editor wie
 * bei Personen/Ensembles/Venues (component/entity-gallery/gallery-editor.tsx):
 * hier gibt es kein einzelnes "Gruppen"-Objekt mit eigener Bilder-Tabelle,
 * jeder Upload wirkt sofort auf alle Mitgliedsevents, ein Verwalten/
 * Neuordnen einer eigenen Gruppen-Galerie ergibt datenmodellseitig keinen Sinn.
 *
 * Nutzeranfrage: "in der Bearbeitungsansicht soll angezeigt werden, wenn
 * schon ein Bild für die Gruppe vorhanden ist, und auch welches — ähnlich
 * wie bei normalen Veranstaltungen" — currentImageUrl/coverage kommen dazu
 * serverseitig aus page.tsx (die unter den Terminen häufigste sourceUrl an
 * Position 0), hier nur Anzeige + Entfernen-Möglichkeit, analog zur
 * 16:9-Vorschau in der normalen Event-Galerie (CroppedImagePreview). */
export function GroupImageUploader({
  groupId,
  currentImageUrl,
  coverage,
  memberCount,
}: {
  groupId: string;
  currentImageUrl: string | null;
  coverage: number;
  memberCount: number;
}) {
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [removePending, startRemoveTransition] = useTransition();
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

    setUploading(true);
    try {
      const supabase = createClient();
      const ext = file.name.split(".").pop() ?? "jpg";
      const path = `event-groups/${crypto.randomUUID()}.${ext}`;

      const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, file, {
        cacheControl: "3600",
        upsert: false,
      });
      if (uploadError) throw uploadError;

      const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
      await addGroupImage(groupId, data.publicUrl);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload fehlgeschlagen.");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  return (
    <div className="flex flex-col gap-3">
      {currentImageUrl && (
        <div className="flex items-center gap-3">
          <CroppedImagePreview src={currentImageUrl} crop={null} className="w-32 shrink-0 rounded-lg" />
          <div className="flex flex-col gap-1 text-xs">
            <span className="font-medium text-neutral-700">
              Gruppenbild vorhanden
              {memberCount > 0 && ` — bei ${coverage}/${memberCount} Terminen als Titelbild hinterlegt`}
            </span>
            {coverage < memberCount && (
              <span className="text-amber-600">
                Nicht bei allen Terminen — neu hochgeladen erneuern, um es überall zu übernehmen.
              </span>
            )}
            <ConfirmButton
              action={removeGroupImage.bind(null, groupId, currentImageUrl)}
              confirmMessage="Gruppenbild bei allen Terminen entfernen? Eigene Event-Bilder bleiben erhalten."
              label="Entfernen"
              pendingLabel="Entferne…"
              className="w-fit text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
            />
          </div>
        </div>
      )}
      <div className="flex items-center gap-3">
        <input
          ref={fileInputRef}
          type="file"
          accept={ACCEPTED_TYPES.join(",")}
          disabled={uploading || removePending}
          onChange={handleFileChange}
          className="hidden"
        />
        <button
          type="button"
          disabled={uploading || removePending}
          onClick={() => fileInputRef.current?.click()}
          className="rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
        >
          {uploading ? "Lädt hoch…" : currentImageUrl ? "Anderes Gruppenbild hochladen" : "Gruppenbild hochladen"}
        </button>
        {error && <span className="text-xs text-red-600">{error}</span>}
      </div>
    </div>
  );
}
