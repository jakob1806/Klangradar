#!/usr/bin/env node

/** Ruft die bestehende research-entity-bio Edge Function (Wikipedia +
 * KI-Fallback, siehe admin/src/app/(dashboard)/bio-research/actions.ts für
 * das interaktive Pendant) für eine Liste von Personen auf.
 *
 * Sicherheitsregel (mit dem Nutzer abgestimmt): NUR "wikipedia"-Quellen
 * (aus einem konkret zitierbaren Artikel zusammengefasst, mit Namens-
 * Abgleich durch die KI) werden hier automatisch gespeichert — exakt
 * derselbe Vertrauens-Maßstab wie beim Excel-Biografie-Import. "ai_knowledge"-
 * Treffer (kein Beleg) und "not_found" werden NICHT gespeichert, sondern nur
 * geloggt — die bleiben für die manuelle Prüfung über /bio-research offen.
 */
import { writeFileSync, readFileSync } from "node:fs";

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

const idsFile = valueOf("--ids-file", null);
if (!idsFile) {
  console.error("--ids-file <pfad.json> ist erforderlich (Format: {rows:[{id,full_name}]} oder [{id,full_name}]).");
  process.exit(2);
}
const outFile = valueOf("--out-file", "/tmp/bio-research-results.json");
const startAt = Number(valueOf("--start-at", 0));

const raw = JSON.parse(readFileSync(idsFile, "utf8"));
const persons = (Array.isArray(raw) ? raw : raw.rows).slice(startAt);

console.log(`${persons.length} Personen (ab Index ${startAt})`);

const results = { savedWikipedia: [], needsReviewAiKnowledge: [], notFound: [], errors: [] };

for (let i = 0; i < persons.length; i++) {
  const p = persons[i];
  let result;
  try {
    const res = await fetch(`${baseUrl.replace(/\/$/, "")}/functions/v1/research-entity-bio`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
      body: JSON.stringify({ entityType: "person", entityId: p.id }),
      signal: AbortSignal.timeout(30_000),
    });
    result = await res.json();
    if (!res.ok) result.error ??= `HTTP ${res.status}`;
  } catch (err) {
    result = { error: err instanceof Error ? err.message : String(err) };
  }

  if (result.error) {
    results.errors.push({ id: p.id, name: p.full_name, error: result.error });
    console.log(`${i + 1}/${persons.length} ${p.full_name}: FEHLER — ${result.error}`);
  } else if (!result.found) {
    results.notFound.push({ id: p.id, name: p.full_name });
    console.log(`${i + 1}/${persons.length} ${p.full_name}: nicht gefunden`);
  } else if (result.source === "wikipedia") {
    // Direkt speichern — zitierbare Quelle, KI hat Namens-Match bestätigt.
    const patchRes = await fetch(`${baseUrl.replace(/\/$/, "")}/rest/v1/persons?id=eq.${p.id}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        apikey: key,
        Authorization: `Bearer ${key}`,
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ biography_de: result.biography }),
    });
    if (!patchRes.ok) {
      results.errors.push({ id: p.id, name: p.full_name, error: `Speichern fehlgeschlagen (HTTP ${patchRes.status})` });
      console.log(`${i + 1}/${persons.length} ${p.full_name}: Speichern fehlgeschlagen`);
    } else {
      results.savedWikipedia.push({ id: p.id, name: p.full_name, sourceUrl: result.sourceUrl });
      console.log(`${i + 1}/${persons.length} ${p.full_name}: gespeichert (Wikipedia: ${result.sourceUrl})`);
    }
  } else {
    // ai_knowledge — kein Beleg, NICHT automatisch speichern.
    results.needsReviewAiKnowledge.push({ id: p.id, name: p.full_name, biography: result.biography });
    console.log(`${i + 1}/${persons.length} ${p.full_name}: ai_knowledge, zur Prüfung vorgemerkt (nicht gespeichert)`);
  }

  writeFileSync(outFile, JSON.stringify({ ...results, lastIndex: i + startAt }, null, 2));
}

console.log(`\nGESAMT: gespeichert(Wikipedia)=${results.savedWikipedia.length} zur-Pruefung(ai_knowledge)=${results.needsReviewAiKnowledge.length} nicht-gefunden=${results.notFound.length} fehler=${results.errors.length}`);
