// Schreiblogik für den Ingestion-Worker: pro RawEvent entscheiden, ob es
// ein bereits bekanntes Event ist (exaktes (source_id, external_id)-Match
// oder Fuzzy-Match via matching.ts), aktualisiert werden muss, ein
// Duplicate-Candidate ist, oder komplett neu angelegt wird. Siehe
// docs/06-mvp-plan.md "Ingestion-Pipeline (Basis)" für den Gesamtkontext.

import { findEventMatch, resolveVenue } from "./matching.ts";
import type { RawEvent } from "./types.ts";
import { detectEventCoverImage } from "../_shared/coverImageDetection.ts";
import { ensureCoverImage } from "../_shared/imagePipeline.ts";

interface SourceRow {
  id: string;
  type?: string;
  venue_id: string | null;
  organizer_id?: string | null;
  person_id?: string | null;
  ensemble_id?: string | null;
  consecutive_failures?: number | null;
  confidence_thresholds?: { auto?: number; quick?: number } | null;
}

/** Ordnet den Score einer Triage-Stufe zu, mit den PRO QUELLE kalibrierten
 * Schwellwerten (sources.confidence_thresholds, Architektur-Dokument
 * Abschnitt 0/4/2.2) statt eines global fixen Cutoffs. review_status ist
 * weiterhin rein redaktionelle Metadaten für die Review-Queue-Triage und
 * hat KEINEN Effekt auf Sichtbarkeit — das bleibt allein status/RLS
 * (siehe 20260819000004_events_import_confidence.sql). */
function reviewStatusForScore(
  score: number,
  thresholds: SourceRow["confidence_thresholds"],
): "auto_published" | "needs_quick_check" | "needs_review" {
  const auto = thresholds?.auto ?? 0.95;
  const quick = thresholds?.quick ?? 0.85;
  if (score >= auto) return "auto_published";
  if (score >= quick) return "needs_quick_check";
  return "needs_review";
}

// Structured feed types haben eine strukturell niedrigere Fehlerquote als
// freies HTML-Scraping mit KI-Extraktion — siehe Architektur-Dokument
// Abschnitt 4 ("extraktions_methode").
const STRUCTURED_SOURCE_TYPES = new Set(["schema_org", "rss", "ical", "api"]);

/** Grobe Erstversion der Confidence-Score-Formel aus dem Architektur-
 * Dokument (Abschnitt 4) — NUR für neu angelegte Events berechnet.
 * review_status wird daraus über die pro Quelle kalibrierten Schwellwerte
 * (sources.confidence_thresholds, siehe reviewStatusForScore()) triagiert,
 * hat aber weiterhin KEINEN Effekt auf Sichtbarkeit: status bleibt immer
 * 'draft' für neue Events, unabhängig vom Score — das bestehende, bereits
 * produktiv laufende "alles landet als draft, Redaktion prüft"-Verhalten
 * ändert sich dadurch nicht. review_status ist reine Triage-Metadaten für
 * die Review-Queue (Quick-Check vs. Vollprüfung).
 *
 * Vereinfachungen gegenüber der vollen Formel im Dokument:
 *  - "entity_resolution_confidence" bewertet hier nur die Venue-Auflösung
 *    (fest über sources.venue_id vs. Fuzzy-Match) — Personen/Ensembles
 *    fließen noch nicht ein (die laufen ohnehin über die separate
 *    entity_candidates-Pipeline in enrich-event-references).
 *  - "quelle_zuverlässigkeit_historisch" nutzt sources.consecutive_failures
 *    als Proxy statt einer echten Erfolgsquote über alle bisherigen Runs
 *    (dafür fehlt aktuell eine aggregierte Statistik-Spalte/View). */
function computeConfidenceScore(
  raw: RawEvent,
  source: SourceRow,
  venueResolvedViaFixedId: boolean,
): number {
  const sourceReliability = Math.max(0, 1 - (source.consecutive_failures ?? 0) * 0.15);

  const optionalFields = [raw.description, raw.priceMin, raw.priceMax, raw.imageUrl, raw.venueAddress];
  const fieldCompleteness = optionalFields.filter((f) => f !== null && f !== undefined).length / optionalFields.length;

  const entityResolutionConfidence = venueResolvedViaFixedId ? 1.0 : 0.65;

  const extractionMethod = source.type && STRUCTURED_SOURCE_TYPES.has(source.type)
    ? 1.0
    : source.type === "manual"
    ? 0.9
    : 0.6; // "scrape" (HTML + KI-Extraktion)

  const startsInFuture = new Date(raw.startDateTime).getTime() > Date.now();
  const plausibility = startsInFuture ? 1.0 : 0.3;

  const score = 0.30 * sourceReliability
    + 0.25 * fieldCompleteness
    + 0.20 * entityResolutionConfidence
    + 0.15 * extractionMethod
    + 0.10 * plausibility;

  return Math.round(score * 100) / 100;
}

// eventId is present on every non-error outcome — index.ts uses it to track
// which events a source's current run actually saw, so it can flag events
// belonging to that source that went missing (see the cancellation-sweep
// in index.ts / cancellation_candidates, 20260815000003).
export type WriteOutcome =
  | { outcome: "unchanged"; eventId: string }
  | { outcome: "updated"; eventId: string }
  | { outcome: "created"; eventId: string }
  | { outcome: "flagged"; eventId: string }
  | { outcome: "error"; error: string };

const HTML_ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  hellip: "…",
  mdash: "—",
  ndash: "–",
};

/** Deno hat keine eingebaute HTML-Entity-Dekodierung außerhalb eines
 * DOM-Parsers — für JSON-Quellen (kein DOM im Spiel) reicht das kleine,
 * in klassischen Konzerttiteln vorkommende Set (siehe Aufrufer-Kommentar). */
function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&([a-z]+);/gi, (match, name) => HTML_ENTITIES[name.toLowerCase()] ?? match);
}

/** Siehe Kommentar bei upsertRawEvent — stellt dem Titel den Ensemble-Namen
 * voran, wenn er nicht schon selbst darin vorkommt. Best-effort: schlägt
 * das Nachladen des Ensemble-Namens fehl, bleibt der Titel unangetastet
 * statt den ganzen Ingestion-Lauf für dieses Event scheitern zu lassen. */
async function withEnsemblePrefix(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  ensembleId: string,
  title: string,
): Promise<string> {
  const { data: ensemble } = await supabase
    .from("ensembles")
    .select("name")
    .eq("id", ensembleId)
    .maybeSingle();
  const name: string | undefined = ensemble?.name;
  if (!name || title.toLowerCase().includes(name.toLowerCase())) return title;
  return `${name}: ${title}`;
}

const DIFFABLE_FIELDS = [
  "title",
  "description_de",
  "start_datetime",
  "end_datetime",
  "price_min",
  "price_max",
  "is_free",
  "website_url",
  "image_urls",
] as const;

/**
 * Per-RawEvent decision tree:
 *  1. Resolve venue (source.venue_id, or fuzzy find_matching_venue()).
 *  2. Exact match on (source_id, external_id) if raw.externalId is set —
 *     authoritative, idempotent re-ingestion of the SAME source.
 *  3. Otherwise fuzzy title+venue+time match — catches the SAME real-world
 *     event reported by a DIFFERENT source (or one with no external id).
 *     High confidence (>=0.7) updates in place; moderate confidence
 *     (0.35-0.7) creates a draft and flags it for admin review instead of
 *     silently merging or silently duplicating.
 *  4. No match at all -> brand-new draft event.
 * Never throws — every failure mode returns {outcome: 'error', error}.
 */
export async function upsertRawEvent(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  source: SourceRow,
  rawInRaw: RawEvent,
): Promise<WriteOutcome> {
  try {
    // JSON-basierte Quellen (brso.ts, bayerncloud.ts) liefern Titel/
    // Beschreibung manchmal HTML-entity-kodiert statt Klartext (live
    // beobachtet: "Daniel Harding &amp; Seong-Jin Cho" statt "&") — anders
    // als DOM-basierte Scrape-Quellen (scrape.ts), deren textContent das
    // schon automatisch dekodiert. Zentral hier statt in jedem Parser
    // einzeln, damit kein zukünftiger JSON-Parser dieselbe Lücke wiederholt.
    const rawIn: RawEvent = {
      ...rawInRaw,
      title: decodeHtmlEntities(rawInRaw.title),
      description: rawInRaw.description ? decodeHtmlEntities(rawInRaw.description) : rawInRaw.description,
    };

    // Manche Quellen liefern als "Titel" nur eine Komponisten-Liste (z.B.
    // mphil.de's ".m-mphil-concertlist__headline" — "Ravel Bernstein
    // Strawinsky" statt eines echten Konzerttitels). Auf der Marken-Website
    // der Quelle ist das im Kontext klar, in der App ohne Ensemble-Namen
    // missverständlich (Nutzerfeedback: "Mozart von Weber" wirkt wie ein
    // (fiktiver) Personenname). Nur für Quellen mit fest hinterlegtem
    // Ensemble (sources.ensemble_id) und nur, wenn der Titel den Namen
    // nicht schon selbst enthält — sonst bliebe z.B. "BRSO: BRSO spielt..."
    // stehen.
    const raw = source.ensemble_id
      ? { ...rawIn, title: await withEnsemblePrefix(supabase, source.ensemble_id, rawIn.title) }
      : rawIn;

    const venueResult = await resolveVenue(supabase, source, raw);
    if ("error" in venueResult) {
      return { outcome: "error", error: venueResult.error };
    }
    const venueId = venueResult.venueId;

    const contentHash = await computeContentHash(raw);
    const nowIso = new Date().toISOString();

    if (raw.externalId) {
      const { data: existing, error } = await supabase
        .from("events")
        .select(
          "id, title, description_de, start_datetime, end_datetime, price_min, price_max, is_free, website_url, image_urls, content_hash, primary_image_id",
        )
        .eq("source_id", source.id)
        .eq("external_id", raw.externalId)
        .maybeSingle();

      if (error) {
        return { outcome: "error", error: `lookup by external_id failed: ${error.message}` };
      }

      if (existing) {
        if (existing.content_hash === contentHash) {
          const { error: touchError } = await supabase
            .from("events")
            .update({ last_verified_at: nowIso, last_seen_at: nowIso })
            .eq("id", existing.id);
          if (touchError) {
            return { outcome: "error", error: `failed to refresh last_verified_at: ${touchError.message}` };
          }
          await linkSourceEntity(supabase, source, existing.id);
          return { outcome: "unchanged", eventId: existing.id };
        }
        // Same source re-reporting the same external_id — authoritative,
        // always trust its image.
        const outcome = await applyUpdate(supabase, existing, raw, contentHash, nowIso, source, venueId, true);
        if (outcome.outcome !== "error") await linkSourceEntity(supabase, source, outcome.eventId);
        return outcome;
      }
      // No row for this (source_id, external_id) yet — first time this
      // source has reported it. Still worth a fuzzy check: it may already
      // be tracked from a DIFFERENT source (or manually, with no source_id
      // at all) before we fall back to creating a brand-new event.
    }

    const match = await findEventMatch(supabase, raw.title, venueId, raw.startDateTime, raw.castNames);

    if (match && match.similarity >= 0.7) {
      const { data: existing, error } = await supabase
        .from("events")
        .select(
          "id, title, description_de, start_datetime, end_datetime, price_min, price_max, is_free, website_url, image_urls, content_hash, primary_image_id",
        )
        .eq("id", match.id)
        .maybeSingle();

      if (error || !existing) {
        return {
          outcome: "error",
          error: `failed to load matched event ${match.id}: ${error?.message ?? "not found"}`,
        };
      }

      // Cross-source fuzzy match (title/time/venue similarity, not a real
      // identifier) — trusted enough to update text fields, but NOT to
      // blindly accept a photo: a wrong match here previously stuck a
      // mismatched image on the event permanently (image_urls is
      // append-only, the app always shows image_urls[0]). Only fill the
      // gap when the event has no photo yet; never overwrite/append one
      // that's already there from a possibly-different, already-verified
      // match.
      const outcome = await applyUpdate(supabase, existing, raw, contentHash, nowIso, source, venueId, false);
      if (outcome.outcome !== "error") {
        // Backfill so future runs of THIS source hit the fast exact-match
        // path above. Guarded on source_id being null so we never steal
        // ownership from a different source that's already tracking it.
        await supabase
          .from("events")
          .update({ source_id: source.id, external_id: raw.externalId })
          .eq("id", existing.id)
          .is("source_id", null);
        await linkSourceEntity(supabase, source, existing.id);
      }
      return outcome;
    }

    const slug = await generateUniqueSlug(supabase, raw.title);
    const importConfidence = computeConfidenceScore(raw, source, venueResult.viaFixedSourceVenue);
    const reviewStatus = reviewStatusForScore(importConfidence, source.confidence_thresholds);
    const { data: created, error: createError } = await supabase
      .from("events")
      .insert({
        slug,
        title: raw.title,
        description_de: raw.description,
        start_datetime: raw.startDateTime,
        end_datetime: raw.endDateTime,
        venue_id: venueId,
        price_min: raw.priceMin,
        price_max: raw.priceMax,
        is_free: raw.isFree ?? false,
        website_url: raw.url,
        image_urls: raw.imageUrl ? [raw.imageUrl] : [],
        status: "draft",
        source_id: source.id,
        external_id: raw.externalId,
        content_hash: contentHash,
        last_verified_at: nowIso,
        last_seen_at: nowIso,
        attribution_notice: raw.attributionNotice ?? null,
        attribution_license_url: raw.attributionLicenseUrl ?? null,
        import_confidence: importConfidence,
        review_status: reviewStatus,
      })
      .select("id")
      .single();

    if (createError || !created) {
      return { outcome: "error", error: `failed to create event: ${createError?.message ?? "unknown"}` };
    }

    await linkSourceEntity(supabase, source, created.id);
    await attachCoverImage(supabase, source, raw, created.id, venueId, null, true);

    if (match) {
      const { error: dupError } = await supabase.from("duplicate_candidates").insert({
        event_a_id: match.id,
        event_b_id: created.id,
        similarity_score: match.similarity,
        status: "pending",
      });
      if (dupError) {
        return {
          outcome: "error",
          error: `created event ${created.id} but failed to flag as duplicate candidate: ${dupError.message}`,
        };
      }
      return { outcome: "flagged", eventId: created.id };
    }

    return { outcome: "created", eventId: created.id };
  } catch (err) {
    return { outcome: "error", error: err instanceof Error ? err.message : String(err) };
  }
}

async function applyUpdate(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  // deno-lint-ignore no-explicit-any
  existing: Record<string, any>,
  raw: RawEvent,
  contentHash: string,
  nowIso: string,
  source: SourceRow,
  venueId: string | null,
  trustImage: boolean,
): Promise<WriteOutcome> {
  const updates = buildUpdatePayload(raw);

  if (raw.imageUrl) {
    const currentImages: string[] = Array.isArray(existing.image_urls) ? existing.image_urls : [];
    if (trustImage) {
      if (!currentImages.includes(raw.imageUrl)) {
        updates.image_urls = [...currentImages, raw.imageUrl];
      }
    } else if (currentImages.length === 0) {
      // Fuzzy-matched source and the event has no photo at all yet —
      // safe to fill the gap, nothing to accidentally overwrite.
      updates.image_urls = [raw.imageUrl];
    }
  }

  const { changedFields, oldValues, newValues } = diffFields(existing, updates);

  const { error: updateError } = await supabase
    .from("events")
    .update({ ...updates, content_hash: contentHash, last_verified_at: nowIso, last_seen_at: nowIso })
    .eq("id", existing.id);

  if (updateError) {
    return { outcome: "error", error: `failed to update event ${existing.id}: ${updateError.message}` };
  }

  if (changedFields.length > 0) {
    const { error: logError } = await supabase.from("event_change_log").insert({
      event_id: existing.id,
      changed_fields: changedFields,
      old_values: oldValues,
      new_values: newValues,
      changed_by: `ingestion:${source.id}`,
    });
    if (logError) {
      // The event itself was already updated successfully — a failed audit
      // log write shouldn't be reported as an outcome error (nothing about
      // the event data is wrong), just surfaced for visibility.
      console.error(`event ${existing.id} updated but change-log insert failed: ${logError.message}`);
    }
  }

  await attachCoverImage(supabase, source, raw, existing.id, venueId, existing.primary_image_id ?? null, trustImage);

  return { outcome: "updated", eventId: existing.id };
}

/** Ordnet einem Event nach Möglichkeit ein Coverbild zu (Architektur-Auftrag
 * "Event-Importer: automatische Bilderkennung") — läuft nach jedem
 * Event-Write (create/update), best-effort: ein Fehlschlag hier lässt den
 * eigentlichen Event-Write nie scheitern (siehe try/catch unten, genau wie
 * beim bisherigen recordImage()).
 *
 * Ablauf:
 *  1. raw.imageUrl, falls die Quelle selbst eins liefert (schema_org/brso/
 *     bayerncloud/scrape-mit-Bildselektor) — bereits "erkannt", keine
 *     erneute Seiten-Analyse nötig. Das ist die einzige "authoritative"
 *     Quelle im Sinne von trustImage/mayOverwrite unten.
 *  2. Sonst, falls raw.url gesetzt ist: Prioritätskaskade auf der
 *     Event-Seite selbst (coverImageDetection.ts: schema.org -> og:image ->
 *     twitter:image -> Hero -> Event-Container).
 *  3. Für 1./2. gefundene URL: Download+WebP+Thumbnail+pHash-Dedupe+Storage
 *     (imagePipeline.ts). Bei Erfolg -> primary_image_id gesetzt. Bei
 *     Fehlschlag (nicht erreichbar/Decode-Fehler): Verhalten von vor dieser
 *     Erweiterung erhalten, mindestens die URL für die redaktionelle
 *     Lizenz-Review-Queue festhalten (recordImage()).
 *  4. Kein Bild gefunden/gespeichert: Fallback auf Ensemble-/Künstler-/
 *     Venue-Foto (resolveFallbackImage()).
 *
 * Überschreibt ein schon vorhandenes primary_image_id nur, wenn raw.imageUrl
 * authoritativ UND trustImage true ist (exakter external_id-Match) — exakt
 * dieselbe Vertrauens-Abstufung wie image_urls[] oben in applyUpdate(): ein
 * bloß fuzzy-gematchtes oder nur von der Seite abgeleitetes Bild darf immer
 * nur eine Lücke füllen, nie ein bestehendes Coverbild verdrängen. Ändert
 * NIE image_urls[] selbst — das bleibt exakt das bisherige, von der App
 * gelesene Verhalten (primary_image_id ist ein rein additives, noch nicht
 * von der App gelesenes Feld, siehe 20260819000003_images_and_tags.sql). */
async function attachCoverImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  source: SourceRow,
  raw: RawEvent,
  eventId: string,
  venueId: string | null,
  currentPrimaryImageId: string | null,
  trustImage: boolean,
): Promise<void> {
  try {
    const authoritative = raw.imageUrl != null;
    let detected: { url: string; credits: string | null } | null = authoritative
      ? { url: raw.imageUrl as string, credits: null }
      : null;

    if (!detected && raw.url) {
      const found = await detectEventCoverImage(raw.url);
      if (found) detected = { url: found.url, credits: found.credits };
    }

    const mayOverwrite = authoritative && trustImage;

    let imageId: string | null = null;
    if (detected && (mayOverwrite || !currentPrimaryImageId)) {
      imageId = await ensureCoverImage(supabase, {
        sourceUrl: detected.url,
        originType: "event",
        originId: eventId,
        credits: detected.credits,
      });
      if (!imageId) {
        await recordImage(supabase, "event", eventId, detected.url);
      }
    }

    if (!imageId && !currentPrimaryImageId) {
      imageId = await resolveFallbackImage(supabase, source, eventId, venueId);
    }

    if (imageId && imageId !== currentPrimaryImageId) {
      const { error } = await supabase.from("events").update({ primary_image_id: imageId }).eq("id", eventId);
      if (error) {
        console.error(`attachCoverImage: failed to set primary_image_id for event ${eventId}: ${error.message}`);
      }
    }
  } catch (err) {
    console.error(`attachCoverImage failed for event ${eventId}: ${err instanceof Error ? err.message : String(err)}`);
  }
}

/** Fallback-Kaskade aus dem Architektur-Auftrag, wenn kein Veranstaltungsbild
 * gefunden/gespeichert werden konnte: 1. Ensemble  2. Künstler/Person
 * 3. Veranstaltungsort. Bevorzugt die feste Quellen-Bindung
 * (source.ensemble_id/person_id — dasselbe Signal wie linkSourceEntity()
 * oben), sonst die per event_participants verknüpften Entities, sonst die
 * Venue. Reuses ensureCoverImage() für die eigentliche Zeile: das Foto
 * gehört weiterhin der Entity (origin_type bleibt 'ensemble'/'person'/
 * 'venue'), das Event bekommt nur eine primary_image_id-Referenz darauf —
 * genau das "Bilder unabhängig vom Event speichern"-Prinzip des Auftrags. */
async function resolveFallbackImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  source: SourceRow,
  eventId: string,
  venueId: string | null,
): Promise<string | null> {
  let ensembleId = source.ensemble_id ?? null;
  let personId = source.person_id ?? null;

  if (!ensembleId && !personId) {
    const { data: ensembleParticipant } = await supabase
      .from("event_participants")
      .select("ensemble_id")
      .eq("event_id", eventId)
      .not("ensemble_id", "is", null)
      .limit(1)
      .maybeSingle();
    if (ensembleParticipant?.ensemble_id) ensembleId = ensembleParticipant.ensemble_id;
  }
  if (!ensembleId && !personId) {
    const { data: personParticipant } = await supabase
      .from("event_participants")
      .select("person_id")
      .eq("event_id", eventId)
      .not("person_id", "is", null)
      .limit(1)
      .maybeSingle();
    if (personParticipant?.person_id) personId = personParticipant.person_id;
  }

  if (ensembleId) {
    const id = await ensureEntityCoverImage(supabase, "ensemble", ensembleId);
    if (id) return id;
  }
  if (personId) {
    const id = await ensureEntityCoverImage(supabase, "person", personId);
    if (id) return id;
  }
  if (venueId) {
    const id = await ensureEntityCoverImage(supabase, "venue", venueId);
    if (id) return id;
  }
  return null;
}

async function ensureEntityCoverImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  originType: "ensemble" | "person" | "venue",
  originId: string,
): Promise<string | null> {
  const table = originType === "ensemble" ? "ensembles" : originType === "person" ? "persons" : "venues";
  const { data: entity } = await supabase.from(table).select("photo_url").eq("id", originId).maybeSingle();
  if (!entity?.photo_url) return null;
  return await ensureCoverImage(supabase, {
    sourceUrl: entity.photo_url,
    originType,
    originId,
    credits: null,
  });
}

/** Legt eine images-Zeile an (Architektur-Dokument Abschnitt 2.2/6:
 * Lizenz-Tracking, siehe 20260819000003_images_and_tags.sql) — parallel zu
 * events.image_urls[], das weiterhin unverändert die von der App
 * gelesene Quelle bleibt. license_status startet immer bei 'unknown' mit
 * needs_review=true: eine automatisch importierte Bild-URL gilt nie als
 * automatisch freigegeben, unabhängig vom Confidence Score der übrigen
 * Event-Daten. Idempotent (kein Duplikat bei erneutem Lauf derselben
 * source_url für denselben origin_id) und best-effort — ein Fehlschlag
 * hier lässt den eigentlichen Event-Write nicht scheitern. Dient jetzt als
 * Fallback von attachCoverImage(), wenn die Download-/Verarbeitungs-Pipeline
 * (imagePipeline.ts) scheitert — vorher der einzige Pfad. */
async function recordImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  originType: "event",
  originId: string,
  sourceUrl: string,
): Promise<void> {
  const { data: existingImage } = await supabase
    .from("images")
    .select("id")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .eq("source_url", sourceUrl)
    .maybeSingle();
  if (existingImage) return;

  const { error } = await supabase.from("images").insert({
    origin_type: originType,
    origin_id: originId,
    source_url: sourceUrl,
  });
  if (error) {
    console.error(`recordImage: failed to insert images row for ${originType} ${originId}: ${error.message}`);
  }
}

/** Verknüpft ein Event automatisch mit event_participants, wenn die Quelle
 * explizit an eine Person/ein Ensemble gebunden ist (sources.person_id/
 * ensemble_id, siehe 20260818000001_sources_person_ensemble.sql) — die
 * Quelle IST "die eigene Seite von X", ein vertrauenswürdigeres Signal als
 * eine LLM-Vermutung, deshalb hier direkt geschrieben statt über
 * entity_candidates/enrich-event-references zu laufen. Idempotent: prüft
 * vor dem Insert, ob die Verknüpfung schon existiert. Best-effort — ein
 * Fehlschlag hier lässt den eigentlichen Event-Write nicht scheitern,
 * genau wie beim event_change_log-Insert oben. */
async function linkSourceEntity(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  source: SourceRow,
  eventId: string,
): Promise<void> {
  if (!source.person_id && !source.ensemble_id) return;

  const filterColumn = source.person_id ? "person_id" : "ensemble_id";
  const filterValue = source.person_id ?? source.ensemble_id;

  const { data: existingLink } = await supabase
    .from("event_participants")
    .select("id")
    .eq("event_id", eventId)
    .eq(filterColumn, filterValue)
    .maybeSingle();
  if (existingLink) return;

  let role: string | null = null;
  if (source.person_id) {
    const { data: person } = await supabase
      .from("persons")
      .select("roles")
      .eq("id", source.person_id)
      .maybeSingle();
    const roles: string[] = person?.roles ?? [];
    role = roles[0] ?? "solist";
  }

  const { error } = await supabase.from("event_participants").insert({
    event_id: eventId,
    person_id: source.person_id ?? null,
    ensemble_id: source.ensemble_id ?? null,
    role,
  });
  if (error) {
    console.error(`linkSourceEntity: failed to link event ${eventId} to source entity: ${error.message}`);
  }
}

/** Only includes keys the source actually provided a non-null value for —
 * a source that doesn't know a field (e.g. RSS has no price) must never
 * overwrite a previously-known value from a richer source with null. */
function buildUpdatePayload(raw: RawEvent): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    title: raw.title,
    start_datetime: raw.startDateTime,
  };
  if (raw.description !== null) payload.description_de = raw.description;
  if (raw.endDateTime !== null) payload.end_datetime = raw.endDateTime;
  if (raw.priceMin !== null) payload.price_min = raw.priceMin;
  if (raw.priceMax !== null) payload.price_max = raw.priceMax;
  if (raw.isFree !== null) payload.is_free = raw.isFree;
  if (raw.url !== null) payload.website_url = raw.url;
  if (raw.attributionNotice != null) payload.attribution_notice = raw.attributionNotice;
  if (raw.attributionLicenseUrl != null) payload.attribution_license_url = raw.attributionLicenseUrl;
  return payload;
}

function diffFields(
  existing: Record<string, unknown>,
  updates: Record<string, unknown>,
): { changedFields: string[]; oldValues: Record<string, unknown>; newValues: Record<string, unknown> } {
  const changedFields: string[] = [];
  const oldValues: Record<string, unknown> = {};
  const newValues: Record<string, unknown> = {};

  for (const field of DIFFABLE_FIELDS) {
    if (!(field in updates)) continue;
    const oldVal = existing[field] ?? null;
    const newVal = updates[field] ?? null;
    if (!valuesEqual(oldVal, newVal)) {
      changedFields.push(field);
      oldValues[field] = oldVal;
      newValues[field] = newVal;
    }
  }

  return { changedFields, oldValues, newValues };
}

function valuesEqual(a: unknown, b: unknown): boolean {
  if (typeof a === "number" && typeof b === "number") {
    return Math.abs(a - b) < 0.001;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    return JSON.stringify(a) === JSON.stringify(b);
  }
  return a === b;
}

/** Deterministic SHA-256 over the mutable fields — unchanged hash means an
 * exact-match re-fetch is a no-op ping, not a real update. */
async function computeContentHash(raw: RawEvent): Promise<string> {
  const canonical = {
    title: raw.title,
    description: raw.description,
    startDateTime: raw.startDateTime,
    endDateTime: raw.endDateTime,
    priceMin: raw.priceMin,
    priceMax: raw.priceMax,
    isFree: raw.isFree,
    url: raw.url,
    imageUrl: raw.imageUrl,
  };
  const bytes = new TextEncoder().encode(JSON.stringify(canonical));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return toHex(digest);
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function slugify(title: string): string {
  const umlauts: Record<string, string> = {
    ä: "ae",
    ö: "oe",
    ü: "ue",
    ß: "ss",
    Ä: "ae",
    Ö: "oe",
    Ü: "ue",
  };
  let s = title;
  for (const [from, to] of Object.entries(umlauts)) {
    s = s.split(from).join(to);
  }
  s = s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "");
  return s || "veranstaltung";
}

async function generateUniqueSlug(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  title: string,
): Promise<string> {
  const base = slugify(title);
  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from("events").select("id").eq("slug", candidate).maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${Date.now()}`;
}
