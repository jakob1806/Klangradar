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
import { searchWikidataImage, searchWikidataOfficialWebsite } from "../_shared/wikidataImage.ts";
import { fetchWikipediaPortrait } from "../_shared/wikipediaPortrait.ts";
import { detectEventCoverImage } from "../_shared/coverImageDetection.ts";
import { extractImageNearName } from "../_shared/imageNearName.ts";
import {
  checkImageUrl,
  isLikelyGenericImage,
} from "../_shared/imageValidation.ts";
import { isAllowedByRobots } from "../_shared/robots.ts";
import { searchDuckDuckGo } from "../_shared/duckDuckGoSearch.ts";
import { searchViaGeminiGrounding } from "../_shared/geminiGroundedSearch.ts";
import { logSystemAction } from "../_shared/systemLog.ts";
import { nameSearchVariants } from "../_shared/nameVariants.ts";
import { findLikelySubpages } from "../_shared/subpageDiscovery.ts";
import { searchOfficialSiteForImages } from "../_shared/officialSiteImageSearch.ts";
import { ensureCoverImage, type ImageOriginType } from "../_shared/imagePipeline.ts";

const DEFAULT_LIMIT = 8;
const HEALTH_CHECK_LIMIT = 15;
const EVENT_URL_DISCOVERY_LIMIT = 5;
const ENTITY_URL_DISCOVERY_LIMIT = 5;

interface CandidateMetadata {
  imageUrl: string;
  sourcePageUrl: string;
  sourceName: string;
  photographer?: string | null;
  licenseName?: string | null;
  licenseUrl?: string | null;
  licenseStatus:
    | "confirmed_free"
    | "confirmed_licensed"
    | "official_press_image"
    | "permission_required"
    | "unknown";
  confidenceScore: number;
  matchReason: string;
  warnings?: string[];
  needsReview: boolean;
}

/** Zentraler Schreibpfad: jeder Kandidat wird validiert, heruntergeladen,
 * nach SHA-256/pHash dedupliziert und als WebP + Thumbnail im bestehenden
 * Storage abgelegt. Externe Hotlinks werden dadurch nicht mehr als App-URL
 * veröffentlicht. */
async function persistCandidate(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: { table: string; originType: ImageOriginType },
  id: string,
  candidate: CandidateMetadata,
): Promise<{ imageId: string; publicUrl: string } | null> {
  // Review-pflichtige Recherchetreffer zunächst nur mit ihrer externen
  // Quelle vormerken. Das Laden + WebP/pHash-WASM für jedes Fundstück ließ
  // die kleine Edge-Runtime bei großen Künstlerbildern mit
  // WORKER_RESOURCE_LIMIT sterben, bevor überhaupt ein Kandidat sichtbar
  // wurde. Die Freigabeansicht unterstützt storage_path=null bereits und
  // zeigt source_url; erst bestätigte Bilder werden regulär veröffentlicht.
  if (candidate.needsReview) {
    const { data: existing } = await supabase.from("images")
      .select("id")
      .eq("origin_type", kind.originType)
      .eq("origin_id", id)
      .eq("source_url", candidate.imageUrl)
      .neq("license_status", "rejected")
      .maybeSingle();
    if (existing?.id) return { imageId: existing.id, publicUrl: candidate.imageUrl };

    const { data, error } = await supabase.from("images").insert({
      source_url: candidate.imageUrl,
      original_image_url: candidate.imageUrl,
      storage_path: null,
      origin_type: kind.originType,
      origin_id: id,
      source_page_url: candidate.sourcePageUrl,
      source_name: candidate.sourceName,
      photographer: candidate.photographer ?? null,
      credits: candidate.photographer ?? null,
      license_name: candidate.licenseName ?? null,
      license_url: candidate.licenseUrl ?? null,
      license_status: candidate.licenseStatus,
      confidence_score: candidate.confidenceScore,
      match_reason: candidate.matchReason,
      warnings: candidate.warnings ?? [],
      needs_review: true,
    }).select("id").single();
    if (error || !data) return null;
    return { imageId: data.id, publicUrl: candidate.imageUrl };
  }

  const imageId = await ensureCoverImage(supabase, {
    sourceUrl: candidate.imageUrl,
    originType: kind.originType,
    originId: id,
    sourcePageUrl: candidate.sourcePageUrl,
    sourceName: candidate.sourceName,
    photographer: candidate.photographer,
    credits: candidate.photographer,
    licenseName: candidate.licenseName,
    licenseUrl: candidate.licenseUrl,
    licenseStatus: candidate.licenseStatus,
    confidenceScore: candidate.confidenceScore,
    matchReason: candidate.matchReason,
    warnings: candidate.warnings,
    needsReview: candidate.needsReview,
  });
  if (!imageId) return null;
  const { data: image } = await supabase.from("images").select("storage_path")
    .eq("id", imageId).maybeSingle();
  if (!image?.storage_path) return null;
  const { data } = supabase.storage.from("ingested-images").getPublicUrl(
    image.storage_path,
  );
  return { imageId, publicUrl: data.publicUrl };
}

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
  {
    table: "venues",
    originType: "venue",
    nameColumn: "name",
    queryContext: "München",
  },
  {
    table: "persons",
    originType: "person",
    nameColumn: "full_name",
    participantColumn: "person_id",
    useWikipediaFallback: true,
  },
  {
    table: "ensembles",
    originType: "ensemble",
    nameColumn: "name",
    participantColumn: "ensemble_id",
  },
  {
    table: "festivals",
    originType: "festival",
    nameColumn: "name",
    queryContext: "München",
  },
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
    {
      events: {
        website_url: string | null;
        ticket_url: string | null;
        start_datetime: string;
      };
    }
  >;
  if (rows.length === 0) return null;
  rows.sort((a, b) =>
    a.events.start_datetime.localeCompare(b.events.start_datetime)
  );
  for (const row of rows) {
    const url = row.events.website_url ?? row.events.ticket_url;
    if (url) return url;
  }
  return null;
}

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  let body: {
    limit?: unknown;
    type?: unknown;
    dryRun?: unknown;
    reviewOnly?: unknown;
    minConfidence?: unknown;
    entityIds?: unknown;
    fastFallback?: unknown;
    manualCandidates?: unknown;
    rehostCandidates?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0
    ? body.limit
    : DEFAULT_LIMIT;
  const minConfidence =
    typeof body.minConfidence === "number" && body.minConfidence >= 0 &&
      body.minConfidence <= 1
      ? body.minConfidence
      : 0.85;
  const entityIds = Array.isArray(body.entityIds)
    ? body.entityIds.filter((id): id is string =>
      typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id)
    ).slice(0, 500)
    : [];

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Separater, expliziter Modus für vorab extern recherchierte Bilder mit
  // bereits bekannter Ziel-Entität (z. B. Bulk-Import eines Bildpakets) —
  // überspringt die komplette Such-/Discovery-Kaskade oben und schreibt
  // jeden Kandidaten direkt über denselben Download/Dedupe/Review-Pfad wie
  // die reguläre Suche (persistCandidate/ensureCoverImage), IMMER mit
  // needsReview=true: eine extern gelieferte URL wurde hier nicht wie beim
  // eigenen-Website-Pfad verifiziert, gilt also als Fremdbild.
  if (Array.isArray(body.manualCandidates)) {
    return jsonResponse(
      await applyManualCandidates(supabase, body.manualCandidates),
    );
  }

  // Nochmal separater Modus: bereits freigegebene photo_url-Werte, die
  // direkt auf einen Drittanbieter verlinken (kein storage_path), erneut
  // über ensureCoverImage laufen lassen und die Entität auf den neuen,
  // in unserem eigenen Storage liegenden Link umstellen. Anders als
  // manualCandidates KEIN neuer Review-Fall — das Bild wurde bereits
  // redaktionell freigegeben, es wird nur die fragile Hotlink-Auslieferung
  // ersetzt (Nutzerfeedback: direktes Hotlinken v.a. auf Wikimedia Commons
  // führt bei vielen gleichzeitig geladenen Thumbnails zu HTTP 429, das
  // Bild bleibt dann in Galerie/App leer).
  if (Array.isArray(body.rehostCandidates)) {
    return jsonResponse(
      await applyRehostCandidates(supabase, body.rehostCandidates),
    );
  }

  const requestedType = typeof body.type === "string" ? body.type : "all";
  const selectedKinds = requestedType === "all"
    ? ENTITY_KINDS
    : ENTITY_KINDS.filter((kind) => kind.originType === requestedType);
  if (requestedType !== "all" && selectedKinds.length === 0) {
    return jsonResponse({ error: `Ungültiger Typ: ${requestedType}` }, 400);
  }

  // Dry-run ist garantiert schreibfrei: er inventarisiert die konkrete
  // Batch-Größe und Review-Queue, führt aber weder Webrequests noch Updates
  // aus. So kann ein großer Lauf sicher vorab eingeschätzt werden.
  if (body.dryRun === true || body.reviewOnly === true) {
    const inventory: Record<
      string,
      { missing: number; reviewPending: number }
    > = {};
    for (const kind of selectedKinds) {
      const [{ count: missing }, { count: reviewPending }] = await Promise.all([
        supabase.from(kind.table).select("id", { count: "exact", head: true })
          .is("photo_url", null),
        supabase.from("images").select("id", { count: "exact", head: true })
          .eq("origin_type", kind.originType).eq("needs_review", true),
      ]);
      inventory[kind.table] = {
        missing: missing ?? 0,
        reviewPending: reviewPending ?? 0,
      };
    }
    return jsonResponse({ dryRun: true, requestedType, limit, inventory });
  }

  const healthCheck: Record<
    string,
    { checked: number; brokenCleared: number }
  > = {};
  for (const kind of selectedKinds) {
    healthCheck[kind.table] = entityIds.length > 0 || body.fastFallback === true
      ? { checked: 0, brokenCleared: 0 }
      : await healthCheckEntityKind(supabase, kind);
  }
  const eventHealthCheck = requestedType === "all"
    ? await healthCheckEventImages(supabase)
    : { checked: 0, brokenCleared: 0 };

  const eventUrlDiscovery = requestedType === "all"
    ? await discoverMissingEventUrls(supabase)
    : { attempted: 0, found: 0 };

  const entityUrlDiscovery: Record<
    string,
    { attempted: number; found: number }
  > = {};
  for (const kind of selectedKinds) {
    entityUrlDiscovery[kind.table] = body.fastFallback === true
      ? { attempted: 0, found: 0 }
      : await discoverMissingEntityWebsites(supabase, kind, entityIds);
  }

  const perKind: Record<
    string,
    {
      found: number;
      autoApplied: number;
      queuedForReview: number;
      errors: string[];
    }
  > = {};
  for (const kind of selectedKinds) {
    // Eine Venue-Recherche lädt neben Commons/Wikidata häufig mehrere
    // Gebäudeseiten, Pressebereiche und großformatige Hero-Bilder. Drei
    // vollständige Kaskaden in einem Edge-Aufruf überschritten im Live-Test
    // das Worker-Limit und verloren dadurch ALLE Treffer des Batches.
    // Kleinere, dafür häufiger laufende Portionen liefern verlässlich
    // Fortschritt. Gezielte Admin-Nachläufe mit entityIds behalten ihr
    // explizites Limit.
    const effectiveLimit = entityIds.length > 0
      ? limit
      : kind.originType === "venue"
      ? Math.min(limit, 2)
      : Math.min(limit, 4);
    perKind[kind.table] = await enrichEntityKind(
      supabase,
      kind,
      effectiveLimit,
      minConfidence,
      entityIds,
      body.fastFallback === true,
    );
  }
  const eventResult = requestedType === "all"
    ? await enrichEventCovers(supabase, limit)
    : { found: 0, updated: 0, errors: [] };

  const totalAutoApplied = Object.values(perKind).reduce(
    (sum, r) => sum + r.autoApplied,
    0,
  );
  const totalQueued = Object.values(perKind).reduce(
    (sum, r) => sum + r.queuedForReview,
    0,
  );
  if (totalAutoApplied > 0 || totalQueued > 0 || eventResult.updated > 0) {
    await logSystemAction(supabase, "images", null, "auto_enrichment_batch", {
      healthCheck,
      eventHealthCheck,
      eventUrlDiscovery,
      entityUrlDiscovery,
      perKind,
      events: eventResult,
    });
  }

  return jsonResponse({
    healthCheck,
    eventHealthCheck,
    eventUrlDiscovery,
    entityUrlDiscovery,
    ...perKind,
    events: eventResult,
  });
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
      await supabase.from(kind.table).update({ photo_checked_at: now }).eq(
        "id",
        row.id,
      );
      continue;
    }
    brokenCleared++;
    await supabase.from(kind.table).update({
      photo_url: null,
      photo_checked_at: now,
    }).eq("id", row.id);
    await logSystemAction(
      supabase,
      kind.originType,
      row.id as string,
      "broken_photo_cleared",
      {
        name: row[kind.nameColumn],
        brokenUrl: row.photo_url,
      },
    );
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
  for (
    const row of rows as Array<
      { id: string; title: string; image_urls: string[] | null }
    >
  ) {
    if (!row.image_urls || row.image_urls.length === 0) continue;
    checked++;
    const { reachable } = await checkImageUrl(row.image_urls[0]);
    const now = new Date().toISOString();
    if (reachable) {
      await supabase.from("events").update({ images_checked_at: now }).eq(
        "id",
        row.id,
      );
      continue;
    }
    brokenCleared++;
    await supabase.from("events").update({
      image_urls: [],
      images_checked_at: now,
    }).eq("id", row.id);
    await logSystemAction(supabase, "event", row.id, "broken_image_cleared", {
      title: row.title,
      brokenUrl: row.image_urls[0],
    });
  }
  return { checked, brokenCleared };
}

interface ManualCandidateInput {
  originType: "venue" | "person" | "ensemble";
  originId: string;
  imageUrl: string;
  sourcePageUrl?: string;
  sourceName?: string;
  photographer?: string;
  licenseName?: string;
  licenseUrl?: string;
  matchReason?: string;
  confidenceScore?: number;
}

function parseManualCandidate(raw: unknown): ManualCandidateInput | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (
    typeof r.originType !== "string" ||
    !["venue", "person", "ensemble"].includes(r.originType) ||
    typeof r.originId !== "string" ||
    !/^[0-9a-f-]{36}$/i.test(r.originId) ||
    typeof r.imageUrl !== "string" || !r.imageUrl
  ) return null;
  return {
    originType: r.originType as ManualCandidateInput["originType"],
    originId: r.originId,
    imageUrl: r.imageUrl,
    sourcePageUrl: typeof r.sourcePageUrl === "string"
      ? r.sourcePageUrl
      : undefined,
    sourceName: typeof r.sourceName === "string" ? r.sourceName : undefined,
    photographer: typeof r.photographer === "string"
      ? r.photographer
      : undefined,
    licenseName: typeof r.licenseName === "string"
      ? r.licenseName
      : undefined,
    licenseUrl: typeof r.licenseUrl === "string" ? r.licenseUrl : undefined,
    matchReason: typeof r.matchReason === "string"
      ? r.matchReason
      : undefined,
    confidenceScore: typeof r.confidenceScore === "number"
      ? r.confidenceScore
      : undefined,
  };
}

async function applyManualCandidates(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  rawCandidates: unknown[],
): Promise<
  { applied: number; skipped: number; errors: string[] }
> {
  const candidates = rawCandidates.slice(0, 500).map(parseManualCandidate)
    .filter((c): c is ManualCandidateInput => c !== null);
  let applied = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const candidate of candidates) {
    const kind = ENTITY_KINDS.find((k) => k.originType === candidate.originType);
    if (!kind) {
      errors.push(`${candidate.originId}: unbekannter originType`);
      continue;
    }

    const { data: existing } = await supabase
      .from("images")
      .select("id")
      .eq("origin_type", candidate.originType)
      .eq("origin_id", candidate.originId)
      .neq("license_status", "rejected")
      .limit(1)
      .maybeSingle();
    if (existing) {
      skipped++;
      continue;
    }

    if (
      await isUrlUsedElsewhere(
        supabase,
        candidate.imageUrl,
        kind.table,
        candidate.originId,
      )
    ) {
      skipped++;
      continue;
    }

    const stored = await persistCandidate(supabase, kind, candidate.originId, {
      imageUrl: candidate.imageUrl,
      sourcePageUrl: candidate.sourcePageUrl ?? candidate.imageUrl,
      sourceName: candidate.sourceName ?? "Bildpaket-Import",
      photographer: candidate.photographer ?? null,
      licenseName: candidate.licenseName ?? null,
      licenseUrl: candidate.licenseUrl ?? null,
      licenseStatus: "unknown",
      confidenceScore: candidate.confidenceScore ?? 0.7,
      matchReason: candidate.matchReason ??
        `Bildpaket-Import, Namens-Match auf „${candidate.originId}“.`,
      warnings: ["Externe Bildquelle vor Veröffentlichung prüfen (Lizenz/Namensnennung)."],
      needsReview: true,
    });
    if (!stored) {
      errors.push(`${candidate.originType} ${candidate.originId}: Download/Storage fehlgeschlagen (${candidate.imageUrl})`);
      continue;
    }
    applied++;
  }

  return { applied, skipped, errors };
}

interface RehostCandidateInput {
  originType: "venue" | "person" | "ensemble";
  originId: string;
  currentPhotoUrl: string;
}

function parseRehostCandidate(raw: unknown): RehostCandidateInput | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (
    typeof r.originType !== "string" ||
    !["venue", "person", "ensemble"].includes(r.originType) ||
    typeof r.originId !== "string" ||
    !/^[0-9a-f-]{36}$/i.test(r.originId) ||
    typeof r.currentPhotoUrl !== "string" || !r.currentPhotoUrl
  ) return null;
  return {
    originType: r.originType as RehostCandidateInput["originType"],
    originId: r.originId,
    currentPhotoUrl: r.currentPhotoUrl,
  };
}

/** `is_primary` (welches Bild eine Entität repräsentiert) und `sort_order`
 * (welches Bild die Galerie an Position 0 zeigt) liefen bisher auseinander
 * — sowohl die Admin- als auch die App-Galerie sortieren ausschließlich
 * nach sort_order (siehe admin/src/lib/gallery-actions.ts's
 * setPrimaryGalleryImage für dasselbe Muster), is_primary-Schreibvorgänge
 * allein waren dadurch für das tatsächlich Angezeigte wirkungslos.
 * is_primary bleibt kanonisch, sort_order wird hier synchron mitgeführt. */
async function setPrimaryAndSortOrder(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  originType: string,
  originId: string,
  imageId: string,
): Promise<void> {
  const { data: images } = await supabase
    .from("images")
    .select("id, sort_order")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .order("sort_order", { ascending: true });

  const rows = (images ?? []) as Array<{ id: string; sort_order: number }>;
  const target = rows.find((r) => r.id === imageId);
  const reordered = target ? [target, ...rows.filter((r) => r.id !== imageId)] : rows;

  for (let i = 0; i < reordered.length; i++) {
    if (reordered[i].sort_order === i) continue;
    await supabase.from("images").update({ sort_order: i }).eq("id", reordered[i].id);
  }

  await supabase.from("images").update({ is_primary: false })
    .eq("origin_type", originType).eq("origin_id", originId);
  await supabase.from("images").update({ is_primary: true }).eq("id", imageId);
}

async function applyRehostCandidates(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  rawCandidates: unknown[],
): Promise<{ rehosted: number; skipped: number; errors: string[] }> {
  const candidates = rawCandidates.slice(0, 500).map(parseRehostCandidate)
    .filter((c): c is RehostCandidateInput => c !== null);
  let rehosted = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const candidate of candidates) {
    const kind = ENTITY_KINDS.find((k) => k.originType === candidate.originType);
    if (!kind) {
      errors.push(`${candidate.originId}: unbekannter originType`);
      continue;
    }

    // Nur umziehen, solange die Entität tatsächlich noch auf genau diese
    // (fragile) URL zeigt — sonst wurde inzwischen redaktionell etwas
    // anderes gesetzt, das nicht überschrieben werden soll.
    const { data: origin } = await supabase
      .from(kind.table)
      .select("photo_url")
      .eq("id", candidate.originId)
      .maybeSingle();
    if (!origin || origin.photo_url !== candidate.currentPhotoUrl) {
      skipped++;
      continue;
    }

    // Metadaten der bisherigen images-Zeile (falls vorhanden) übernehmen,
    // statt sie durch generische Werte zu ersetzen.
    const { data: existingMeta } = await supabase
      .from("images")
      .select("photographer, license_name, license_url, source_page_url, source_name, confidence_score, match_reason")
      .eq("origin_type", candidate.originType)
      .eq("origin_id", candidate.originId)
      .eq("source_url", candidate.currentPhotoUrl)
      .maybeSingle();

    const imageId = await ensureCoverImage(supabase, {
      sourceUrl: candidate.currentPhotoUrl,
      originType: candidate.originType,
      originId: candidate.originId,
      sourcePageUrl: existingMeta?.source_page_url ?? null,
      sourceName: existingMeta?.source_name ?? null,
      photographer: existingMeta?.photographer ?? null,
      credits: existingMeta?.photographer ?? null,
      licenseName: existingMeta?.license_name ?? null,
      licenseUrl: existingMeta?.license_url ?? null,
      licenseStatus: "confirmed_free",
      confidenceScore: existingMeta?.confidence_score ?? null,
      matchReason: existingMeta?.match_reason ??
        "Rehost: bereits freigegebenes Bild, fragiler Hotlink durch eigenen Storage-Link ersetzt.",
      needsReview: false,
    });
    if (!imageId) {
      errors.push(`${candidate.originType} ${candidate.originId}: Rehost fehlgeschlagen (${candidate.currentPhotoUrl})`);
      continue;
    }

    const { data: image } = await supabase.from("images").select("storage_path")
      .eq("id", imageId).maybeSingle();
    if (!image?.storage_path) {
      errors.push(`${candidate.originType} ${candidate.originId}: kein storage_path nach Rehost`);
      continue;
    }
    const { data: publicUrlData } = supabase.storage.from("ingested-images")
      .getPublicUrl(image.storage_path);

    const { error: updateError } = await supabase
      .from(kind.table)
      .update({ photo_url: publicUrlData.publicUrl })
      .eq("id", candidate.originId)
      .eq("photo_url", candidate.currentPhotoUrl);
    if (updateError) {
      errors.push(`${candidate.originType} ${candidate.originId}: ${updateError.message}`);
      continue;
    }

    await setPrimaryAndSortOrder(supabase, candidate.originType, candidate.originId, imageId);

    rehosted++;
  }

  return { rehosted, skipped, errors };
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
    let query = supabase.from(kind.table).select("id", {
      count: "exact",
      head: true,
    }).eq("photo_url", url);
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
    let eventsQuery = supabase.from("events").select("id", {
      count: "exact",
      head: true,
    }).contains(
      "image_urls",
      [url],
    );
    if (excludeTable === "events") {
      eventsQuery = eventsQuery.neq("id", excludeId);
    }
    const { count } = await eventsQuery;
    if (count && count > 0) return true;
  }
  // Auch gegen bereits (für eine ANDERE Entität) in die Review-Queue
  // gestellte, noch nicht abgelehnte Kandidaten prüfen — sonst kann
  // dieselbe generische Grafik (z. B. ein "Tickets kaufen"-Icon, das
  // fälschlich als Bild mehrerer verschiedener Mitwirkender erkannt
  // wurde) mehrfach parallel zur Prüfung vorgelegt werden, bevor eine
  // Redakteurin den ersten Fall überhaupt gesehen hat.
  const { data: queuedImages } = await supabase
    .from("images")
    .select("id, origin_type, origin_id")
    .eq("source_url", url)
    .neq("license_status", "rejected")
    .limit(25);

  // Zusammengeführte/gelöschte Personen hinterließen früher vereinzelt
  // polymorphe images-Zeilen. Diese verwaisten Zeilen dürfen einen erneut
  // gefundenen, korrekten Kandidaten nicht dauerhaft blockieren. Das war
  // live u. a. bei Beethoven der Fall: Das Commons-Porträt war genehmigt,
  // sein origin_id zeigte aber auf die beim Merge entfernte Dublette und die
  // kanonische Person blieb deshalb ohne Foto.
  const originTable: Record<string, string> = {
    event: "events",
    venue: "venues",
    ensemble: "ensembles",
    person: "persons",
    organizer: "organizers",
    festival: "festivals",
    work: "works",
    editorial_collection: "editorial_collections",
  };
  for (const image of queuedImages ?? []) {
    const imageOriginType = String(image.origin_type ?? "");
    const imageOriginId = String(image.origin_id ?? "");
    const currentKind = ENTITY_KINDS.find((kind) => kind.table === excludeTable);
    const currentOriginType = currentKind?.originType ??
      (excludeTable === "events" ? "event" : "");
    if (imageOriginType === currentOriginType && imageOriginId === excludeId) {
      continue;
    }

    const table = originTable[imageOriginType];
    // Unbekannte künftige Origin-Typen konservativ weiter als belegt
    // behandeln; nur nachweislich verwaiste Zuordnungen ignorieren.
    if (!table || !imageOriginId) return true;
    const { data: owner, error } = await supabase.from(table).select("id")
      .eq("id", imageOriginId).maybeSingle();
    if (error || owner) return true;
  }
  return false;
}

/** Letzter, kostenloser Fallback für ALLE Entity-Kinds — auch für Personen,
 * nach einem erfolglosen Wikipedia-Versuch: Wikidata-Suche + P18-
 * Bildeigenschaft, aufgelöst über denselben Commons-Lizenzcheck wie die
 * reguläre Volltextsuche (siehe wikidataImage.ts/wikimediaCommons.ts).
 * Manche Entitäten haben keinen (Wikipedia-)Artikel mit Infobox-Bild, aber
 * ein eigenständiges Wikidata-Item mit strukturiert verknüpftem Bild — oder
 * die Commons-Volltextsuche rankt die richtige Datei nicht hoch genug.
 *
 * Rückgabe statt reinem Boolean, weil drei Fälle unterscheidbar sein
 * müssen: "queued" (Aufrufer zählt queuedForReview++ und macht `continue`),
 * "error" (Insert fehlgeschlagen, schon in `errors` erfasst — Aufrufer
 * macht `continue`, OHNE die generische "nichts gefunden"-Notiz zu
 * überschreiben, denn es WURDE etwas gefunden) und "not_found" (Aufrufer
 * setzt wie bisher seine eigene Notiz). */
async function tryWikidataFallback(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
  id: string,
  name: string,
  errors: string[],
): Promise<"queued" | "error" | "not_found"> {
  let candidate: Awaited<ReturnType<typeof searchWikidataImage>> = null;
  for (const variant of nameSearchVariants(name)) {
    candidate = await searchWikidataImage(variant, kind.queryContext);
    if (candidate) break;
  }
  if (!candidate) return "not_found";

  const { reachable } = await checkImageUrl(candidate.url);
  if (!reachable) return "not_found";
  if (await isUrlUsedElsewhere(supabase, candidate.url, kind.table, id)) {
    return "not_found";
  }

  const stored = await persistCandidate(supabase, kind, id, {
    imageUrl: candidate.url,
    sourcePageUrl: candidate.pageUrl,
    sourceName: "Wikimedia Commons",
    photographer: candidate.artist,
    licenseName: candidate.license,
    licenseStatus: "confirmed_free",
    confidenceScore: 0.82,
    matchReason:
      `Strukturiertes Wikidata-P18-Bild für „${name}“, Lizenz über Commons verifiziert.`,
    warnings: ["Identitätszuordnung vor Veröffentlichung redaktionell prüfen."],
    needsReview: true,
  });
  if (!stored) {
    errors.push(`${kind.table} "${name}": Download/Storage fehlgeschlagen`);
    return "error";
  }

  await supabase
    .from(kind.table)
    .update({
      last_image_search_note:
        "Wikidata-Kandidat gefunden, wartet auf Lizenzprüfung (/media).",
    })
    .eq("id", id);
  return "queued";
}

/** Breiter, vollständig kostenloser Web-Fallback nur für Personen, wenn
 * Wikipedia und Wikidata kein Porträt liefern. Die DuckDuckGo-Websuche
 * findet offizielle, Agentur-, Operabase-, Orchester- und Veranstalterseiten;
 * das dort erkannte Bild wird niemals blind
 * veröffentlicht, sondern als heruntergeladener Kandidat in die
 * redaktionelle Bildprüfung gestellt. */
function imagePageScore(url: string, originType: ImageOriginType): number {
  const value = url.toLowerCase();
  if (/facebook|instagram|linkedin|pinterest|youtube|tiktok|x\.com/.test(value)) return -100;
  let score = 0;
  if (/operabase\.com/.test(value)) score += 35;
  if (/agency|agentur|management|artists|artist|biograph|biograf|press|presse|media/.test(value)) score += 22;
  if (/opera|oper\b|orchester|orchestra|philharm|symphon|festival|theater|concert/.test(value)) score += 16;
  if (originType === "venue" && /venue|spielstaette|konzerthaus|concert-hall|theatre|architecture/.test(value)) score += 20;
  if (originType === "ensemble" && /ensemble|choir|chor|quartet|quartett|band/.test(value)) score += 20;
  if (/ticket|shop|calendar|kalender/.test(value)) score -= 15;
  return score;
}

async function tryMultiSourceWebImageFallback(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
  id: string,
  name: string,
  errors: string[],
): Promise<boolean> {
  const context = kind.queryContext ? ` ${kind.queryContext}` : "";
  const typeTerm = kind.originType === "person"
    ? "Musiker Künstler Porträt"
    : kind.originType === "ensemble"
    ? "Ensemble Orchester Chor Pressefoto"
    : kind.originType === "venue"
    ? "Veranstaltungsort Gebäude Pressefoto"
    : "Pressefoto";
  const queries = [
    `"${name}"${context} ${typeTerm} offizielle Website`,
    `"${name}"${context} press media photo`,
    `"${name}" site:operabase.com OR opera OR orchestra OR philharmonic OR theater OR festival`,
  ];
  const pages: Array<{ url: string; title: string | null }> = [];
  // Wikidata P856 verweist kostenlos und strukturiert auf die offizielle
  // Künstlerwebsite. Damit bleibt die Recherche auch dann funktionsfähig,
  // wenn die kostenlose HTML-Suchmaschine vorübergehend drosselt.
  const officialWebsite = await searchWikidataOfficialWebsite(name);
  if (officialWebsite) {
    // Der bereits vorhandene spezialisierte Crawler durchsucht neben der
    // Startseite auch Presse-, Media-, Galerie-, Bio- und Team-Unterseiten
    // und bewertet schema.org-, Meta-, Hero- und Inhaltsbilder. Im Cron
    // bewusst auf vier Seiten begrenzen, damit mehrere Personen pro Lauf
    // innerhalb der Edge-Ressourcen bleiben.
    const crawl = await searchOfficialSiteForImages(name, officialWebsite, { maxPages: 4 });
    for (const candidate of crawl.candidates.slice(0, 3)) {
      if (isLikelyGenericImage(candidate.url)) continue;
      const { reachable } = await checkImageUrl(candidate.url);
      if (!reachable || await isUrlUsedElsewhere(supabase, candidate.url, kind.table, id)) continue;
      const stored = await persistCandidate(supabase, kind, id, {
        imageUrl: candidate.url,
        sourcePageUrl: candidate.pageUrl,
        sourceName: new URL(candidate.pageUrl).hostname,
        licenseStatus: "permission_required",
        confidenceScore: candidate.confidence === "high" ? 0.9 : candidate.confidence === "medium" ? 0.8 : 0.68,
        matchReason: `Porträt auf der offiziellen Website von „${name}“: ${candidate.reasons.join(" ")}`,
        warnings: ["Bildcredit und Nutzungserlaubnis vor Veröffentlichung prüfen."],
        needsReview: true,
      });
      if (!stored) continue;
      await supabase.from("persons").update({
        last_image_search_note: "Kandidat von der offiziellen Website gefunden, wartet auf Bilderfreigabe (/media).",
        image_search_checked_at: new Date().toISOString(),
      }).eq("id", id);
      return true;
    }
    pages.push({ url: officialWebsite, title: "Offizielle Website (Wikidata)" });
  }
  for (const query of queries) {
    for (const result of await searchDuckDuckGo(query, 4) ?? []) {
      if (!pages.some((page) => page.url === result.url)) pages.push({ url: result.url, title: null });
    }
    if (pages.length >= 9) break;
  }

  // Hochwertige Fach-/Primärquellen zuerst prüfen. So verbraucht ein Lauf
  // nicht seine knappe Zeit mit sozialen Netzwerken oder Ticketshops.
  pages.sort((a, b) => {
    const aScore = a.title === "Offizielle Website (Wikidata)" ? 100 : imagePageScore(a.url, kind.originType);
    const bScore = b.title === "Offizielle Website (Wikidata)" ? 100 : imagePageScore(b.url, kind.originType);
    return bScore - aScore;
  });
  for (const page of pages.filter((page) => imagePageScore(page.url, kind.originType) > -100).slice(0, 8)) {
    try {
      const detected = await detectEventCoverImage(page.url);
      // Viele Agentur-/Künstlerseiten pflegen kein og:image. Dort gezielt
      // ein mit dem Namen beschriftetes Bild suchen, statt den Treffer trotz
      // vorhandenen Porträts wegzuwerfen.
      // Auch bei einem generisch wirkenden og:image weiter suchen: Dateinamen
      // wie "artist-events.jpg" können auf der offiziellen Künstlerseite
      // trotzdem ein korrektes Porträt sein. Der namensbezogene Treffer ist
      // in diesem Fall die sicherere Wahl.
      let imageUrl = detected?.url ?? null;
      if (!imageUrl || isLikelyGenericImage(imageUrl)) {
        imageUrl = await extractImageNearName(page.url, name);
      }
      if (!imageUrl || isLikelyGenericImage(imageUrl)) continue;
      const { reachable } = await checkImageUrl(imageUrl);
      if (!reachable || await isUrlUsedElsewhere(supabase, imageUrl, kind.table, id)) continue;
      const stored = await persistCandidate(supabase, kind, id, {
        imageUrl,
        sourcePageUrl: page.url,
        sourceName: new URL(page.url).hostname,
        photographer: detected?.credits ?? null,
        licenseStatus: detected?.credits ? "official_press_image" : "permission_required",
        confidenceScore: 0.72,
        matchReason: `Kostenfreie Websuche nach „${name}“${page.title ? ` — Treffer „${page.title}“` : ""}.`,
        warnings: ["Identität, Bildcredit und Nutzungserlaubnis vor Veröffentlichung prüfen."],
        needsReview: true,
      });
      if (!stored) {
        errors.push(`persons "${name}": Webbild konnte nicht gespeichert werden`);
        continue;
      }
      await supabase.from(kind.table).update({
        last_image_search_note: `Kandidat aus erweiterter Mehrquellen-Suche (${new URL(page.url).hostname}) gefunden, wartet auf Bilderfreigabe (/media).`,
        image_search_checked_at: new Date().toISOString(),
      }).eq("id", id);
      return true;
    } catch {
      // Einzelne blockierte/kaputte Treffer überspringen; weitere Quelle
      // versuchen, ohne den gesamten Personenbatch abzubrechen.
    }
  }
  return false;
}

async function enrichEntityKind(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
  limit: number,
  minConfidence: number,
  entityIds: string[] = [],
  fastFallback = false,
): Promise<
  {
    found: number;
    autoApplied: number;
    queuedForReview: number;
    errors: string[];
  }
> {
  // Fairer Queue-Zeitstempel statt Sortierung nach dem Diagnose-Text: Die
  // alte Reihenfolge konnte nach dem ersten vollständigen Umlauf immer
  // wieder dieselben erfolglosen Zeilen auswählen. Älteste/nie geprüfte
  // Entitäten kommen nun zuverlässig zuerst.
  let rowQuery = supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}, website_url`)
    .is("photo_url", null)
    .order("image_search_checked_at", { ascending: true, nullsFirst: true })
    // Innerhalb desselben Queue-Alters zuerst Datensätze mit offizieller
    // Website bearbeiten: Dort ist die Trefferwahrscheinlichkeit deutlich
    // höher als bei einer reinen Namenssuche.
    .order("website_url", { ascending: false, nullsFirst: false });
  if (entityIds.length > 0) rowQuery = rowQuery.in("id", entityIds);
  const { data: rows, error } = await rowQuery.limit(limit);

  if (error) {
    return {
      found: 0,
      autoApplied: 0,
      queuedForReview: 0,
      errors: [`${kind.table}: Laden fehlgeschlagen — ${error.message}`],
    };
  }

  const list = (rows ?? []) as Array<Record<string, unknown>>;
  let autoApplied = 0;
  let queuedForReview = 0;
  const errors: string[] = [];

  const setNote = (id: string, note: string | null) =>
    supabase.from(kind.table).update({
      last_image_search_note: note,
      image_search_checked_at: new Date().toISOString(),
    }).eq(
      "id",
      id,
    );

  for (const row of list) {
    const id = row.id as string;
    const name = row[kind.nameColumn] as string;
    const websiteUrl = row.website_url as string | null;
    if (!name?.trim()) continue;

    try {
      // Ein gezielter manueller Nachlauf ist idempotent: Existiert bereits
      // ein nicht abgelehnter Kandidat, wird weder die Quellseite erneut
      // geladen noch ein zweites Bild angelegt.
      if (entityIds.length > 0) {
        const { data: existingTargetedCandidate } = await supabase
          .from("images")
          .select("id")
          .eq("origin_type", kind.originType)
          .eq("origin_id", id)
          .neq("license_status", "rejected")
          .limit(1)
          .maybeSingle();
        if (existingTargetedCandidate) {
          await setNote(
            id,
            "Kandidat gefunden, wartet auf redaktionelle Lizenzprüfung (/media).",
          );
          continue;
        }
      }

      // Priorität 2: eigene offizielle Website. Direkt übernommen, kein
      // Review — es ist die Entität selbst, die dieses Bild von sich
      // öffentlich zeigt, kein Fremdbild eines Dritten.
      // `fastFallback` darf nur Health-Checks und URL-Discovery abkürzen,
      // nicht die bereits bekannte offizielle Website überspringen. Genau
      // das tat der Cron bisher und schloss hunderte Personen trotz
      // vorhandener Primärquelle als „kein Bild gefunden“ ab.
      if (websiteUrl) {
        if (!(await isAllowedByRobots(websiteUrl))) {
          await setNote(
            id,
            "Eigene Website durch robots.txt gesperrt — Zugriff verweigert.",
          );
        } else {
          // Entitätsspezifischer Tiefencrawler: anders als der einfache
          // Event-Cover-Parser versteht er auch data-image/data-src/srcset,
          // schema.org Person/MusicGroup sowie Presse-, Portrait-, Galerie-,
          // Bio- und Team-Unterseiten. Das schließt insbesondere
          // Squarespace-/Agenturseiten, auf denen das sichtbare Porträt
          // nicht als og:image hinterlegt ist.
          const officialCrawl = await searchOfficialSiteForImages(name, websiteUrl, {
            maxPages: fastFallback ? 4 : 8,
          });
          let officialCandidateQueued = false;
          for (const candidate of officialCrawl.candidates.slice(0, 5)) {
            if (candidate.confidence === "low" || isLikelyGenericImage(candidate.url)) continue;
            const { reachable } = await checkImageUrl(candidate.url);
            if (!reachable || await isUrlUsedElsewhere(supabase, candidate.url, kind.table, id)) continue;
            const stored = await persistCandidate(supabase, kind, id, {
              imageUrl: candidate.url,
              sourcePageUrl: candidate.pageUrl,
              sourceName: new URL(candidate.pageUrl).hostname,
              licenseStatus: "permission_required",
              confidenceScore: candidate.confidence === "high" ? 0.92 : 0.8,
              matchReason: `Offizielle Website von „${name}“: ${candidate.reasons.join(" ")}`,
              warnings: ["Bildcredit und Nutzungserlaubnis vor Veröffentlichung prüfen."],
              needsReview: true,
            });
            if (!stored) continue;
            queuedForReview++;
            await setNote(id, "Porträt auf offizieller Website gefunden, wartet auf Bilderfreigabe (/media).");
            officialCandidateQueued = true;
            break;
          }
          if (officialCandidateQueued) continue;

          // Volle Kaskade (schema.org -> og:image -> twitter:image -> Hero/
          // Banner -> Bild im Content-Container) statt nur og:image/
          // twitter:image — dieselbe Erkennung, die der Ingestion-Importer
          // seit PR #92 für neue Events nutzt (coverImageDetection.ts), war
          // hier bisher nicht verdrahtet, obwohl die meisten bildlosen
          // Entities durchaus eine website_url hinterlegt haben.
          let detected = await detectEventCoverImage(websiteUrl);
          let ownImageSourcePage = websiteUrl;
          if (!detected) {
            // Startseite liefert nichts — 1-2 wahrscheinliche Unterseiten
            // (Presse/Über uns/Kontakt) derselben Domain versuchen, bevor
            // aufgegeben wird. Viele Vereine/Ensembles haben eine
            // text-lastige Startseite ohne Foto, aber ein Foto auf einer
            // "Über uns"-Unterseite.
            const subpages = await findLikelySubpages(websiteUrl);
            for (const subpageUrl of subpages) {
              const subDetected = await detectEventCoverImage(subpageUrl);
              if (subDetected) {
                detected = subDetected;
                ownImageSourcePage = subpageUrl;
                break;
              }
            }
          }
          const ownImage = detected?.url ?? null;
          if (!ownImage) {
            await setNote(
              id,
              "Eigene Website liefert kein nutzbares Bild (og:image/Hero/Content-Bereich/Unterseiten geprüft).",
            );
          } else {
            const { reachable } = await checkImageUrl(ownImage);
            if (!reachable) {
              await setNote(
                id,
                "Bild von der eigenen Website nicht erreichbar/kein gültiges Bildformat.",
              );
            } else if (
              await isUrlUsedElsewhere(supabase, ownImage, kind.table, id)
            ) {
              await setNote(
                id,
                "Bild von der eigenen Website ist bereits einer anderen Entität zugeordnet (Duplikat).",
              );
            } else {
              let requiresReview = !detected?.credits || 0.96 < minConfidence;
              const metadata: CandidateMetadata = {
                imageUrl: ownImage,
                sourcePageUrl: ownImageSourcePage,
                sourceName: new URL(ownImageSourcePage).hostname,
                photographer: detected?.credits ?? null,
                licenseStatus: detected?.credits
                  ? "official_press_image"
                  : "permission_required",
                confidenceScore: 0.96,
                matchReason:
                  `Bild stammt von der hinterlegten offiziellen Website von „${name}“.`,
                warnings: detected?.credits ? [] : [
                  "Kein vollständiger Bildcredit auf der Quellseite erkannt.",
                ],
                needsReview: requiresReview,
              };
              let stored = await persistCandidate(supabase, kind, id, metadata);
              // Große Originale können die WebP/pHash-Verarbeitung der Edge-
              // Runtime sprengen. Der Fund darf dann nicht verloren gehen:
              // als externer, review-pflichtiger Kandidat speichern; nach
              // Freigabe kann er separat rehosted werden.
              if (!stored && !requiresReview) {
                requiresReview = true;
                stored = await persistCandidate(supabase, kind, id, {
                  ...metadata,
                  needsReview: true,
                  warnings: [...(metadata.warnings ?? []), "Automatische Bildverarbeitung fehlgeschlagen; Originalquelle vor Freigabe prüfen."],
                });
              }
              if (!stored) {
                errors.push(
                  `${kind.table} "${name}": Bilddownload/Storage fehlgeschlagen`,
                );
                continue;
              }
              // Nur bei vollständigem Credit automatisch veröffentlichen.
              // Sonst bleibt der Storage-Kandidat ausschließlich in /media.
              if (requiresReview) {
                queuedForReview++;
                await setNote(
                  id,
                  "Offizieller Bildkandidat ohne vollständigen Credit wartet auf Prüfung (/media).",
                );
                continue;
              }
              const now = new Date().toISOString();
              const { error: updateError } = await supabase
                .from(kind.table)
                .update({
                  photo_url: stored.publicUrl,
                  photo_checked_at: now,
                  image_search_checked_at: now,
                  last_image_search_note: null,
                })
                .eq("id", id);
              if (updateError) {
                errors.push(
                  `${kind.table} "${name}": Update fehlgeschlagen — ${updateError.message}`,
                );
                continue;
              }
              autoApplied++;
              continue;
            }
          }
        }
      } else if (!websiteUrl) {
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
        await setNote(
          id,
          "Kandidat gefunden, wartet auf redaktionelle Lizenzprüfung (/media).",
        );
        continue;
      }

      // Priorität 2b: Bild von der Seite einer konkreten bevorstehenden
      // Veranstaltung, bei der diese Person/dieses Ensemble mitwirkt —
      // präziser als eine blinde Namenssuche, aber Seite eines Dritten
      // ohne bekannte Lizenz, daher immer review-pflichtig.
      // Auch im regulären Cron-Lauf ausführen: `fastFallback` hatte diesen
      // wichtigsten kostenlosen Rückfall komplett deaktiviert. Damit
      // blieben gerade neue Künstler:innen ohne Wikipedia und ohne bereits
      // hinterlegte Website dauerhaft ohne jeden Kandidaten, obwohl ihre
      // Veranstaltungs-/Besetzungsseite häufig ein Porträt enthält. Die
      // Cron-Batches sind klein genug, dass ein einzelner zielgerichteter
      // Seitenabruf pro Entität vertretbar bleibt.
      if (kind.participantColumn) {
        const eventPageUrl = await findUpcomingEventPageUrl(
          supabase,
          kind.participantColumn,
          id,
        );
        if (eventPageUrl) {
          const nearImage = await extractImageNearName(eventPageUrl, name);
          if (nearImage && !isLikelyGenericImage(nearImage)) {
            const { reachable } = await checkImageUrl(nearImage);
            if (
              reachable &&
              !(await isUrlUsedElsewhere(supabase, nearImage, kind.table, id))
            ) {
              const stored = await persistCandidate(supabase, kind, id, {
                imageUrl: nearImage,
                sourcePageUrl: eventPageUrl,
                sourceName: new URL(eventPageUrl).hostname,
                licenseStatus: "permission_required",
                confidenceScore: 0.78,
                matchReason:
                  `Bild steht auf einer konkreten Veranstaltungsseite in unmittelbarer Nähe zum Namen „${name}“.`,
                warnings: [
                  "Drittquelle; Nutzungserlaubnis und Credit müssen manuell geklärt werden.",
                ],
                needsReview: true,
              });
              if (!stored) {
                errors.push(
                  `${kind.table} "${name}": Download/Storage fehlgeschlagen`,
                );
              } else {
                queuedForReview++;
                await setNote(
                  id,
                  "Kandidat von einer Veranstaltungsseite gefunden, wartet auf Lizenzprüfung (/media).",
                );
              }
              continue;
            }
          }
        }
      }

      // Priorität 3: Wikipedia-Infobox-Bild — jetzt für ALLE Entity-Kinds
      // versucht (vorher nur Personen), da bekannte Ensembles/Festivals und
      // historische Venues genauso oft einen eigenen Artikel mit kuratiertem
      // Infobox-Bild haben (z. B. "Bayerisches Staatsorchester",
      // "Prinzregententheater") — ein einzelnes, redaktionell gepflegtes
      // Bild pro Artikel ist zuverlässiger als das Ranking einer
      // Commons-Volltextsuche.
      let portrait: Awaited<ReturnType<typeof fetchWikipediaPortrait>> = null;
      for (const variant of nameSearchVariants(name)) {
        portrait = await fetchWikipediaPortrait(variant);
        if (portrait) break;
      }
      if (portrait) {
        const { reachable } = await checkImageUrl(portrait.imageUrl);
        if (!reachable) {
          await setNote(
            id,
            "Wikipedia-Bild nicht erreichbar/kein gültiges Bildformat.",
          );
        } else if (
          await isUrlUsedElsewhere(supabase, portrait.imageUrl, kind.table, id)
        ) {
          await setNote(
            id,
            "Wikipedia-Bild ist bereits einer anderen Entität zugeordnet (Duplikat).",
          );
        } else {
          const stored = await persistCandidate(supabase, kind, id, {
            imageUrl: portrait.imageUrl,
            sourcePageUrl: portrait.pageUrl,
            sourceName: "Wikipedia",
            licenseStatus: "unknown",
            confidenceScore: 0.86,
            matchReason:
              `Infobox-Bild des eindeutig aufgelösten Wikipedia-Artikels „${name}“.`,
            warnings: [
              "Wikipedia dient nur der Identifikation; Lizenz auf der verknüpften Bildseite prüfen.",
            ],
            needsReview: true,
          });
          if (stored) {
            queuedForReview++;
            await setNote(
              id,
              "Wikipedia-Kandidat gefunden, wartet auf Lizenzprüfung (/media).",
            );
            continue;
          }
          errors.push(`${kind.table} "${name}": Wikipedia-Kandidat konnte nicht gespeichert werden`);
        }
      }

      // Priorität 4: Personen nutzen bewusst KEINE Commons-Volltextsuche
      // (siehe wikimediaCommons.ts-Datei-Kommentar: zu viele Fehltreffer bei
      // Namensgleichheiten), gehen direkt zu Wikidata. Venues/Ensembles/
      // Festivals versuchen zuerst Commons.
      if (!kind.useWikipediaFallback) {
        let candidate: Awaited<ReturnType<typeof searchCommonsImage>> = null;
        for (const variant of nameSearchVariants(name)) {
          const query = kind.queryContext
            ? `${variant} ${kind.queryContext}`
            : variant;
          candidate = await searchCommonsImage(query);
          if (candidate) break;
        }
        if (candidate) {
          const { reachable } = await checkImageUrl(candidate.url);
          if (!reachable) {
            await setNote(
              id,
              "Wikimedia-Bild nicht erreichbar/kein gültiges Bildformat.",
            );
            continue;
          }
          if (
            await isUrlUsedElsewhere(supabase, candidate.url, kind.table, id)
          ) {
            await setNote(
              id,
              "Wikimedia-Bild ist bereits einer anderen Entität zugeordnet (Duplikat).",
            );
            continue;
          }
          const stored = await persistCandidate(supabase, kind, id, {
            imageUrl: candidate.url,
            sourcePageUrl: candidate.pageUrl,
            sourceName: "Wikimedia Commons",
            photographer: candidate.artist,
            licenseName: candidate.license,
            licenseStatus: "confirmed_free",
            confidenceScore: 0.72,
            matchReason:
              `Namens- und Kontextsuche nach „${name}“ auf Wikimedia Commons.`,
            warnings: [
              "Treffer stammt aus Volltextsuche; Identität redaktionell bestätigen.",
            ],
            needsReview: true,
          });
          if (!stored) {
            errors.push(
              `${kind.table} "${name}": Download/Storage fehlgeschlagen`,
            );
            continue;
          }
          queuedForReview++;
          await setNote(
            id,
            "Wikimedia-Kandidat gefunden, wartet auf Lizenzprüfung (/media).",
          );
          continue;
        }
      }

      // Priorität 5: Wikidata (P18) — letzter kostenloser Fallback für alle
      // Kinds, bevor endgültig aufgegeben wird.
      const wikidataOutcome = await tryWikidataFallback(
        supabase,
        kind,
        id,
        name,
        errors,
      );
      if (wikidataOutcome === "queued") queuedForReview++;
      if (wikidataOutcome !== "not_found") continue;
      const webQueued = await tryMultiSourceWebImageFallback(supabase, kind, id, name, errors);
      if (webQueued) {
        queuedForReview++;
        continue;
      }
      await setNote(
        id,
        kind.useWikipediaFallback
          ? "Kein eindeutiges Porträt in Wikipedia, Wikidata oder der erweiterten Websuche gefunden."
          : "Keine passende Wikimedia-Commons-Datei gefunden.",
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push(`${kind.table} "${name}": ${message}`);
      await setNote(id, `Bildrecherche vorübergehend fehlgeschlagen: ${message.slice(0, 180)}. Automatischer neuer Versuch eingeplant.`);
    }
  }

  return {
    found: list.length,
    autoApplied,
    queuedForReview,
    errors: errors.slice(0, 10),
  };
}

/** Analog zu discoverMissingEventUrls() (siehe dort für die Begründung
 * Gemini-Grounding+DuckDuckGo statt Tavily/Google CSE) — aber für Venues/
 * Personen/Ensembles/Festivals ohne website_url. Nur relevant für Zeilen
 * OHNE photo_url: eine Website zu finden bringt nichts, wenn schon ein Bild
 * vorhanden ist. Setzt nur website_url; das eigentliche Bild zieht
 * enrichEntityKind()'s "eigene Website"-Priorität daraus im selben oder
 * einem der nächsten Läufe (Reihenfolge im Deno.serve-Handler: erst
 * Discovery für alle Entity-Kinds, dann enrichEntityKind für alle —
 * innerhalb desselben Laufs sichtbar). Keine neue Abhängigkeit, dieselbe
 * bereits vorhandene (und bereits bezahlte) Suche wie bei Events. */
async function discoverMissingEntityWebsites(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  kind: EntityKind,
  entityIds: string[] = [],
): Promise<{ attempted: number; found: number }> {
  const geminiApiKey = Deno.env.get("GEMINI_SEARCH_API_KEY");

  let discoveryQuery = supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}`)
    .is("website_url", null)
    .is("photo_url", null);
  if (entityIds.length > 0) discoveryQuery = discoveryQuery.in("id", entityIds);
  const { data: rows } = await discoveryQuery.limit(
    entityIds.length > 0 ? Math.min(entityIds.length, 500) : ENTITY_URL_DISCOVERY_LIMIT,
  );

  const list = (rows ?? []) as Array<Record<string, unknown>>;
  let found = 0;

  for (const row of list) {
    const id = row.id as string;
    const name = row[kind.nameColumn] as string;
    if (!name?.trim()) continue;

    const query = kind.queryContext
      ? `${name} ${kind.queryContext} offizielle Website`
      : `${name} offizielle Website`;

    let topResultUrl: string | null = null;

    if (geminiApiKey) {
      const groundedResults = await searchViaGeminiGrounding(
        geminiApiKey,
        query,
      );
      if (groundedResults && groundedResults.length > 0) {
        topResultUrl = groundedResults[0].url;
      }
    }
    if (!topResultUrl) {
      const ddgResults = await searchDuckDuckGo(query, 3);
      if (ddgResults && ddgResults.length > 0) topResultUrl = ddgResults[0].url;
    }
    if (!topResultUrl) continue;

    await supabase.from(kind.table).update({ website_url: topResultUrl }).eq(
      "id",
      id,
    );
    found++;
  }

  return { attempted: list.length, found };
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

  const rows = (events ?? []) as Array<
    { id: string; title: string; venues: { name: string } | null }
  >;
  let found = 0;

  for (const event of rows) {
    const venueName = event.venues?.name ?? "";
    const query = `${event.title} ${venueName} München Tickets`;

    let topResultUrl: string | null = null;
    let searchFailed = false;

    if (geminiApiKey) {
      const groundedResults = await searchViaGeminiGrounding(
        geminiApiKey,
        query,
      );
      if (groundedResults === null) searchFailed = true;
      else if (groundedResults.length > 0) {
        topResultUrl = groundedResults[0].url;
      }
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
      await supabase.from("events").update({ last_image_search_note: note }).eq(
        "id",
        event.id,
      );
      continue;
    }
    await supabase.from("events").update({ website_url: topResultUrl }).eq(
      "id",
      event.id,
    );
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
    return {
      found: 0,
      updated: 0,
      errors: [`events: Laden fehlgeschlagen — ${error.message}`],
    };
  }

  const missingImages = (events ?? []).filter(
    (e: { image_urls: string[] | null }) =>
      !e.image_urls || e.image_urls.length === 0,
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
            .update({
              last_image_search_note: "Keine Website-/Ticket-URL hinterlegt.",
            })
            .eq("id", event.id);
          continue;
        }

        let coverImage: string | null = null;
        let coverSourcePage: string | null = null;
        let coverCredits: string | null = null;
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
            notes.push(
              `${pageUrl} liefert kein nutzbares Bild (og:image/Hero/Content-Bereich geprüft)`,
            );
            continue;
          }
          const { reachable } = await checkImageUrl(candidate);
          if (!reachable) {
            notes.push(`Bild von ${pageUrl} nicht erreichbar/ungültig`);
            continue;
          }
          if (
            await isUrlUsedElsewhere(supabase, candidate, "events", event.id)
          ) {
            notes.push(
              `Bild von ${pageUrl} bereits einem anderen Event zugeordnet (Duplikat)`,
            );
            continue;
          }
          coverImage = candidate;
          coverSourcePage = pageUrl;
          coverCredits = detected?.credits ?? null;
          break;
        }
        if (!coverImage) {
          await supabase
            .from("events")
            .update({
              last_image_search_note: notes.join("; ") || "Kein Bild gefunden.",
            })
            .eq("id", event.id);
          continue;
        }

        // Zentral über `images` speichern, nicht nur als nackte URL im
        // Event. So bleiben Quellseite, Anbieter, Original-URL, Credits,
        // Lizenzstatus und Abrufzeit bei JEDEM automatischen Eventbild
        // dauerhaft nachvollziehbar.
        const stored = await persistCandidate(supabase, { table: "events", originType: "event" }, event.id, {
          imageUrl: coverImage,
          sourcePageUrl: coverSourcePage!,
          sourceName: new URL(coverSourcePage!).hostname,
          photographer: coverCredits,
          licenseStatus: coverCredits ? "official_press_image" : "permission_required",
          confidenceScore: 0.94,
          matchReason: "Titel-/Hero-Bild der konkreten Veranstaltungsseite.",
          warnings: coverCredits ? [] : ["Bildcredit und Nutzungserlaubnis vor Veröffentlichung prüfen."],
          needsReview: !coverCredits,
        });
        if (!stored) {
          errors.push(`event ${event.id}: Bild oder Quellenmetadaten konnten nicht zentral gespeichert werden`);
          continue;
        }

        const now = new Date().toISOString();
        const { error: updateError } = await supabase
          .from("events")
          .update({
            image_urls: [stored.publicUrl],
            primary_image_id: stored.imageId,
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
        errors.push(
          `event ${event.id}: ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
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
