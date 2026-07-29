"use client";

import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { addGroupImage } from "./actions";

const BUCKET = "entity-photos";
const MAX_BYTES = 5 * 1024 * 1024;
const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];

/** Ein Bild hochladen und als Miniaturansicht bei JEDEM Termin der Gruppe
 * eintragen (siehe addGroupImage) — bewusst kein voller Galerie-Editor wie
 * bei Personen/Ensembles/Venues (component/entity-gallery/gallery-editor.tsx):
 * hier gibt es kein einzelnes "Gruppen"-Objekt mit eigener Bilder-Tabelle,
 * jeder Upload wirkt sofort auf alle Mitgliedsevents, ein Verwalten/
 * Neuordnen einer eigenen Gruppen-Galerie ergibt datenmodellseitig keinen Sinn. */
export function GroupImageUploader({ groupId }: { groupId: string }) {
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setError(null);
    setDone(false);

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
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload fehlgeschlagen.");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  return (
    <div className="flex items-center gap-3">
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
        className="rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
      >
        {uploading ? "Lädt hoch…" : "Gruppenbild hochladen"}
      </button>
      {done && <span className="text-xs text-emerald-700">Bei allen Terminen eingetragen.</span>}
      {error && <span className="text-xs text-red-600">{error}</span>}
    </div>
  );
}
