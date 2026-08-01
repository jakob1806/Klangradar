#!/usr/bin/env node

/** Einmaliger Rehost bereits freigegebener photo_url-Werte, die direkt auf
 * einen Drittanbieter zeigen (kein eigener storage_path) — v.a. Wikimedia
 * Commons blockt bei vielen gleichzeitig geladenen Thumbnails (Galerie/
 * App-Liste) mit HTTP 429, das Bild bleibt dann leer. Ruft den neuen
 * rehostCandidates-Modus von enrich-entity-images in Batches auf: lädt
 * jedes Bild einmal herunter, legt es re-encodiert im eigenen Storage ab
 * und stellt die Entität auf den neuen Link um (kein Review-Fall, siehe
 * Kommentar in der Edge Function).
 */
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const valueOf = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};

const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!baseUrl || !key) {
  console.error("SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY (oder ANON_KEY) müssen gesetzt sein.");
  process.exit(2);
}

const candidatesFile = valueOf("--candidates-file", null);
if (!candidatesFile) {
  console.error("--candidates-file <pfad.json> ist erforderlich.");
  process.exit(2);
}
const batchSize = Number(valueOf("--batch-size", 4));

const allCandidates = JSON.parse(readFileSync(candidatesFile, "utf8"));

console.log(`${allCandidates.length} Kandidaten, Batchgröße ${batchSize}`);

const totals = { rehosted: 0, skipped: 0, errors: [] };

for (let offset = 0; offset < allCandidates.length; offset += batchSize) {
  const batch = allCandidates.slice(offset, offset + batchSize);
  let result;
  try {
    const response = await fetch(`${baseUrl.replace(/\/$/, "")}/functions/v1/enrich-entity-images`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
      body: JSON.stringify({ rehostCandidates: batch }),
      signal: AbortSignal.timeout(180_000),
    });
    const text = await response.text();
    try { result = JSON.parse(text); } catch { result = { error: text }; }
    if (!response.ok) result.error ??= `HTTP ${response.status}`;
  } catch (error) {
    result = { error: error instanceof Error ? error.message : String(error) };
  }

  if (result.error) {
    totals.errors.push(`Batch ${offset}-${offset + batch.length}: ${result.error}`);
    console.log(`Batch ${offset + 1}-${offset + batch.length}/${allCandidates.length}: FEHLER — ${result.error}`);
  } else {
    totals.rehosted += result.rehosted ?? 0;
    totals.skipped += result.skipped ?? 0;
    totals.errors.push(...(result.errors ?? []));
    console.log(`Batch ${offset + 1}-${offset + batch.length}/${allCandidates.length}: rehosted=${result.rehosted} skipped=${result.skipped} errors=${(result.errors ?? []).length}`);
  }
}

console.log(`\nGESAMT: rehosted=${totals.rehosted} skipped=${totals.skipped} errors=${totals.errors.length}`);
if (totals.errors.length > 0) {
  console.log("\nFehlerdetails:");
  for (const e of totals.errors) console.log(" -", e);
}
