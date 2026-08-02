// Phase 7 der Datenanreicherung (Nutzeranfrage: "erstelle im Redaktions-
// Dashboard eine Datenqualitätsansicht: pro Entität fehlende Felder, letzte
// Aktualisierung, Quellenlage und Vertrauensbewertung. Priorisiere zuerst
// alle Einträge, die in den nächsten 90 Tagen stattfinden."). Beschränkt
// sich bewusst auf Venues/Personen/Ensembles/Werke, die tatsächlich an
// einer Veranstaltung in den nächsten 90 Tagen beteiligt sind — die
// Felder, die die Enrichment-Pipelines dieser Sitzung befüllen
// (enrich-venue-details/enrich-person-profile/enrich-ensemble-profile/
// enrich-work-profile), nicht die von Anfang an vorhandenen Excel-
// Stammdaten (Adresse, Geburtsdatum etc.) — die Ansicht soll zeigen, wo
// die NEUE Anreicherung noch fehlt, nicht jede denkbare Datenlücke.
import { createClient } from "@/lib/supabase/server";
import { computeQualityScore, type QualityBreakdown, type QualityConfidence } from "./quality-score";

const HORIZON_DAYS = 90;

const VENUE_FIELDS = [
  "history_de",
  "district",
  "venue_type",
  "phone",
  "email",
  "arrival_info_de",
  "doors_info_de",
  "catering_info_de",
] as const;
const PERSON_FIELDS = ["biography_de", "education_career_de", "current_roles_de"] as const;
const ENSEMBLE_FIELDS = ["description_de", "leadership_de", "residency_de", "repertoire_de"] as const;
const WORK_FIELDS = ["instrumentation", "alternative_titles", "movements", "genre", "description_de"] as const;

// Abschnitt 8: kritische Felder stärker gewichten als optionale — hier
// bewusst als Teilmenge der obigen *_FIELDS-Arrays statt eigener Listen, um
// die Ansichten nicht auseinanderlaufen zu lassen. Auswahl nach fachlicher
// Relevanz für die Redaktion: ein fehlender Beschreibungstext wiegt schwerer
// als eine fehlende Telefonnummer.
const VENUE_CRITICAL_FIELDS = ["history_de", "district", "venue_type"] as const;
const PERSON_CRITICAL_FIELDS = ["biography_de"] as const;
const ENSEMBLE_CRITICAL_FIELDS = ["description_de"] as const;
const WORK_CRITICAL_FIELDS = ["description_de", "genre"] as const;

export interface CompletenessRow {
  entityType: "venue" | "person" | "ensemble" | "work";
  id: string;
  name: string;
  /** null, wenn es dafür (noch) keine eigene Admin-Seite gibt (aktuell:
   * Werke — es existiert keine /works-Verwaltungsseite). */
  editHref: string | null;
  missingFields: string[];
  totalFields: number;
  profileCheckedAt: string | null;
  sourceCount: number;
  confidenceLabel: string | null;
  nextEventStart: string;
  quality: QualityBreakdown;
}

function isEmpty(value: unknown): boolean {
  if (value == null) return true;
  if (typeof value === "string") return value.trim() === "";
  if (Array.isArray(value)) return value.length === 0;
  return false;
}

/** Liefert die Datenqualitätsübersicht für alle Venues/Personen/Ensembles/
 * Werke mit mindestens einer Veranstaltung in den nächsten 90 Tagen,
 * sortiert nach dem nächsten Veranstaltungstermin (dringlichste zuerst). */
export async function fetchCompletenessRows(): Promise<{ rows: CompletenessRow[]; error: string | null }> {
  const supabase = await createClient();
  const now = new Date();
  const horizon = new Date(now.getTime() + HORIZON_DAYS * 24 * 60 * 60 * 1000);

  const { data: events, error: eventsError } = await supabase
    .from("events")
    .select(
      "id, start_datetime, venue_id, event_participants(person_id, ensemble_id), event_works(work_id)",
    )
    .in("status", ["scheduled", "sold_out", "postponed"])
    .gte("start_datetime", now.toISOString())
    .lte("start_datetime", horizon.toISOString());

  if (eventsError) {
    return { rows: [], error: eventsError.message };
  }

  // Frühester bevorstehender Termin pro Entität — bestimmt die
  // Priorisierung ("zuerst alle Einträge, die in den nächsten 90 Tagen
  // stattfinden", dringlichste zuerst).
  const nextEventFor = new Map<string, string>();
  const noteEvent = (key: string, start: string) => {
    const existing = nextEventFor.get(key);
    if (!existing || start < existing) nextEventFor.set(key, start);
  };

  const venueIds = new Set<string>();
  const personIds = new Set<string>();
  const ensembleIds = new Set<string>();
  const workIds = new Set<string>();

  for (const e of events ?? []) {
    const start = e.start_datetime as string;
    if (e.venue_id) {
      venueIds.add(e.venue_id as string);
      noteEvent(`venue:${e.venue_id}`, start);
    }
    for (const p of (e.event_participants as { person_id: string | null; ensemble_id: string | null }[]) ?? []) {
      if (p.person_id) {
        personIds.add(p.person_id);
        noteEvent(`person:${p.person_id}`, start);
      }
      if (p.ensemble_id) {
        ensembleIds.add(p.ensemble_id);
        noteEvent(`ensemble:${p.ensemble_id}`, start);
      }
    }
    for (const w of (e.event_works as { work_id: string | null }[]) ?? []) {
      if (w.work_id) {
        workIds.add(w.work_id);
        noteEvent(`work:${w.work_id}`, start);
      }
    }
  }

  // Supabase-js parst den .select()-String zur Typ-Prüfzeit als Literal —
  // eine Template-Interpolation der FIELDS-Arrays (statt eines
  // ausgeschriebenen Literals) lässt sich dadurch nicht typisieren
  // (ParserError). Deshalb hier ausgeschrieben statt aus VENUE_FIELDS etc.
  // zusammengesetzt; die "as const"-Arrays bleiben die Instanz der
  // Wahrheit für isEmpty()/missingFields unten, hier nur redundant, aber
  // bewusst synchron zu halten.
  const [venues, persons, ensembles, works, provenance, images, personDuplicates, workDuplicates] = await Promise.all([
    venueIds.size
      ? supabase
        .from("venues")
        .select("id, name, profile_checked_at, history_de, district, venue_type, phone, email, arrival_info_de, doors_info_de, catering_info_de")
        .in("id", [...venueIds])
      : Promise.resolve({ data: [], error: null }),
    personIds.size
      ? supabase
        .from("persons")
        .select("id, full_name, profile_checked_at, biography_de, education_career_de, current_roles_de")
        .in("id", [...personIds])
      : Promise.resolve({ data: [], error: null }),
    ensembleIds.size
      ? supabase
        .from("ensembles")
        .select("id, name, profile_checked_at, description_de, leadership_de, residency_de, repertoire_de")
        .in("id", [...ensembleIds])
      : Promise.resolve({ data: [], error: null }),
    workIds.size
      ? supabase
        .from("works")
        .select("id, title, profile_checked_at, instrumentation, alternative_titles, movements, genre, description_de")
        .in("id", [...workIds])
      : Promise.resolve({ data: [], error: null }),
    // field_provenance über alle vier Entitätstypen auf einmal, dann in JS
    // nach entity_id gruppiert — vier separate .in()-Filter wären hier
    // unnötig komplex, die Tabelle ist klein genug für einen Gesamtabruf
    // pro Lauf.
    supabase
      .from("field_provenance")
      .select("entity_type, entity_id, confidence, retrieved_at")
      .in("entity_type", ["venue", "person", "ensemble", "work"])
      .in("entity_id", [...venueIds, ...personIds, ...ensembleIds, ...workIds]),
    // Für den Bild-Teilscore (Abschnitt 8) — works haben keine eigenen
    // Bilder, deshalb hier bewusst nur venue/person/ensemble.
    supabase
      .from("images")
      .select("origin_type, origin_id, license_status, needs_review")
      .in("origin_type", ["venue", "person", "ensemble"])
      .in("origin_id", [...venueIds, ...personIds, ...ensembleIds]),
    // Match-Sicherheit (Abschnitt 8/E) — nur für Personen/Werke existiert
    // aktuell eine Dedup-Review-Queue; Venues/Ensembles folgen erst mit den
    // neuen Tabellen in dieser Sitzung (siehe duplicates-Sektion). Ungefiltert
    // abgerufen (wie field_provenance oben) statt einer .or()-Kette über
    // potenziell viele IDs — die Review-Queue ist klein genug dafür.
    supabase.from("person_duplicate_candidates").select("person_a_id, person_b_id").eq("status", "pending"),
    supabase.from("work_duplicate_candidates").select("work_a_id, work_b_id").eq("status", "pending"),
  ]);

  const provenanceByEntity = new Map<string, { count: number; confidences: QualityConfidence[]; latest: string | null }>();
  for (const row of provenance.data ?? []) {
    const key = `${row.entity_type}:${row.entity_id}`;
    const entry = provenanceByEntity.get(key) ?? { count: 0, confidences: [], latest: null };
    entry.count++;
    if (row.confidence) entry.confidences.push(row.confidence as QualityConfidence);
    if (!entry.latest || (row.retrieved_at && row.retrieved_at > entry.latest)) entry.latest = row.retrieved_at;
    provenanceByEntity.set(key, entry);
  }

  const imagesByEntity = new Map<string, { hasNonRejectedImage: boolean; anyNeedsReview: boolean; anyLicenseConfirmed: boolean }>();
  for (const row of images.data ?? []) {
    const key = `${row.origin_type}:${row.origin_id}`;
    const entry = imagesByEntity.get(key) ?? { hasNonRejectedImage: false, anyNeedsReview: false, anyLicenseConfirmed: false };
    if (row.license_status !== "rejected") entry.hasNonRejectedImage = true;
    if (row.needs_review) entry.anyNeedsReview = true;
    if (row.license_status === "confirmed_free" || row.license_status === "confirmed_licensed") entry.anyLicenseConfirmed = true;
    imagesByEntity.set(key, entry);
  }

  const pendingPersonDuplicateIds = new Set<string>();
  for (const row of personDuplicates.data ?? []) {
    if (row.person_a_id) pendingPersonDuplicateIds.add(row.person_a_id as string);
    if (row.person_b_id) pendingPersonDuplicateIds.add(row.person_b_id as string);
  }
  const pendingWorkDuplicateIds = new Set<string>();
  for (const row of workDuplicates.data ?? []) {
    if (row.work_a_id) pendingWorkDuplicateIds.add(row.work_a_id as string);
    if (row.work_b_id) pendingWorkDuplicateIds.add(row.work_b_id as string);
  }

  const rows: CompletenessRow[] = [];

  function addRows<T extends Record<string, unknown>>(
    entityType: CompletenessRow["entityType"],
    items: T[],
    fields: readonly string[],
    criticalFields: readonly string[],
    nameOf: (item: T) => string,
    editHrefOf: (item: T) => string | null,
    options: { hasImages: boolean; duplicateIds: Set<string> | null },
  ) {
    for (const item of items) {
      const id = item.id as string;
      const missingFields = fields.filter((f) => isEmpty(item[f]));
      const key = `${entityType}:${id}`;
      const prov = provenanceByEntity.get(key);
      const profileCheckedAt = (item.profile_checked_at as string | null) ?? null;

      const criticalPresent = criticalFields.filter((f) => !isEmpty(item[f])).length;
      const optionalTotal = fields.length - criticalFields.length;
      const optionalPresent = fields.filter((f) => !criticalFields.includes(f) && !isEmpty(item[f])).length;

      const quality = computeQualityScore({
        fields: {
          criticalPresent,
          criticalTotal: criticalFields.length,
          optionalPresent,
          optionalTotal,
        },
        provenanceConfidences: prov?.confidences ?? [],
        profileCheckedAt,
        images: options.hasImages
          ? imagesByEntity.get(`${entityType}:${id}`) ?? { hasNonRejectedImage: false, anyNeedsReview: false, anyLicenseConfirmed: false }
          : null,
        hasPendingDuplicateCandidate: options.duplicateIds ? options.duplicateIds.has(id) : null,
      });

      rows.push({
        entityType,
        id,
        name: nameOf(item),
        editHref: editHrefOf(item),
        missingFields,
        totalFields: fields.length,
        profileCheckedAt,
        sourceCount: prov?.count ?? 0,
        confidenceLabel: prov ? [...new Set(prov.confidences)].join(", ") : null,
        nextEventStart: nextEventFor.get(key) ?? horizon.toISOString(),
        quality,
      });
    }
  }

  addRows(
    "venue",
    venues.data ?? [],
    VENUE_FIELDS,
    VENUE_CRITICAL_FIELDS,
    (v) => v.name as string,
    (v) => `/venues/${v.id}`,
    { hasImages: true, duplicateIds: null },
  );
  addRows(
    "person",
    persons.data ?? [],
    PERSON_FIELDS,
    PERSON_CRITICAL_FIELDS,
    (p) => p.full_name as string,
    (p) => `/persons/${p.id}`,
    { hasImages: true, duplicateIds: pendingPersonDuplicateIds },
  );
  addRows(
    "ensemble",
    ensembles.data ?? [],
    ENSEMBLE_FIELDS,
    ENSEMBLE_CRITICAL_FIELDS,
    (e) => e.name as string,
    (e) => `/ensembles/${e.id}`,
    { hasImages: true, duplicateIds: null },
  );
  addRows(
    "work",
    works.data ?? [],
    WORK_FIELDS,
    WORK_CRITICAL_FIELDS,
    (w) => w.title as string,
    () => null,
    { hasImages: false, duplicateIds: pendingWorkDuplicateIds },
  );

  rows.sort((a, b) => a.nextEventStart.localeCompare(b.nextEventStart));

  return { rows, error: null };
}
