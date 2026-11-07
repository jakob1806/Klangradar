"use client";

import { useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";
import { setSeatingPlan } from "@/lib/seating-plan-actions";

const BUCKET = "entity-photos";
const MAX_BYTES = 15 * 1024 * 1024;

/** Saalplan hochladen (Bild/PDF) oder per Link setzen. Erscheint in der App
 * auf der Spielstättenseite unter „Saalplan“ und im Ticket-Blatt. */
export function SeatingPlanEditor({ venueId, initialUrl }: { venueId: string; initialUrl: string | null }) {
  const [url, setUrl] = useState(initialUrl);
  const [link, setLink] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [pending, startTransition] = useTransition();
  const isPdf = url?.toLowerCase().split("?")[0].endsWith(".pdf");

  function save(next: string | null) {
    setError(null);
    startTransition(async () => {
      const result = await setSeatingPlan(venueId, next);
      if (result.error) setError(result.error);
      else { setUrl(next); setLink(""); }
    });
  }

  async function upload(file: File) {
    if (file.size > MAX_BYTES) { setError("Datei ist größer als 15 MB."); return; }
    if (!/^(image\/(jpeg|png|webp)|application\/pdf)$/.test(file.type)) { setError("Nur JPG, PNG, WebP oder PDF."); return; }
    setBusy(true); setError(null);
    try {
      const ext = file.name.split(".").pop()?.toLowerCase() ?? "pdf";
      const path = `seating-plans/${venueId}/${crypto.randomUUID()}.${ext}`;
      const supabase = createClient();
      const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, file, { contentType: file.type, upsert: false });
      if (uploadError) throw uploadError;
      save(supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload fehlgeschlagen.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium text-neutral-900">Saalplan</h2>
        <label className="cursor-pointer rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:bg-neutral-50">
          {busy ? "Lädt hoch…" : url ? "Ersetzen" : "Hochladen"}
          <input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" className="hidden"
            disabled={busy || pending} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
        </label>
      </div>
      {url ? (
        <div className="rounded-md border border-neutral-200 p-2">
          {isPdf ? (
            <a href={url} target="_blank" rel="noreferrer" className="text-sm text-blue-700 underline">Saalplan (PDF) öffnen</a>
          ) : (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={url} alt="Saalplan" className="max-h-80 w-full rounded object-contain" />
          )}
          <button type="button" onClick={() => save(null)} disabled={pending}
            className="mt-2 text-xs font-medium text-red-700 hover:underline">Saalplan entfernen</button>
        </div>
      ) : (
        <p className="text-xs text-neutral-500">Noch kein Saalplan. Bild oder PDF hochladen oder Link vom Haus einfügen.</p>
      )}
      <div className="flex gap-2">
        <input value={link} onChange={(e) => setLink(e.target.value)} placeholder="https://… (Link zum Saalplan)"
          className="min-w-0 flex-1 rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
        <button type="button" disabled={!link.trim() || pending} onClick={() => save(link)}
          className="shrink-0 rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 disabled:opacity-50">
          Link setzen
        </button>
      </div>
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  );
}
