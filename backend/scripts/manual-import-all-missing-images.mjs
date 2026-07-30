#!/usr/bin/env node

import { readFileSync } from "node:fs";

/** Einmaliger, explizit manueller Voll-Lauf. Holt die aktuell bildlosen IDs
 * aus Supabase und übergibt jede ID genau einmal in kleinen, kontrollierten
 * Batches an enrich-entity-images. Kein Scheduler und kein Cronjob beteiligt.
 */
const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!baseUrl || !key) throw new Error("Supabase-Umgebungsvariablen fehlen.");

const batchSize = Math.max(1, Math.min(20, Number(process.env.IMAGE_IMPORT_BATCH_SIZE ?? 8)));
const requestedTypes = new Set(
  (process.env.IMAGE_IMPORT_TYPES ?? "venue,ensemble,person")
    .split(",").map((value) => value.trim()).filter(Boolean),
);
const kinds = [
  { type: "venue", table: "venues", name: "name" },
  { type: "ensemble", table: "ensembles", name: "name" },
  { type: "person", table: "persons", name: "full_name" },
].filter((kind) => requestedTypes.has(kind.type));
const headers = { apikey: key, Authorization: `Bearer ${key}` };
const totals = { processed: 0, autoApplied: 0, queuedForReview: 0, errors: 0 };
const retryNames = process.env.IMAGE_IMPORT_NAMES_FILE
  ? JSON.parse(readFileSync(process.env.IMAGE_IMPORT_NAMES_FILE, "utf8"))
  : null;

for (const kind of kinds) {
  const query = new URL(`${baseUrl.replace(/\/$/, "")}/rest/v1/${kind.table}`);
  query.searchParams.set("select", `id,${kind.name}`);
  query.searchParams.set("photo_url", "is.null");
  query.searchParams.set("order", `${kind.name}.asc`);
  query.searchParams.set("limit", "1000");
  const inventoryResponse = await fetch(query, { headers, signal: AbortSignal.timeout(30_000) });
  if (!inventoryResponse.ok) throw new Error(`${kind.table}: Inventar fehlgeschlagen (${inventoryResponse.status})`);
  let rows = await inventoryResponse.json();
  if (retryNames?.[kind.type]) {
    const selectedNames = new Set(retryNames[kind.type]);
    rows = rows.filter((row) => selectedNames.has(row[kind.name]));
  }
  console.log(`\n${kind.type.toUpperCase()}: ${rows.length} bildlose Datensätze`);

  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    let response;
    let result;
    try {
      response = await fetch(`${baseUrl.replace(/\/$/, "")}/functions/v1/enrich-entity-images`, {
        method: "POST",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({
          type: kind.type,
          limit: batch.length,
          onlyMissing: true,
          minConfidence: 0.85,
          entityIds: batch.map((row) => row.id),
          fastFallback: process.env.IMAGE_IMPORT_FAST_FALLBACK === "1",
        }),
        signal: AbortSignal.timeout(125_000),
      });
      const text = await response.text();
      try { result = JSON.parse(text); } catch { result = { error: text }; }
    } catch (error) {
      response = { ok: false, status: "client_timeout" };
      result = { error: error instanceof Error ? error.message : String(error) };
    }
    const stats = result[kind.table] ?? {};
    totals.processed += stats.found ?? 0;
    totals.autoApplied += stats.autoApplied ?? 0;
    totals.queuedForReview += stats.queuedForReview ?? 0;
    totals.errors += (stats.errors ?? []).length + (response.ok ? 0 : 1);
    console.log(JSON.stringify({
      type: kind.type,
      batch: `${offset + 1}-${offset + batch.length}/${rows.length}`,
      names: batch.map((row) => row[kind.name]),
      found: stats.found ?? 0,
      autoApplied: stats.autoApplied ?? 0,
      queuedForReview: stats.queuedForReview ?? 0,
      errors: stats.errors ?? (response.ok ? [] : [result.error ?? response.status]),
    }));
    if (!response.ok) await new Promise((resolve) => setTimeout(resolve, 2_000));
  }
}

console.log(`\nGESAMT ${JSON.stringify(totals)}`);
