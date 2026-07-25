// Automatische Bilder-Anreicherung für Venues/Personen/Ensembles/Festivals
// ohne eigenes Foto, plus Cover-Bilder für Events ohne image_urls — auf
// expliziten Nutzerwunsch ("Bilder automatisch hinzufügen"), analog zum
// bestehenden resolve-entity-candidates-Batch-Muster (fester Aufruf,
// begrenztes Limit pro Lauf, manuell auslösbar über einen Admin-Button).
//
// Venues/Personen/Ensembles/Festivals: Wikimedia-Commons-Suche (siehe
// _shared/wikimediaCommons.ts) nach einem Bild mit erkennbar freier Lizenz.
// Ein Treffer landet als NEUE Zeile in images mit needs_review=true,
// license_status='unknown' — NIE automatisch freigegeben (siehe
// 20260819000003_images_and_tags.sql), das hier ist reine Vorauswahl. Die
// eigentliche Übernahme ins photo_url-Feld passiert erst, wenn eine
// Redakteurin das Bild im Media-Review (/media) bestätigt (siehe
// admin/src/app/(dashboard)/media/actions.ts).
//
// Events: NUR das eigene Bild der Konzert-Quellseite (og:image/
// twitter:image über website_url, ersatzweise ticket_url — siehe
// _shared/ogImage.ts). Bewusst KEIN Rückfall auf das Venue-Foto mehr (auf
// expliziten Nutzerwunsch: "nicht bloß ein generisches Foto der Venue" —
// ein geteiltes Gebäudefoto für zig verschiedene Konzerte am selben Ort
// suggeriert ein eigenes Bild, wo keins existiert). Findet sich kein
// og:image, bleibt image_urls leer und die App zeigt den genre-spezifischen
// GenreArtwork-Platzhalter (core/widgets/genre_artwork.dart) — der ist
// bereits das "klar unterscheidbare, hochwertige Ersatzmotiv im jeweiligen
// Event-Stil", um das der Nutzer gebeten hat, kein separater Baustein
// nötig. og:image wird ohne Review-Schritt direkt in events.image_urls
// geschrieben (direkter Verweis auf die eigene Werbeseite des Konzerts,
// anders als die Wikimedia-Funde unten keine neue, ungeprüfte Quelle).
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 8)
// Entitäten pro Kategorie (venues/persons/ensembles/festivals) und bis zu
// `limit` Events (jedes braucht einen echten externen Fetch für das
// og:image, ebenfalls begrenzt statt "beliebig viele").

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { searchCommonsImage } from "../_shared/wikimediaCommons.ts";
import { extractOgImage } from "../_shared/ogImage.ts";
import { logSystemAction } from "../_shared/systemLog.ts";

const DEFAULT_LIMIT = 8;

interface EntityKind {
  table: string;
  originType: "venue" | "person" | "ensemble" | "festival";
  nameColumn: string;
  /** Zusätzlicher Suchkontext, um Namensgleichheiten mit anderen Städten/
   * Personen zu vermeiden (z.B. "Isarphilharmonie" -> "Isarphilharmonie
   * München", ein reiner Personenname bleibt dagegen ambiger genug, dass
   * ein Zusatz eher schadet als hilft). */
  queryContext?: string;
}

const ENTITY_KINDS: EntityKind[] = [
  // Nur "München" als Zusatz, kein Venue-/Genre-Wort — Commons' Volltextsuche
  // matcht gegen Dateititel/Kategorien, ein zusätzliches Wort wie
  // "Konzertsaal" schlägt bei Venues, die selbst keine Konzertsäle sind
  // (Kirchen, Museen), fehl und lieferte in der Praxis 0 statt einige
  // Treffer (z.B. "Alte Pinakothek München Konzertsaal" -> kein einziger
  // Treffer, "Alte Pinakothek" allein -> mehrere CC-BY-Treffer).
  { table: "venues", originType: "venue", nameColumn: "name", queryContext: "München" },
  { table: "persons", originType: "person", nameColumn: "full_name" },
  { table: "ensembles", originType: "ensemble", nameColumn: "name" },
  { table: "festivals", originType: "festival", nameColumn: "name", queryContext: "München" },
];

Deno.serve(async (req) => {
  let body: { limit?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0 ? body.limit : DEFAULT_LIMIT;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const perKind: Record<string, { found: number; queued: number; errors: string[] }> = {};
  for (const kind of ENTITY_KINDS) {
    perKind[kind.table] = await enrichEntityKind(supabase, kind, limit);
  }
  const eventResult = await enrichEventCovers(supabase, limit);

  const totalQueued = Object.values(perKind).reduce((sum, r) => sum + r.queued, 0);
  if (totalQueued > 0 || eventResult.updated > 0) {
    await logSystemAction(supabase, "images", null, "auto_enrichment_batch", {
      perKind,
      events: eventResult,
    });
  }

  return jsonResponse({ ...perKind, events: eventResult });
});

async function enrichEntityKind(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
  limit: number,
): Promise<{ found: number; queued: number; errors: string[] }> {
  const { data: rows, error } = await supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}`)
    .is("photo_url", null)
    .limit(limit);

  if (error) {
    return { found: 0, queued: 0, errors: [`${kind.table}: Laden fehlgeschlagen — ${error.message}`] };
  }

  const list = (rows ?? []) as Array<Record<string, unknown>>;
  let queued = 0;
  const errors: string[] = [];

  for (const row of list) {
    const id = row.id as string;
    const name = row[kind.nameColumn] as string;
    if (!name?.trim()) continue;

    try {
      // Schon eine images-Zeile (egal welchen Status) für diese Entität? —
      // dann läuft schon eine Prüfung/Entscheidung, keine zweite Suche.
      const { data: existing } = await supabase
        .from("images")
        .select("id")
        .eq("origin_type", kind.originType)
        .eq("origin_id", id)
        .maybeSingle();
      if (existing) continue;

      const query = kind.queryContext ? `${name} ${kind.queryContext}` : name;
      const candidate = await searchCommonsImage(query);
      if (!candidate) continue;

      const { error: insertError } = await supabase.from("images").insert({
        source_url: candidate.url,
        origin_type: kind.originType,
        origin_id: id,
        photographer: candidate.artist,
        license_notes: `Wikimedia Commons: ${candidate.license}` +
          (candidate.attributionRequired ? " (Namensnennung erforderlich)" : "") +
          ` — ${candidate.pageUrl}`,
      });
      if (insertError) {
        errors.push(`${kind.table} "${name}": Insert fehlgeschlagen — ${insertError.message}`);
        continue;
      }
      queued++;
    } catch (err) {
      errors.push(`${kind.table} "${name}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return { found: list.length, queued, errors: errors.slice(0, 10) };
}

const EVENT_BATCH_SIZE = 15;
const EVENT_CONCURRENCY = 4;

/** Titelbild für bevorstehende Events ohne eigenes Bild — dieselben
 * Kriterien (aktiv, bevorstehend) wie die Datenqualitäts-Review-Seite im
 * Admin-Dashboard. NUR das Bild der Event-Quellseite selbst (og:image/
 * twitter:image über website_url bzw. ersatzweise ticket_url, siehe
 * _shared/ogImage.ts) — kein Venue-Foto-Rückfall mehr (siehe
 * Datei-Kommentar oben). Findet sich keins, bleibt image_urls leer.
 * Begrenzte Stapelgröße + Nebenläufigkeit wie bei resolve-entity-
 * candidates: pro Event ist ein echter externer Fetch nötig, unbegrenzt
 * hätte das 150s-Idle-Timeout der Edge Function gerissen. */
async function enrichEventCovers(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  limit = EVENT_BATCH_SIZE,
): Promise<{ found: number; updated: number; errors: string[] }> {
  const { data: events, error } = await supabase
    .from("events")
    .select("id, image_urls, website_url, ticket_url")
    .in("status", ["scheduled", "sold_out", "postponed"])
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true });

  if (error) {
    return { found: 0, updated: 0, errors: [`events: Laden fehlgeschlagen — ${error.message}`] };
  }

  const missingImages = (events ?? []).filter(
    (e: { image_urls: string[] | null }) => !e.image_urls || e.image_urls.length === 0,
  );
  const batch = missingImages.slice(0, limit);

  let updated = 0;
  const errors: string[] = [];

  let nextIndex = 0;
  async function worker() {
    while (nextIndex < batch.length) {
      const event = batch[nextIndex++];
      try {
        let coverImage: string | null = null;
        for (const pageUrl of [event.website_url, event.ticket_url]) {
          if (!pageUrl) continue;
          coverImage = await extractOgImage(pageUrl);
          if (coverImage) break;
        }
        if (!coverImage) continue;

        const { error: updateError } = await supabase
          .from("events")
          .update({ image_urls: [coverImage], updated_at: new Date().toISOString() })
          .eq("id", event.id);
        if (updateError) {
          errors.push(`event ${event.id}: ${updateError.message}`);
          continue;
        }
        updated++;
      } catch (err) {
        errors.push(`event ${event.id}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
  }
  const workerCount = Math.min(EVENT_CONCURRENCY, batch.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));

  return { found: missingImages.length, updated, errors: errors.slice(0, 10) };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
