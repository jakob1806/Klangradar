// Automatische Zusammenführung von Personen-Duplikaten durch Namensvarianten
// (Nutzerwunsch: "J.S. Bach" und "Johann Sebastian Bach" sollen automatisch
// zur ausgeschriebenen Form zusammengeführt werden). Auf Nutzerentscheidung
// vollautomatisch bei hoher KI-Konfidenz, analog zur bestehenden
// automatischen Kandidaten-Anlage (enrich-event-references' autoCreateEntity)
// — alles Unklare bleibt unangetastet für die manuelle Prüfung.
//
// Zweistufig:
//  1. Günstiger Heuristik-Filter (kein LLM-Aufruf): gruppiert Personen nach
//     normalisiertem Nachnamen (letztes Wort, Umlaute gefaltet), vergleicht
//     dann innerhalb einer Gruppe, ob ein Name eine reine Initialen-
//     Abkürzung des anderen ist (z.B. "J.S." vs "Johann Sebastian" — jede
//     Initiale im kürzeren Namen muss der Reihe nach zum ersten Buchstaben
//     eines Vornamens im längeren Namen passen).
//  2. Nur wer die Heuristik besteht, geht zur KI-Bestätigung (konservativ:
//     confident=false bei jeder Unsicherheit, z.B. wenn Geburts-/Sterbedaten
//     wenn vorhanden nicht zusammenpassen).
// Merge-Reihenfolge folgt demselben Muster wie die bisherigen manuellen
// Zusammenführungen dieser Sitzung: FK-Referenzen (works.composer_id,
// event_participants.person_id, user_favorite_persons.person_id,
// sources.person_id, entity_candidates.created_person_id,
// field_provenance.entity_id) auf den kanonischen Eintrag umbiegen, Alias
// für die kürzere Form anlegen, Duplikat erst danach löschen. Audit-Log via
// _shared/systemLog.ts, damit ein automatischer Merge nachvollziehbar bleibt.
//
// Aufruf: POST { limit?: number } — prüft bis zu `limit` (Default 10)
// Heuristik-Kandidatenpaare per KI pro Lauf.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { logSystemAction } from "../_shared/systemLog.ts";

const DEFAULT_LIMIT = 10;

const UMLAUT_MAP: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss" };

function foldUmlauts(s: string): string {
  return s
    .toLowerCase()
    .split("")
    .map((c) => UMLAUT_MAP[c] ?? c)
    .join("");
}

/** Alle "bedeutsamen" Tokens (≥3 Zeichen, damit Initialen/Partikel wie "von"
 * nicht selbst als Anker taugen) eines Namens, umlautgefaltet — dient als
 * Gruppierungsschlüssel. Bewusst NICHT mehr nur das letzte Token: bei
 * mehrteiligen Nachnamen ("Felix Mendelssohn Bartholdy") ist "Bartholdy"
 * das letzte Token, aber die Kurzform "F. Mendelssohn" endet auf
 * "Mendelssohn" — beide landeten dadurch nie in derselben Gruppe und
 * wurden nie verglichen (live beobachteter Fall: "F. Mendelssohn" blieb
 * neben "Felix Mendelssohn Bartholdy" als eigener Eintrag stehen). */
// Adels-/Herkunfts-Partikel sind oft ≥3 Zeichen lang, taugen aber nicht als
// Anker — sonst matcht "Friedrich von Thun" fälschlich gegen "Friedrich von
// Flotow" (live beobachtet), weil beide "von" + denselben Vornamen teilen.
const NAME_PARTICLES = new Set([
  "von", "van", "der", "den", "des", "de", "di", "da", "do", "dos",
  "le", "la", "les", "el", "al", "bin", "ibn", "y", "und",
]);

function significantTokens(fullName: string): string[] {
  return fullName
    .trim()
    .split(/\s+/)
    .map((t) => foldUmlauts(t.replace(/\./g, "")))
    .filter((t) => t.length >= 3 && !NAME_PARTICLES.has(t));
}

/** Prüft, ob die Vornamens-Tokens vor dem gemeinsamen Anker-Token
 * zueinander passen — entweder als Initialen-Abkürzung ("J.S." vs "Johann
 * Sebastian") oder als exakte Übereinstimmung der ausgeschriebenen Vornamen. */
function givenNamesMatch(shortGiven: string[], longGiven: string[]): boolean {
  if (shortGiven.length === 0 || shortGiven.length > longGiven.length) return false;

  const fragments = shortGiven.flatMap((t) => t.split(".").filter(Boolean));
  if (fragments.length === 0) return false;

  if (fragments.every((f) => f.length === 1)) {
    const shortInitials = fragments.map((f) => foldUmlauts(f));
    if (shortInitials.length > longGiven.length) return false;
    return shortInitials.every((initial, i) => foldUmlauts(longGiven[i]).charAt(0) === initial);
  }

  // Kein reiner Initialen-Fall — nur als Treffer werten, wenn die
  // ausgeschriebenen Vornamen selbst übereinstimmen (z.B. "Felix
  // Mendelssohn" vs "Felix Mendelssohn Bartholdy", wo der Nachnamens-Zusatz
  // in der Kurzform schlicht fehlt statt abgekürzt zu sein).
  return (
    shortGiven.length === fragments.length &&
    fragments.every((f, i) => foldUmlauts(f) === foldUmlauts(longGiven[i]))
  );
}

/** true, wenn `shortName` eine abgekürzte/verkürzte Form von `longName`
 * ist — beide teilen ein bedeutsames Namens-Token (der Anker, meist der
 * Nachname oder ein Teil eines mehrteiligen Nachnamens), und die Tokens
 * VOR diesem Anker in `shortName` passen als Initialen oder exakte
 * Vornamen zu denen in `longName`. Ein evtl. NACH dem Anker folgender
 * Rest in `longName` (z.B. "Bartholdy") muss in `shortName` nicht
 * vorkommen — genau der Fall, den die alte nur-letztes-Token-Logik nicht
 * abdeckte. */
function isAbbreviationOf(shortName: string, longName: string, anchor: string): boolean {
  const shortTokens = shortName.trim().split(/\s+/);
  const longTokens = longName.trim().split(/\s+/);

  const shortAnchorIdx = shortTokens.findIndex((t) => foldUmlauts(t.replace(/\./g, "")) === anchor);
  const longAnchorIdx = longTokens.findIndex((t) => foldUmlauts(t.replace(/\./g, "")) === anchor);
  if (shortAnchorIdx <= 0 || longAnchorIdx <= 0) return false; // Anker muss existieren und Vornamen davor haben

  return givenNamesMatch(shortTokens.slice(0, shortAnchorIdx), longTokens.slice(0, longAnchorIdx));
}

const MERGE_CHECK_FUNCTION: AiFunctionDeclaration = {
  name: "confirm_same_person",
  description: "Prüft, ob zwei Namenseinträge dieselbe reale Person bezeichnen.",
  parameters: {
    type: "object",
    properties: {
      samePerson: {
        type: "boolean",
        description:
          "true NUR, wenn beide Einträge eindeutig dieselbe reale Person sind (z.B. Abkürzung/Namensvariante " +
          "desselben bekannten Komponisten/Musikers). false bei jeder Unsicherheit, unterschiedlichen Lebensdaten " +
          "oder wenn es sich um zwei verschiedene, nur namensähnliche Personen handeln könnte.",
      },
    },
    required: ["samePerson"],
  },
};

interface PersonRow {
  id: string;
  full_name: string;
  birth_date: string | null;
  death_date: string | null;
  biography_de: string | null;
  website_url: string | null;
}

const FK_REFS: Array<{ table: string; column: string }> = [
  { table: "works", column: "composer_id" },
  { table: "event_participants", column: "person_id" },
  { table: "user_favorite_persons", column: "person_id" },
  { table: "sources", column: "person_id" },
  { table: "entity_candidates", column: "created_person_id" },
];

Deno.serve(async (req) => {
  if (!hasAnyAiProviderConfigured()) {
    return jsonResponse({ error: "Kein AI-Provider-Secret gesetzt (siehe _shared/ai/router.ts)" }, 500);
  }

  let body: { limit?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0 ? Math.min(body.limit, 30) : DEFAULT_LIMIT;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: persons, error: fetchError } = await supabase
    .from("persons")
    .select("id, full_name, birth_date, death_date, biography_de, website_url")
    .returns<PersonRow[]>();

  if (fetchError) {
    return jsonResponse({ error: fetchError.message }, 500);
  }
  if (!persons || persons.length < 2) {
    return jsonResponse({ processed: 0, merged: 0, message: "Nicht genug Personen für einen Vergleich." });
  }

  // Gruppierung über JEDES bedeutsame Token statt nur des letzten — eine
  // Person kann so über mehrere Anker-Gruppen (z.B. "mendelssohn" UND
  // "bartholdy") mit anderen verglichen werden.
  const groups = new Map<string, PersonRow[]>();
  for (const p of persons) {
    for (const token of significantTokens(p.full_name)) {
      (groups.get(token) ?? groups.set(token, []).get(token)!).push(p);
    }
  }

  const seenPairs = new Set<string>();
  const candidatePairs: Array<{ shorter: PersonRow; longer: PersonRow }> = [];
  for (const [anchor, group] of groups.entries()) {
    if (group.length < 2) continue;
    for (let i = 0; i < group.length; i++) {
      for (let j = 0; j < group.length; j++) {
        if (i === j) continue;
        const a = group[i];
        const b = group[j];
        if (a.id === b.id) continue;
        if (isAbbreviationOf(a.full_name, b.full_name, anchor)) {
          const pairKey = [a.id, b.id].sort().join(":");
          if (seenPairs.has(pairKey)) continue;
          seenPairs.add(pairKey);
          candidatePairs.push({ shorter: a, longer: b });
        }
      }
    }
  }

  let checked = 0;
  let merged = 0;
  const errors: string[] = [];

  for (const { shorter, longer } of candidatePairs) {
    if (checked >= limit) break;
    checked++;
    try {
      const context = [
        `Eintrag 1: "${shorter.full_name}"` +
          (shorter.birth_date ? `, geboren ${shorter.birth_date}` : "") +
          (shorter.death_date ? `, gestorben ${shorter.death_date}` : ""),
        `Eintrag 2: "${longer.full_name}"` +
          (longer.birth_date ? `, geboren ${longer.birth_date}` : "") +
          (longer.death_date ? `, gestorben ${longer.death_date}` : ""),
      ].join("\n");

      const response = await callAiFunction(
        "Du prüfst, ob zwei Namenseinträge aus einer Klassik-Konzert-Datenbank dieselbe reale Person " +
          "bezeichnen (z.B. eine abgekürzte und eine ausgeschriebene Namensform desselben Komponisten/" +
          "Musikers). Sei konservativ: bei jeder Unsicherheit oder widersprüchlichen Lebensdaten " +
          "samePerson=false.",
        context,
        MERGE_CHECK_FUNCTION,
      );
      const args = response?.args;
      if (!args || args.samePerson !== true) {
        // Heuristik hat angeschlagen, aber die KI ist sich nicht sicher
        // genug für einen automatischen Merge (z.B. "F. Mendelssohn" könnte
        // Felix ODER Fanny Mendelssohn sein, beide real existierende
        // Komponist:innen) — landet zur manuellen Entscheidung in der
        // Review-Queue statt stillschweigend zu verschwinden.
        await supabase
          .from("person_duplicate_candidates")
          .insert({ person_a_id: shorter.id, person_b_id: longer.id })
          .select("id")
          .maybeSingle(); // best effort — Unique-Konflikt (schon vorgemerkt) ist kein Fehlerfall
        continue;
      }

      // Kanonisch ist immer die ausgeschriebene ("longer") Form — die
      // Heuristik stellt bereits sicher, dass "shorter" eine reine
      // Initialen-Abkürzung von "longer" ist, nie umgekehrt.
      for (const { table, column } of FK_REFS) {
        const { error: repointError } = await supabase.from(table).update({ [column]: longer.id }).eq(column, shorter.id);
        if (repointError) {
          throw new Error(`Repoint ${table}.${column} fehlgeschlagen: ${repointError.message}`);
        }
      }
      // Best-effort wie der Rest von field_provenance (siehe
      // _shared/provenance.ts) — ein UNIQUE-Konflikt (longer.id hat für
      // dasselbe Feld bereits einen Eintrag) darf den Merge nicht abbrechen,
      // Provenienz-Metadaten sind nicht kritisch für die Datenintegrität.
      // update() wirft bei einem DB-Fehler NICHT, sondern liefert ihn im
      // Ergebnisobjekt — daher explizit ignorieren statt try/catch.
      const { error: provenanceError } = await supabase
        .from("field_provenance")
        .update({ entity_id: longer.id })
        .eq("entity_type", "person")
        .eq("entity_id", shorter.id);
      if (provenanceError) {
        console.error(`field_provenance-Umzug für "${shorter.full_name}" fehlgeschlagen:`, provenanceError.message);
      }
      await supabase.from("entity_aliases").upsert(
        { entity_type: "person", entity_id: longer.id, alias: shorter.full_name },
        { onConflict: "entity_type,entity_id,alias" },
      );

      const { error: deleteError } = await supabase.from("persons").delete().eq("id", shorter.id);
      if (deleteError) {
        throw new Error(`Löschen von "${shorter.full_name}" fehlgeschlagen: ${deleteError.message}`);
      }

      await logSystemAction(supabase, "person", longer.id, "ai_auto_merged_duplicate", {
        merged_name: shorter.full_name,
        merged_person_id: shorter.id,
        canonical_name: longer.full_name,
      }, "system (AI-Entscheidung, resolve-person-duplicates)");

      merged++;
    } catch (err) {
      errors.push(`"${shorter.full_name}" → "${longer.full_name}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return jsonResponse({
    candidatePairsFound: candidatePairs.length,
    processed: checked,
    merged,
    errorCount: errors.length,
    errors: errors.slice(0, 10),
  });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
