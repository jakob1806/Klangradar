#!/usr/bin/env node

/** Sicherer CLI-Client für die bestehende Supabase Edge Function.
 * Zugangsdaten ausschließlich über Umgebungsvariablen; keine Secrets im Repo.
 */
const args = process.argv.slice(2);
const valueOf = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};
const has = (name) => args.includes(name);
if (has("--help")) {
  console.log(`import-entity-images [options]
  --type all|person|ensemble|venue|festival
  --limit N                 Batchgröße (Standard: 8)
  --only-missing            dokumentiert die Standardselektion
  --dry-run                 nur Inventar, garantiert ohne Schreibzugriffe
  --review-only             nur Queue-Zahlen ausgeben
  --ids ID1,ID2             gezielte Datensätze manuell abarbeiten
  --min-confidence 0..1     Mindestwert für automatische Übernahme`);
  process.exit(0);
}

const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!baseUrl || !key) {
  console.error("SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY (oder ANON_KEY) müssen gesetzt sein.");
  process.exit(2);
}
const type = valueOf("--type", "all");
if (!["all", "person", "ensemble", "venue", "festival"].includes(type)) {
  console.error(`Ungültiger --type: ${type}`);
  process.exit(2);
}
const limit = Number(valueOf("--limit", "8"));
if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
  console.error("--limit muss eine ganze Zahl zwischen 1 und 500 sein.");
  process.exit(2);
}
const minConfidence = Number(valueOf("--min-confidence", "0.85"));
if (!Number.isFinite(minConfidence) || minConfidence < 0 || minConfidence > 1) {
  console.error("--min-confidence muss zwischen 0 und 1 liegen.");
  process.exit(2);
}
const entityIds = valueOf("--ids", "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
if (entityIds.length > 500) {
  console.error("--ids akzeptiert höchstens 500 IDs.");
  process.exit(2);
}

const payload = {
  type,
  limit,
  onlyMissing: has("--only-missing"),
  dryRun: has("--dry-run"),
  reviewOnly: has("--review-only"),
  minConfidence,
  entityIds,
};

const response = await fetch(`${baseUrl.replace(/\/$/, "")}/functions/v1/enrich-entity-images`, {
  method: "POST",
  headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
  body: JSON.stringify(payload),
  signal: AbortSignal.timeout(120_000),
});
const text = await response.text();
let result;
try { result = JSON.parse(text); } catch { result = { raw: text }; }
console.log(JSON.stringify(result, null, 2));
if (!response.ok || result.error) process.exit(1);
