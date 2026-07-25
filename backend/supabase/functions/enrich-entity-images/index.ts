// Vollautomatische Bilderversorgung für Venues/Personen/Ensembles/
// Festivals/Events — auf expliziten Nutzerwunsch ("ich möchte keine Bilder
// manuell eintragen müssen") komplett überarbeitet gegenüber der ersten
// Fassung (die nur Wikimedia für Entitäten und og:image für Events kannte,
// beides ungeprüft übernommen bzw. ungeprüft in die Review-Queue gestellt).
//
// Prioritätenkette pro Lauf, EIN Aufruf deckt beides ab:
//
//   0) HEALTH-CHECK: bestehende photo_url/image_urls auf Erreichbarkeit
//      prüfen (echter HTTP-Request, siehe _shared/imageValidation.ts).
//      Kaputt/leer -> Feld zurücksetzen, damit die Zeile in DIESEM selben
//      Lauf sofort wieder für Priorität 1/2/3 unten in Frage kommt.
//
//   1) Events: eigene og:image/twitter:image-Seite (website_url, dann
//      ticket_url) — war schon vorher so, jetzt zusätzlich mit
//      Erreichbarkeits- und Duplikat-Prüfung vor dem Schreiben.
//   2) Venues/Personen/Ensembles/Festivals: og:image der EIGENEN
//      offiziellen website_url — NEU. Direkt in photo_url übernommen (kein
//      Review nötig: es ist die eigene, von der Entität selbst gepflegte
//      Seite, kein Fremdbild), plus ein images-Audit-Eintrag für
//      Quellen-/Attributionsnachweis (license_status='confirmed_licensed').
//   3) Fallback: Wikimedia Commons (wie vorher) — LANDET WEITERHIN in der
//      manuellen Review-Queue (needs_review=true), auf ausdrücklichen
//      Nutzerwunsch NICHT automatisch freigegeben (Lizenz-/
//      Namensnennungsrisiko bei einem Bild ohne direkten Bezug zur
//      Entität selbst) — jetzt zusätzlich mit Erreichbarkeitsprüfung, damit
//      keine kaputte URL überhaupt erst in die Review-Queue kommt.
//
// Ein Datensatz gilt erst dann als "ohne verlässliches Bild trotz
// Recherche", wenn WEDER photo_url/image_urls gesetzt ist NOCH ein
// nicht-abgelehnter images-Kandidat existiert — siehe admin/src/app/
// (dashboard)/media/gaps/page.tsx für den entsprechenden Bericht.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { searchCommonsImage } from "../_shared/wikimediaCommons.ts";
import { extractOgImage } from "../_shared/ogImage.ts";
import { checkImageUrl } from "../_shared/imageValidation.ts";
import { logSystemAction } from "../_shared/systemLog.ts";

const DEFAULT_LIMIT = 8;
const HEALTH_CHECK_LIMIT = 15;

interface EntityKind {
  table: string;
  originType: "venue" | "person" | "ensemble" | "festival";
  nameColumn: string;
  /** Zusätzlicher Suchkontext für die Wikimedia-Fallback-Suche (Priorität
   * 3), um Namensgleichheiten mit anderen Städten/Personen zu vermeiden. */
  queryContext?: string;
}

const ENTITY_KINDS: EntityKind[] = [
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

  const healthCheck: Record<string, { checked: number; brokenCleared: number }> = {};
  for (const kind of ENTITY_KINDS) {
    healthCheck[kind.table] = await healthCheckEntityKind(supabase, kind);
  }
  const eventHealthCheck = await healthCheckEventImages(supabase);

  const perKind: Record<string, { found: number; autoApplied: number; queuedForReview: number; errors: string[] }> = {};
  for (const kind of ENTITY_KINDS) {
    perKind[kind.table] = await enrichEntityKind(supabase, kind, limit);
  }
  const eventResult = await enrichEventCovers(supabase, limit);

  const totalAutoApplied = Object.values(perKind).reduce((sum, r) => sum + r.autoApplied, 0);
  const totalQueued = Object.values(perKind).reduce((sum, r) => sum + r.queuedForReview, 0);
  if (totalAutoApplied > 0 || totalQueued > 0 || eventResult.updated > 0) {
    await logSystemAction(supabase, "images", null, "auto_enrichment_batch", {
      healthCheck,
      eventHealthCheck,
      perKind,
      events: eventResult,
    });
  }

  return jsonResponse({ healthCheck, eventHealthCheck, ...perKind, events: eventResult });
});

/** Prüft bis zu HEALTH_CHECK_LIMIT Zeilen mit gesetztem photo_url auf
 * Erreichbarkeit, älteste Prüfung zuerst (photo_checked_at asc nulls
 * first) — sorgt für einen fairen Umlauf über alle Zeilen statt immer
 * dieselbe Teilmenge zu treffen. Kaputte URLs werden zurückgesetzt, damit
 * enrichEntityKind() sie im selben Lauf direkt wieder aufgreift. */
async function healthCheckEntityKind(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
): Promise<{ checked: number; brokenCleared: number }> {
  const { data: rows, error } = await supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}, photo_url`)
    .not("photo_url", "is", null)
    .order("photo_checked_at", { ascending: true, nullsFirst: true })
    .limit(HEALTH_CHECK_LIMIT);

  if (error || !rows) return { checked: 0, brokenCleared: 0 };

  let brokenCleared = 0;
  for (const row of rows as Array<Record<string, unknown>>) {
    const { reachable } = await checkImageUrl(row.photo_url as string);
    const now = new Date().toISOString();
    if (reachable) {
      await supabase.from(kind.table).update({ photo_checked_at: now }).eq("id", row.id);
      continue;
    }
    brokenCleared++;
    await supabase.from(kind.table).update({ photo_url: null, photo_checked_at: now }).eq("id", row.id);
    await logSystemAction(supabase, kind.originType, row.id as string, "broken_photo_cleared", {
      name: row[kind.nameColumn],
      brokenUrl: row.photo_url,
    });
  }
  return { checked: rows.length, brokenCleared };
}

/** Analog zu healthCheckEntityKind(), aber für events.image_urls (Array,
 * geprüft wird die erste URL — bei mehreren Einträgen ist die erste immer
 * die zuletzt gesetzte/primäre, siehe enrichEventCovers()/applyToOrigin()
 * in admin/src/app/(dashboard)/media/actions.ts, die beide vorn anhängen
 * bzw. als einzige URL schreiben). */
async function healthCheckEventImages(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<{ checked: number; brokenCleared: number }> {
  const { data: rows, error } = await supabase
    .from("events")
    .select("id, title, image_urls")
    .not("image_urls", "is", null)
    .order("images_checked_at", { ascending: true, nullsFirst: true })
    .limit(HEALTH_CHECK_LIMIT);

  if (error || !rows) return { checked: 0, brokenCleared: 0 };

  let brokenCleared = 0;
  let checked = 0;
  for (const row of rows as Array<{ id: string; title: string; image_urls: string[] | null }>) {
    if (!row.image_urls || row.image_urls.length === 0) continue;
    checked++;
    const { reachable } = await checkImageUrl(row.image_urls[0]);
    const now = new Date().toISOString();
    if (reachable) {
      await supabase.from("events").update({ images_checked_at: now }).eq("id", row.id);
      continue;
    }
    brokenCleared++;
    await supabase.from("events").update({ image_urls: [], images_checked_at: now }).eq("id", row.id);
    await logSystemAction(supabase, "event", row.id, "broken_image_cleared", {
      title: row.title,
      brokenUrl: row.image_urls[0],
    });
  }
  return { checked, brokenCleared };
}

/** Prüft, ob dieselbe Bild-URL bereits einer ANDEREN Entität/einem anderen
 * Event zugeordnet ist — auf Nutzerwunsch ("keine... Duplikate verwenden"),
 * z. B. damit nicht versehentlich ein Presse-Logo o.ä., das og:image auf
 * mehreren verschiedenen Unterseiten derselben Domain liefert, für zwei
 * unterschiedliche Ensembles landet. */
async function isUrlUsedElsewhere(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  url: string,
  excludeTable: string,
  excludeId: string,
): Promise<boolean> {
  for (const kind of ENTITY_KINDS) {
    let query = supabase.from(kind.table).select("id", { count: "exact", head: true }).eq("photo_url", url);
    if (kind.table === excludeTable) query = query.neq("id", excludeId);
    const { count } = await query;
    if (count && count > 0) return true;
  }
  if (excludeTable !== "events") {
    const { count } = await supabase
      .from("events")
      .select("id", { count: "exact", head: true })
      .contains("image_urls", [url]);
    if (count && count > 0) return true;
  }
  return false;
}

async function enrichEntityKind(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
  limit: number,
): Promise<{ found: number; autoApplied: number; queuedForReview: number; errors: string[] }> {
  const { data: rows, error } = await supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}, website_url`)
    .is("photo_url", null)
    .limit(limit);

  if (error) {
    return { found: 0, autoApplied: 0, queuedForReview: 0, errors: [`${kind.table}: Laden fehlgeschlagen — ${error.message}`] };
  }

  const list = (rows ?? []) as Array<Record<string, unknown>>;
  let autoApplied = 0;
  let queuedForReview = 0;
  const errors: string[] = [];

  for (const row of list) {
    const id = row.id as string;
    const name = row[kind.nameColumn] as string;
    const websiteUrl = row.website_url as string | null;
    if (!name?.trim()) continue;

    try {
      // Priorität 2: eigene offizielle Website. Direkt übernommen, kein
      // Review — es ist die Entität selbst, die dieses Bild von sich
      // öffentlich zeigt, kein Fremdbild eines Dritten.
      if (websiteUrl) {
        const ownImage = await extractOgImage(websiteUrl);
        if (ownImage) {
          const { reachable } = await checkImageUrl(ownImage);
          if (reachable && !(await isUrlUsedElsewhere(supabase, ownImage, kind.table, id))) {
            const now = new Date().toISOString();
            const { error: updateError } = await supabase
              .from(kind.table)
              .update({ photo_url: ownImage, photo_checked_at: now })
              .eq("id", id);
            if (updateError) {
              errors.push(`${kind.table} "${name}": Update fehlgeschlagen — ${updateError.message}`);
              continue;
            }
            await supabase.from("images").insert({
              source_url: ownImage,
              origin_type: kind.originType,
              origin_id: id,
              license_status: "confirmed_licensed",
              needs_review: false,
              license_notes:
                `Automatisch übernommen von der eigenen offiziellen Website der Entität (${websiteUrl}) — ` +
                `kein Fremdbild, daher ohne manuelle Lizenzprüfung freigegeben.`,
            });
            autoApplied++;
            continue;
          }
        }
      }

      // Priorität 3: Wikimedia-Fallback — weiterhin review-pflichtig.
      // Schon eine images-Zeile (egal welchen Status außer 'rejected') für
      // diese Entität? Dann läuft schon eine Prüfung/Entscheidung.
      const { data: existing } = await supabase
        .from("images")
        .select("id")
        .eq("origin_type", kind.originType)
        .eq("origin_id", id)
        .neq("license_status", "rejected")
        .maybeSingle();
      if (existing) continue;

      const query = kind.queryContext ? `${name} ${kind.queryContext}` : name;
      const candidate = await searchCommonsImage(query);
      if (!candidate) continue;

      const { reachable } = await checkImageUrl(candidate.url);
      if (!reachable) continue;
      if (await isUrlUsedElsewhere(supabase, candidate.url, kind.table, id)) continue;

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
      queuedForReview++;
    } catch (err) {
      errors.push(`${kind.table} "${name}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return { found: list.length, autoApplied, queuedForReview, errors: errors.slice(0, 10) };
}

const EVENT_BATCH_SIZE = 15;
const EVENT_CONCURRENCY = 4;

/** Titelbild für bevorstehende Events ohne eigenes Bild — NUR das Bild der
 * Event-Quellseite selbst (og:image/twitter:image über website_url,
 * ersatzweise ticket_url), nie ein Venue-Foto (auf expliziten
 * Nutzerwunsch). Jetzt zusätzlich mit Erreichbarkeits- und
 * Duplikat-Prüfung vor dem Schreiben. Findet sich keins, bleibt
 * image_urls leer und die App zeigt den genre-spezifischen
 * GenreArtwork-Platzhalter. */
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
          const candidate = await extractOgImage(pageUrl);
          if (!candidate) continue;
          const { reachable } = await checkImageUrl(candidate);
          if (!reachable) continue;
          if (await isUrlUsedElsewhere(supabase, candidate, "events", event.id)) continue;
          coverImage = candidate;
          break;
        }
        if (!coverImage) continue;

        const now = new Date().toISOString();
        const { error: updateError } = await supabase
          .from("events")
          .update({ image_urls: [coverImage], images_checked_at: now, updated_at: now })
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
