"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { addGalleryImage } from "@/lib/gallery-actions";

const BUCKET = "entity-photos";
const MAX_BYTES = 5 * 1024 * 1024;
const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];

/** Ordnet EIN oder mehrere Bilder (Datei-Upload oder Link) allen aktuell
 * ausgewählten Veranstaltungen gleichzeitig zu — dieselben Wege wie überall
 * sonst in der Bildergalerie (siehe entity-gallery/gallery-editor.tsx),
 * hier nur über mehrere Events hinweg statt nur eines. Kein GalleryEditor-
 * Wiederverwendung, weil der auf genau einen originId ausgelegt ist —
 * stattdessen addGalleryImage() direkt pro Event in einer Schleife
 * aufgerufen (dieselbe hochgeladene Datei/URL, aber je Event eine eigene
 * images-Zeile, damit Zuschnitt/Reihenfolge/Ablehnen pro Event unabhängig
 * bleiben). */
export function BulkEventImageAdd({ eventIds }: { eventIds: string[] }) {
  const router = useRouter();
  const [linkUrl, setLinkUrl] = useState("");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function applyUrlToAllEvents(url: string, label: string) {
    setBusy(true);
    setError(null);
    setDone(null);
    let applied = 0;
    try {
      for (const eventId of eventIds) {
        await addGalleryImage("event", eventId, url, `/events/${eventId}`);
        applied++;
        setProgress(`${label}: ${applied} / ${eventIds.length} Veranstaltungen`);
      }
      setDone(`${label} für ${eventIds.length} Veranstaltung${eventIds.length === 1 ? "" : "en"} hinzugefügt.`);
      router.refresh();
    } catch (e) {
      setError(
        `${e instanceof Error ? e.message : "Fehlgeschlagen"} (${applied}/${eventIds.length} bereits übernommen)`,
      );
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  async function handleAddLink() {
    const url = linkUrl.trim();
    if (!url) return;
    try {
      new URL(url);
    } catch {
      setError(`"${url}" ist keine gültige URL.`);
      return;
    }
    await applyUrlToAllEvents(url, "Bild-Link");
    setLinkUrl("");
  }

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    if (files.length === 0) return;
    setError(null);
    setBusy(true);
    try {
      const supabase = createClient();
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
        const storagePath = `events/${crypto.randomUUID()}.${ext}`;
        const { error: uploadError } = await supabase.storage.from(BUCKET).upload(storagePath, file, {
          cacheControl: "3600",
          upsert: false,
        });
        if (uploadError) throw uploadError;
        const { data } = supabase.storage.from(BUCKET).getPublicUrl(storagePath);
        setBusy(true);
        await applyUrlToAllEvents(data.publicUrl, `"${file.name}"`);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload fehlgeschlagen.");
    } finally {
      setBusy(false);
      setProgress(null);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  return (
    <div className="rounded-lg border border-neutral-200 bg-white p-4">
      <p className="text-sm font-medium text-neutral-900">Bild für alle ausgewählten Veranstaltungen</p>
      <p className="mt-1 text-xs text-neutral-500">
        Wird zusätzlich zur bestehenden Bildergalerie jeder ausgewählten Veranstaltung hinzugefügt (Titelbild, falls
        dort noch keins vorhanden ist).
      </p>

      <div className="mt-3 flex items-center gap-2">
        <input
          type="url"
          value={linkUrl}
          onChange={(e) => setLinkUrl(e.target.value)}
          placeholder="Bild-URL einfügen…"
          disabled={busy}
          className="w-full max-w-xs rounded-md border border-neutral-300 px-2 py-1.5 text-sm disabled:opacity-50"
        />
        <button
          type="button"
          disabled={busy || !linkUrl.trim()}
          onClick={handleAddLink}
          className="shrink-0 rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
        >
          Per Link für alle hinzufügen
        </button>
      </div>

      <div className="mt-2">
        <input
          ref={fileInputRef}
          type="file"
          accept={ACCEPTED_TYPES.join(",")}
          multiple
          disabled={busy}
          onChange={handleFileChange}
          className="hidden"
        />
        <button
          type="button"
          disabled={busy}
          onClick={() => fileInputRef.current?.click()}
          className="rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
        >
          Bilder hochladen für alle
        </button>
      </div>

      {progress && <p className="mt-2 text-xs text-neutral-500">{progress}</p>}
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
      {done && !error && <p className="mt-2 text-xs text-emerald-700">{done}</p>}
    </div>
  );
}
