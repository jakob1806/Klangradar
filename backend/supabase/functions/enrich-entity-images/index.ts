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
//   2b) NUR Personen/Ensembles: Bild von der Seite einer KONKRETEN
//      bevorstehenden Veranstaltung, bei der diese Person/dieses Ensemble
//      laut event_participants mitwirkt (siehe _shared/imageNearName.ts) —
//      auf Nutzerfeedback nachgerüstet, nachdem sich die blinde
//      Wikimedia-Namenssuche für Personen als zu ungenau herausgestellt hat
//      (z. B. Namensgleichheiten wie "Lazarova" trafen ein komplett
//      anderes Wikimedia-Motiv). Landet in der Review-Queue, NICHT
//      automatisch freigegeben — anders als die eigene Website ist das die
//      Seite eines Dritten (Veranstalter/Ticketanbieter) ohne bekannte
//      Lizenz.
//   3) Fallback:
//      - Personen: Wikipedia-Zusammenfassungs-API (_shared/
//        wikipediaPortrait.ts) statt blinder Commons-Volltextsuche — auf
//        Nutzerfeedback NACHGERÜSTET, nachdem sich zeigte, dass sogar
//        Bach/Mozart/Beethoven/Brahms/Mahler mangels Bild fehlten. Ein
//        Wikipedia-Artikeltitel ist (fast) exakt, nicht fuzzy wie eine
//        Commons-Volltextsuche — Mehrdeutigkeitsseiten werden explizit
//        verworfen. Weiterhin review-pflichtig (Drittquelle, Lizenz nicht
//        automatisch geprüft) — siehe mit dem Nutzer abgestimmte Regel:
//        nur die EIGENE offizielle Quelle einer Entität geht automatisch
//        live, jeder Fremdbild-Fund landet in der Review-Queue.
//      - Venues/Ensembles/Festivals: weiterhin Wikimedia Commons
//        (Gebäude-/Ensemble-Namen kollidieren deutlich seltener als
//        Personennamen), jetzt zusätzlich mit Erreichbarkeitsprüfung.
//
// Jeder Entscheidungspunkt schreibt eine kurze Begründung nach
// last_image_search_note (20260906000001_image_search_reason_tracking.sql)
// — das Bildlücken-Dashboard (admin/src/app/(dashboard)/media/gaps) zeigt
// diese Begründung an, statt sie nachträglich zu erraten.
//
// Events ohne website_url UND ohne ticket_url: eine Tavily-Websuche
// (_shared/tavily.ts) versucht, eine passende Seite zu finden — auf
// Nutzerwunsch ("Fehlende Website-/Ticket-URLs müssen automatisch
// nachrecherchiert werden") — über die kostenlose DuckDuckGo-HTML-Suche
// (_shared/duckDuckGoSearch.ts), nicht Tavily (Gratiskontingent
// ausgeschöpft, Upgrade auf Nutzerwunsch abgelehnt). Bounded auf
// EVENT_URL_DISCOVERY_LIMIT pro Lauf.
//
// Ein Datensatz gilt erst dann als "ohne verlässliches Bild trotz
// Recherche", wenn WEDER photo_url/image_urls gesetzt ist NOCH ein
// nicht-abgelehnter images-Kandidat existiert — siehe admin/src/app/
// (dashboard)/media/gaps/page.tsx für den entsprechenden Bericht.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { searchCommonsImage } from "../_shared/wikimediaCommons.ts";
import { fetchWikipediaPortrait } from "../_shared/wikipediaPortrait.ts";
import { detectEventCoverImage } from "../_shared/coverImageDetection.ts";
import { extractImageNearName } from "../_shared/imageNearName.ts";
import { checkImageUrl, isLikelyGenericImage } from "../_shared/imageValidation.ts";
import { isAllowedByRobots } from "../_shared/robots.ts";
import { searchDuckDuckGo } from "../_shared/duckDuckGoSearch.ts";
import { searchViaGeminiGrounding } from "../_shared/geminiGroundedSearch.ts";
import { logSystemAction } from "../_shared/systemLog.ts";

const DEFAULT_LIMIT = 8;
const HEALTH_CHECK_LIMIT = 15;
const EVENT_URL_DISCOVERY_LIMIT = 5;

interface EntityKind {
  table: string;
  originType: "venue" | "person" | "ensemble" | "festival";
  nameColumn: string;
  /** Zusätzlicher Suchkontext für die Wikimedia-Fallback-Suche (Venues/
   * Ensembles/Festivals), um Namensgleichheiten mit anderen Städten zu
   * vermeiden. */
  queryContext?: string;
  /** Spalte in event_participants, die auf diese Entität verweist — nur
   * für Personen/Ensembles gesetzt (Priorität 2b, siehe Datei-Kommentar). */
  participantColumn?: "person_id" | "ensemble_id";
  /** Personen nutzen Wikipedia (präzise) statt Wikimedia Commons (fuzzy)
   * als letzten Rückfall — siehe Datei-Kommentar. */
  useWikipediaFallback?: boolean;
}

const ENTITY_KINDS: EntityKind[] = [
  { table: "venues", originType: "venue", nameColumn: "name", queryContext: "München" },
  {
    table: "persons",
    originType: "person",
    nameColumn: "full_name",
    participantColumn: "person_id",
    useWikipediaFallback: true,
  },
  { table: "ensembles", originType: "ensemble", nameColumn: "name", participantColumn: "ensemble_id" },
  { table: "festivals", originType: "festival", nameColumn: "name", queryContext: "München" },
];

/** Nächste bevorstehende Veranstaltung, bei der diese Person/dieses
 * Ensemble laut event_participants mitwirkt — für Priorität 2b. Liefert
 * deren website_url/ticket_url (in dieser Reihenfolge versucht), oder
 * null wenn keine bevorstehende Veranstaltung mit brauchbarer URL
 * existiert. */
async function findUpcomingEventPageUrl(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  participantColumn: "person_id" | "ensemble_id",
  entityId: string,
): Promise<string | null> {
  const { data } = await supabase
    .from("event_participants")
    .select("events!inner(website_url, ticket_url, start_datetime, status)")
    .eq(participantColumn, entityId)
    .in("events.status", ["scheduled", "sold_out", "postponed"])
    .gte("events.start_datetime", new Date().toISOString())
    .limit(20);

  const rows = (data ?? []) as Array<
    { events: { website_url: string | null; ticket_url: string | null; start_datetime: string } }
  >;
  if (rows.length === 0) return null;
  rows.sort((a, b) => a.events.start_datetime.localeCompare(b.events.start_datetime));
  for (const row of rows) {
    const url = row.events.website_url ?? row.events.ticket_url;
    if (url) return url;
  }
  return null;
}

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

  const eventUrlDiscovery = await discoverMissingEventUrls(supabase);

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
      eventUrlDiscovery,
      perKind,
      events: eventResult,
    });
  }

  return jsonResponse({ healthCheck, eventHealthCheck, eventUrlDiscovery, ...perKind, events: eventResult });
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
  {
    // BUGFIX: diese Prüfung lief vorher NUR, wenn excludeTable !== "events"
    // — also genau dann NICHT, wenn wir für ein EVENT selbst prüfen, dem
    // Hauptfall, für den sie gedacht war. Dadurch konnten mehrere
    // verschiedene Events unbemerkt dasselbe generische Portal-Default-Bild
    // (z. B. "default--og-image--mm.jpg" auf muenchenmusik.de, live auf 38
    // verschiedenen Events gefunden) bekommen, statt dass ab dem zweiten
    // Treffer erkannt wurde: "diese URL ist schon vergeben". Jetzt läuft
    // die Prüfung immer, nur die eigene Zeile wird ausgeschlossen.
    let eventsQuery = supabase.from("events").select("id", { count: "exact", head: true }).contains(
      "image_urls",
      [url],
    );
    if (excludeTable === "events") eventsQuery = eventsQuery.neq("id", excludeId);
    const { count } = await eventsQuery;
    if (count && count > 0) return true;
  }
  // Auch gegen bereits (für eine ANDERE Entität) in die Review-Queue
  // gestellte, noch nicht abgelehnte Kandidaten prüfen — sonst kann
  // dieselbe generische Grafik (z. B. ein "Tickets kaufen"-Icon, das
  // fälschlich als Bild mehrerer verschiedener Mitwirkender erkannt
  // wurde) mehrfach parallel zur Prüfung vorgelegt werden, bevor eine
  // Redakteurin den ersten Fall überhaupt gesehen hat.
  const { count: queuedCount } = await supabase
    .from("images")
    .select("id", { count: "exact", head: true })
    .eq("source_url", url)
    .neq("license_status", "rejected")
    .neq("origin_id", excludeId);
  if (queuedCount && queuedCount > 0) return true;
  return false;
}

async function enrichEntityKind(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
  limit: number,
): Promise<{ found: number; autoApplied: number; queuedForReview: number; errors: string[] }> {
  // Ohne Sortierung liefert Postgres bei jedem Lauf dieselben ersten Zeilen
  // (physische Tabellenreihenfolge) — bei mehr Zeilen mit photo_url=null als
  // `limit` verhungerten dadurch alle Zeilen nach den ersten `limit`
  // permanent (live beobachtet: 266/302 persons, 46/91 ensembles, 19/46
  // venues mit last_image_search_note=null trotz Cron alle 15 Minuten seit
  // Wochen). nullsFirst sorgt dafür, dass noch nie versuchte Zeilen
  // (note ist null) immer vor bereits (erfolglos) versuchten Zeilen drankommen.
  const { data: rows, error } = await supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}, website_url`)
    .is("photo_url", null)
    .order("last_image_search_note", { ascending: true, nullsFirst: true })
    .limit(limit);

  if (error) {
    return { found: 0, autoApplied: 0, queuedForReview: 0, errors: [`${kind.table}: Laden fehlgeschlagen — ${error.message}`] };
  }

  const list = (rows ?? []) as Array<Record<string, unknown>>;
  let autoApplied = 0;
  let queuedForReview = 0;
  const errors: string[] = [];

  const setNote = (id: string, note: string | null) =>
    supabase.from(kind.table).update({ last_image_search_note: note }).eq("id", id);

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
        if (!(await isAllowedByRobots(websiteUrl))) {
          await setNote(id, "Eigene Website durch robots.txt gesperrt — Zugriff verweigert.");
        } else {
          // Volle Kaskade (schema.org -> og:image -> twitter:image -> Hero/
          // Banner -> Bild im Content-Container) statt nur og:image/
          // twitter:image — dieselbe Erkennung, die der Ingestion-Importer
          // seit PR #92 für neue Events nutzt (coverImageDetection.ts), war
          // hier bisher nicht verdrahtet, obwohl die meisten bildlosen
          // Entities durchaus eine website_url hinterlegt haben.
          const detected = await detectEventCoverImage(websiteUrl);
          const ownImage = detected?.url ?? null;
          if (!ownImage) {
            await setNote(id, "Eigene Website liefert kein nutzbares Bild (og:image/Hero/Content-Bereich geprüft).");
          } else {
            const { reachable } = await checkImageUrl(ownImage);
            if (!reachable) {
              await setNote(id, "Bild von der eigenen Website nicht erreichbar/kein gültiges Bildformat.");
            } else if (await isUrlUsedElsewhere(supabase, ownImage, kind.table, id)) {
              await setNote(id, "Bild von der eigenen Website ist bereits einer anderen Entität zugeordnet (Duplikat).");
            } else {
              const now = new Date().toISOString();
              const { error: updateError } = await supabase
                .from(kind.table)
                .update({ photo_url: ownImage, photo_checked_at: now, last_image_search_note: null })
                .eq("id", id);
              if (updateError) {
                errors.push(`${kind.table} "${name}": Update fehlgeschlagen — ${updateError.message}`);
                continue;
              }
              await supabase.from("images").insert({
                source_url: ownImage,
                origin_type: kind.originType,
                origin_id: id,
                photographer: detected?.credits ?? null,
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
      } else {
        await setNote(id, "Keine Website-URL hinterlegt.");
      }

      // Schon eine images-Zeile (egal welchen Status außer 'rejected') für
      // diese Entität? Dann läuft schon eine Prüfung/Entscheidung — weder
      // 2b noch 3 sollen einen zweiten Kandidaten obendrauf stellen.
      const { data: existing } = await supabase
        .from("images")
        .select("id")
        .eq("origin_type", kind.originType)
        .eq("origin_id", id)
        .neq("license_status", "rejected")
        .maybeSingle();
      if (existing) {
        await setNote(id, "Kandidat gefunden, wartet auf redaktionelle Lizenzprüfung (/media).");
        continue;
      }

      // Priorität 2b: Bild von der Seite einer konkreten bevorstehenden
      // Veranstaltung, bei der diese Person/dieses Ensemble mitwirkt —
      // präziser als eine blinde Namenssuche, aber Seite eines Dritten
      // ohne bekannte Lizenz, daher immer review-pflichtig.
      if (kind.participantColumn) {
        const eventPageUrl = await findUpcomingEventPageUrl(supabase, kind.participantColumn, id);
        if (eventPageUrl) {
          const nearImage = await extractImageNearName(eventPageUrl, name);
          if (nearImage && !isLikelyGenericImage(nearImage)) {
            const { reachable } = await checkImageUrl(nearImage);
            if (reachable && !(await isUrlUsedElsewhere(supabase, nearImage, kind.table, id))) {
              const { error: insertError } = await supabase.from("images").insert({
                source_url: nearImage,
                origin_type: kind.originType,
                origin_id: id,
                license_notes:
                  `Automatisch von der Programmseite einer bevorstehenden Veranstaltung mit ${name} ` +
                  `entnommen (${eventPageUrl}) — Seite eines Dritten, Lizenz vor Freigabe individuell prüfen.`,
              });
              if (insertError) {
                errors.push(`${kind.table} "${name}": Insert fehlgeschlagen — ${insertError.message}`);
              } else {
                queuedForReview++;
                await setNote(id, "Kandidat von einer Veranstaltungsseite gefunden, wartet auf Lizenzprüfung (/media).");
              }
              continue;
            }
          }
        }
      }

      // Priorität 3: Personen nutzen Wikipedia (präzise, exakter
      // Artikeltitel statt Volltextsuche), Venues/Ensembles/Festivals
      // weiterhin Wikimedia Commons (siehe Datei-Kommentar).
      if (kind.useWikipediaFallback) {
        const portrait = await fetchWikipediaPortrait(name);
        if (!portrait) {
          await setNote(id, "Kein eindeutiger Wikipedia-Artikel mit Porträtbild gefunden.");
          continue;
        }
        const { reachable } = await checkImageUrl(portrait.imageUrl);
        if (!reachable) {
          await setNote(id, "Wikipedia-Bild nicht erreichbar/kein gültiges Bildformat.");
          continue;
        }
        if (await isUrlUsedElsewhere(supabase, portrait.imageUrl, kind.table, id)) {
          await setNote(id, "Wikipedia-Bild ist bereits einer anderen Entität zugeordnet (Duplikat).");
          continue;
        }
        const { error: insertError } = await supabase.from("images").insert({
          source_url: portrait.imageUrl,
          origin_type: kind.originType,
          origin_id: id,
          license_notes: `Wikipedia: ${portrait.pageUrl}` +
            (portrait.description ? ` — "${portrait.description}"` : "") +
            " — Lizenz/Namensnennung vor Freigabe auf der Wikipedia-Bildseite prüfen.",
        });
        if (insertError) {
          errors.push(`${kind.table} "${name}": Insert fehlgeschlagen — ${insertError.message}`);
          continue;
        }
        queuedForReview++;
        await setNote(id, "Wikipedia-Kandidat gefunden, wartet auf Lizenzprüfung (/media).");
        continue;
      }

      const query = kind.queryContext ? `${name} ${kind.queryContext}` : name;
      const candidate = await searchCommonsImage(query);
      if (!candidate) {
        await setNote(id, "Keine passende Wikimedia-Commons-Datei gefunden.");
        continue;
      }

      const { reachable } = await checkImageUrl(candidate.url);
      if (!reachable) {
        await setNote(id, "Wikimedia-Bild nicht erreichbar/kein gültiges Bildformat.");
        continue;
      }
      if (await isUrlUsedElsewhere(supabase, candidate.url, kind.table, id)) {
        await setNote(id, "Wikimedia-Bild ist bereits einer anderen Entität zugeordnet (Duplikat).");
        continue;
      }

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
      await setNote(id, "Wikimedia-Kandidat gefunden, wartet auf Lizenzprüfung (/media).");
    } catch (err) {
      errors.push(`${kind.table} "${name}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return { found: list.length, autoApplied, queuedForReview, errors: errors.slice(0, 10) };
}

const EVENT_BATCH_SIZE = 15;
const EVENT_CONCURRENCY = 4;

/** Events ganz ohne website_url/ticket_url: Geminis Google-Search-
 * Grounding (_shared/geminiGroundedSearch.ts) versucht, eine passende
 * Seite zu finden (Titel + Venue-Name + "München Tickets") — auf
 * Nutzerwunsch ("Fehlende Website-/Ticket-URLs müssen automatisch
 * nachrecherchiert werden"). Gefundene URL wird als website_url
 * gespeichert (auch wenn sich daraus kein Bild extrahieren lässt — die URL
 * selbst ist der primäre Gewinn, ein Bild ist ein Bonus obendrauf).
 *
 * War zunächst mit Tavily gebaut (Gratiskontingent ausgeschöpft,
 * kostenpflichtiges Upgrade abgelehnt), dann mit Google Custom Search JSON
 * API (die dafür nötige "auf das gesamte Web durchsuchen"-Option wurde von
 * Google für Programmable Search Engine eingestellt) — beide verworfen.
 * Gemini-Grounding liefert über groundingChunks die tatsächlich
 * durchsuchten Quellen-URLs strukturiert mit, ohne HTML-Scraping — nutzt
 * aber bewusst ein EIGENES Secret (GEMINI_SEARCH_API_KEY), nicht den im
 * restlichen Projekt für generate-embeddings/enrich-event-references
 * genutzten GEMINI_API_KEY: mit dem gemeinsamen Key kollidierte diese
 * Suche mit deren Tageskontingent (429 RESOURCE_EXHAUSTED, live
 * beobachtet) — ein zweiter, kostenloser Key von einem separaten
 * Google-Konto hat sein eigenes Kontingent. DuckDuckGo bleibt als
 * letzter, in der Praxis meist wirkungsloser Fallback (Supabase-Server-IPs
 * werden dort geblockt, siehe duckDuckGoSearch.ts), falls kein
 * GEMINI_SEARCH_API_KEY gesetzt ist oder Grounding nichts liefert.
 *
 * Bounded auf EVENT_URL_DISCOVERY_LIMIT pro Lauf. */
async function discoverMissingEventUrls(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<{ attempted: number; found: number }> {
  // Eigenes, separates Secret statt des gemeinsam mit generate-embeddings/
  // enrich-event-references genutzten GEMINI_API_KEY — auf Nutzerwunsch,
  // damit die Event-URL-Suche nicht mit deren Tageskontingent konkurriert
  // (siehe Datei-Kommentar oben: genau das führte zu einem 429 mit dem
  // gemeinsamen Key).
  const geminiApiKey = Deno.env.get("GEMINI_SEARCH_API_KEY");

  const { data: events } = await supabase
    .from("events")
    .select("id, title, venues(name)")
    .is("website_url", null)
    .is("ticket_url", null)
    .in("status", ["scheduled", "sold_out", "postponed"])
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true })
    .limit(EVENT_URL_DISCOVERY_LIMIT);

  const rows = (events ?? []) as Array<{ id: string; title: string; venues: { name: string } | null }>;
  let found = 0;

  for (const event of rows) {
    const venueName = event.venues?.name ?? "";
    const query = `${event.title} ${venueName} München Tickets`;

    let topResultUrl: string | null = null;
    let searchFailed = false;

    if (geminiApiKey) {
      const groundedResults = await searchViaGeminiGrounding(geminiApiKey, query);
      if (groundedResults === null) searchFailed = true;
      else if (groundedResults.length > 0) topResultUrl = groundedResults[0].url;
    }

    if (!topResultUrl) {
      const ddgResults = await searchDuckDuckGo(query, 3);
      if (ddgResults === null) searchFailed = true;
      else if (ddgResults.length > 0) {
        topResultUrl = ddgResults[0].url;
        searchFailed = false;
      }
    }

    if (!topResultUrl) {
      const note = searchFailed
        ? "Websuche nach Website-/Ticket-URL fehlgeschlagen (Such-API nicht erreichbar)."
        : "Keine Website-/Ticket-URL per Websuche gefunden.";
      await supabase.from("events").update({ last_image_search_note: note }).eq("id", event.id);
      continue;
    }
    await supabase.from("events").update({ website_url: topResultUrl }).eq("id", event.id);
    found++;
  }

  return { attempted: rows.length, found };
}

/** Titelbild für bevorstehende Events ohne eigenes Bild — NUR das Bild der
 * Event-Quellseite selbst (og:image/twitter:image über website_url,
 * ersatzweise ticket_url), nie ein Venue-Foto (auf expliziten
 * Nutzerwunsch). Jetzt zusätzlich mit Erreichbarkeits- und
 * Duplikat-Prüfung vor dem Schreiben, plus einer Begründung nach
 * last_image_search_note, wenn nichts gefunden wird. Findet sich keins,
 * bleibt image_urls leer und die App zeigt den genre-spezifischen
 * GenreArtwork-Platzhalter. */
async function enrichEventCovers(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  limit = EVENT_BATCH_SIZE,
): Promise<{ found: number; updated: number; errors: string[] }> {
  // Gleicher Fix wie in enrichEntityKind: never-tried Events (note ist null)
  // zuerst, sonst blockieren die zeitlich nächsten Events dauerhaft den
  // gesamten Batch, sobald sie einmal erfolglos versucht wurden (live
  // beobachtet: 195/367 upcoming events ohne Bild). start_datetime bleibt
  // die Tie-Break-Sortierung innerhalb jeder der beiden Gruppen — je
  // näher das Event, desto eher lohnt sich ein (erneuter) Versuch.
  const { data: events, error } = await supabase
    .from("events")
    .select("id, image_urls, website_url, ticket_url")
    .in("status", ["scheduled", "sold_out", "postponed"])
    .gte("start_datetime", new Date().toISOString())
    .order("last_image_search_note", { ascending: true, nullsFirst: true })
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
        if (!event.website_url && !event.ticket_url) {
          await supabase
            .from("events")
            .update({ last_image_search_note: "Keine Website-/Ticket-URL hinterlegt." })
            .eq("id", event.id);
          continue;
        }

        let coverImage: string | null = null;
        const notes: string[] = [];
        for (const pageUrl of [event.website_url, event.ticket_url]) {
          if (!pageUrl) continue;
          if (!(await isAllowedByRobots(pageUrl))) {
            notes.push(`${pageUrl} durch robots.txt gesperrt`);
            continue;
          }
          // Volle Kaskade statt nur og:image (siehe Kommentar bei
          // enrichEntityKind weiter oben) — deckt jetzt auch Fälle ab, in
          // denen die Event-Seite kein og:image setzt, aber ein Hero-/
          // Bannerbild oder ein Bild im Content-Bereich hat.
          const detected = await detectEventCoverImage(pageUrl);
          const candidate = detected?.url ?? null;
          if (!candidate) {
            notes.push(`${pageUrl} liefert kein nutzbares Bild (og:image/Hero/Content-Bereich geprüft)`);
            continue;
          }
          const { reachable } = await checkImageUrl(candidate);
          if (!reachable) {
            notes.push(`Bild von ${pageUrl} nicht erreichbar/ungültig`);
            continue;
          }
          if (await isUrlUsedElsewhere(supabase, candidate, "events", event.id)) {
            notes.push(`Bild von ${pageUrl} bereits einem anderen Event zugeordnet (Duplikat)`);
            continue;
          }
          coverImage = candidate;
          break;
        }
        if (!coverImage) {
          await supabase
            .from("events")
            .update({ last_image_search_note: notes.join("; ") || "Kein Bild gefunden." })
            .eq("id", event.id);
          continue;
        }

        const now = new Date().toISOString();
        const { error: updateError } = await supabase
          .from("events")
          .update({
            image_urls: [coverImage],
            images_checked_at: now,
            updated_at: now,
            last_image_search_note: null,
          })
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
