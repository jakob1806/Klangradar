"use client";

// Ersatz für das bisherige rohe cover_image_url-Textfeld (Nutzerwunsch:
// Titelbild soll wie bei Personen/Venues/Ensembles/Werken über die
// Bilder-Pipeline laufen — Link-Recherche oder Upload — statt eines von
// Hand eingetippten, potenziell nicht dauerhaft erreichbaren Links).
// Bewusst kein "KI recherchieren"-Button: eine redaktionelle Sammlung ist
// kein öffentlich bekanntes, auffindbares Objekt (siehe research-entity-
// image/index.ts, case "editorial_collection") — nur Link oder Upload.
// Bewusst EIN Bild statt einer Galerie/Slideshow (anders als bei Personen/
// Ensembles/Werken): das Titelbild ist strukturell ein einzelnes Feld für
// die Übersichtskarte, kein eigener Profil-Bereich.

import { useRef, useState } from "react";
import { commitEntityImage, commitManualImage, searchEntityImage, type ImageSearchResult } from "../../image-research/actions";

export function CoverImagePicker({
  collectionId,
  initialCoverUrl,
}: {
  collectionId: string;
  initialCoverUrl: string | null;
}) {
  const [coverUrl, setCoverUrl] = useState(initialCoverUrl);
  const [urlInput, setUrlInput] = useState("");
  const [preview, setPreview] = useState<ImageSearchResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function handleFetchFromLink() {
    const url = urlInput.trim();
    if (!url) return;
    setBusy(true);
    setError(null);
    setPreview(null);
    const result = await searchEntityImage("editorial_collection", collectionId, url);
    setBusy(false);
    if (result.found) setPreview(result);
    else setError(result.error ?? "Nichts gefunden.");
  }

  async function handleTakeOverPreview() {
    if (!preview?.imageUrl) return;
    setBusy(true);
    setError(null);
    const res = await commitEntityImage("editorial_collection", collectionId, {
      sourceUrl: preview.imageUrl,
      sourceName: preview.sourceName,
      sourcePageUrl: preview.sourcePageUrl,
      matchReason: preview.matchReason,
      licenseStatus: "confirmed_licensed",
    });
    setBusy(false);
    if (res.committed) {
      setCoverUrl(preview.imageUrl);
      setPreview(null);
      setUrlInput("");
    } else {
      setError(res.error ?? "Übernehmen fehlgeschlagen.");
    }
  }

  async function handleFileUpload() {
    if (!selectedFile) return;
    setBusy(true);
    setError(null);
    const base64 = await fileToBase64(selectedFile);
    const res = await commitManualImage("editorial_collection", collectionId, base64, "confirmed_licensed");
    setBusy(false);
    if (res.committed) {
      // Best effort: die tatsächlich gespeicherte Storage-URL kommt erst
      // beim nächsten Laden der Seite (Server Component) — bis dahin
      // zeigen wir die lokale Datei direkt als Vorschau.
      setCoverUrl(URL.createObjectURL(selectedFile));
      setSelectedFile(null);
      if (fileInputRef.current) fileInputRef.current.value = "";
    } else {
      setError(res.error ?? "Upload fehlgeschlagen.");
    }
  }

  return (
    <div className="max-w-xl">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">Titelbild</p>
      {coverUrl && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={coverUrl}
          alt=""
          className="mt-2 h-40 w-full rounded-md border border-neutral-200 object-cover bg-neutral-50"
        />
      )}

      <div className="mt-3 flex gap-2">
        <input
          value={urlInput}
          onChange={(e) => setUrlInput(e.target.value)}
          placeholder="https://… (Seite mit Bild)"
          className="flex-1 rounded-md border border-neutral-300 px-3 py-1.5 text-sm outline-none focus:border-neutral-500"
        />
        <button
          type="button"
          disabled={!urlInput.trim() || busy}
          onClick={handleFetchFromLink}
          className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-100 disabled:opacity-50"
        >
          Bild von Link holen
        </button>
      </div>

      {preview?.imageUrl && (
        <div className="mt-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={
              preview.imagePreviewBase64
                ? `data:${preview.imagePreviewMimeType ?? "image/jpeg"};base64,${preview.imagePreviewBase64}`
                : preview.imageUrl
            }
            alt=""
            className="max-h-48 w-full rounded-md border border-neutral-200 object-contain bg-neutral-50"
          />
          <button
            type="button"
            disabled={busy}
            onClick={handleTakeOverPreview}
            className="mt-2 rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
          >
            {busy ? "Speichere…" : "Als Titelbild übernehmen"}
          </button>
        </div>
      )}

      <div className="mt-3">
        <label className="text-xs font-medium uppercase tracking-wide text-neutral-400">Oder: Datei hochladen</label>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          disabled={busy}
          onChange={(e) => setSelectedFile(e.target.files?.[0] ?? null)}
          className="hidden"
        />
        <div className="mt-1 flex items-center gap-2">
          <button
            type="button"
            disabled={busy}
            onClick={() => fileInputRef.current?.click()}
            className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-100 disabled:opacity-50"
          >
            Datei auswählen…
          </button>
          {selectedFile && (
            <>
              <span className="truncate text-xs text-neutral-600">{selectedFile.name}</span>
              <button
                type="button"
                disabled={busy}
                onClick={handleFileUpload}
                className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
              >
                {busy ? "Lade hoch…" : "Hochladen"}
              </button>
            </>
          )}
        </div>
      </div>

      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
    </div>
  );
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      resolve(result.split(",")[1] ?? "");
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
