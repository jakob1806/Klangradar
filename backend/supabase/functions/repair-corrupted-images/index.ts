// Einmaliges Reparatur-Werkzeug (Nutzerbug: "'ähnliche ensembles' ... haben
// keine miniaturbilder, diese sind immer schwarz"). Root Cause bei der
// Diagnose live bestätigt: ein WASM-Buffer-Aliasing-Bug in decodeImage()
// (siehe imagePipeline.ts, mittlerweile per .slice() gefixt) hat über
// Monate hinweg rohe, nicht als WebP kodierte Pixel-Bytes in den Storage
// geschrieben statt echter WebP-Dateien — betraf beim Scan 313 von 329
// gespeicherten images-Zeilen (Events/Venues/Ensembles/Personen), nicht
// nur Ensembles. Der Fix in decodeImage() verhindert nur NEUE Fälle; die
// schon im Storage liegenden kaputten Dateien müssen einzeln neu
// heruntergeladen und mit der jetzt korrekten Pipeline neu kodiert werden.
//
// Schreibt bewusst auf denselben storage_path/thumbnail_path (upsert),
// damit alle bestehenden Referenzen (images.storage_path, das alte
// ensembles.photo_url, o.ä.) unverändert gültig bleiben — nur der
// Dateiinhalt wird ersetzt.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  BUCKET,
  decodeImage,
  downloadImage,
  ensureMagickReady,
  sha256,
} from "../_shared/imagePipeline.ts";

interface RepairResult {
  id: string;
  status: "repaired" | "already_valid" | "download_failed" | "decode_failed" | "upload_failed";
  detail?: string;
}

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Ungültiger Request-Body" }), { status: 400 });
  }

  const imageIds = Array.isArray(body.imageIds)
    ? (body.imageIds as unknown[]).filter((x): x is string => typeof x === "string")
    : [];
  if (imageIds.length === 0) {
    return new Response(JSON.stringify({ error: "imageIds (string[]) ist erforderlich" }), { status: 400 });
  }
  if (imageIds.length > 25) {
    return new Response(JSON.stringify({ error: "Maximal 25 imageIds pro Aufruf (Worker-Zeitlimit)" }), { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  await ensureMagickReady();

  const results: RepairResult[] = [];

  for (const id of imageIds) {
    const { data: row } = await supabase
      .from("images")
      .select("id, storage_path, thumbnail_path, source_url, original_image_url, origin_type")
      .eq("id", id)
      .maybeSingle();

    if (!row || !row.storage_path) {
      results.push({ id, status: "download_failed", detail: "Zeile oder storage_path fehlt" });
      continue;
    }

    const sourceUrl = row.original_image_url ?? row.source_url;
    if (!sourceUrl) {
      results.push({ id, status: "download_failed", detail: "keine source_url/original_image_url" });
      continue;
    }

    const bytes = await downloadImage(sourceUrl);
    if (!bytes) {
      results.push({ id, status: "download_failed", detail: sourceUrl });
      continue;
    }

    const decoded = decodeImage(bytes);
    if (!decoded || decoded.width <= 0 || decoded.height <= 0) {
      results.push({ id, status: "decode_failed", detail: sourceUrl });
      continue;
    }

    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(row.storage_path, decoded.webpBytes, { contentType: "image/webp", upsert: true });
    if (uploadError) {
      results.push({ id, status: "upload_failed", detail: uploadError.message });
      continue;
    }

    let thumbnailPath = row.thumbnail_path;
    if (thumbnailPath) {
      const { error: thumbError } = await supabase.storage
        .from(BUCKET)
        .upload(thumbnailPath, decoded.thumbnailBytes, { contentType: "image/webp", upsert: true });
      if (thumbError) {
        // Hauptbild ist schon repariert — Thumbnail-Pfad neu vergeben statt
        // den ganzen Fix scheitern zu lassen.
        thumbnailPath = `${row.origin_type}/${crypto.randomUUID()}-thumb.webp`;
        await supabase.storage.from(BUCKET).upload(thumbnailPath, decoded.thumbnailBytes, {
          contentType: "image/webp",
          upsert: false,
        });
      }
    } else {
      thumbnailPath = `${row.origin_type}/${crypto.randomUUID()}-thumb.webp`;
      await supabase.storage.from(BUCKET).upload(thumbnailPath, decoded.thumbnailBytes, {
        contentType: "image/webp",
        upsert: false,
      });
    }

    const contentHash = await sha256(decoded.webpBytes);
    await supabase.from("images").update({
      thumbnail_path: thumbnailPath,
      width: decoded.width,
      height: decoded.height,
      mime_type: "image/webp",
      phash: decoded.phash,
      content_hash: contentHash,
      file_size_bytes: decoded.webpBytes.byteLength,
      last_checked_at: new Date().toISOString(),
    }).eq("id", id);

    results.push({ id, status: "repaired" });
  }

  return new Response(JSON.stringify({ results }), {
    headers: { "Content-Type": "application/json" },
  });
});
