import { ensureCoverImage } from "./imagePipeline.ts";

export interface WorkImageDonorMatch {
  donor_event_id: string;
  work_id: string;
  matched_entity_type: "person" | "ensemble";
  matched_entity_id: string;
  matched_venue: boolean;
  image_url: string;
}

/** Ruft die SQL-Funktion find_work_image_donor() auf (siehe
 * 20261013000003_work_image_reuse.sql) — dort liegt das eigentliche Matching
 * (gleiches Werk + gemeinsames Ensemble beliebiger Venue, oder gemeinsame
 * Person an derselben Venue), weil es mehrere Tabellen mit einem OR über
 * zwei unterschiedliche Bedingungen verknüpft; das ist in SQL deutlich
 * lesbarer als über mehrere supabase-js-Roundtrips nachgebaut. */
export async function findWorkImageDonor(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  eventId: string,
): Promise<WorkImageDonorMatch | null> {
  const { data, error } = await supabase.rpc("find_work_image_donor", { p_event_id: eventId });
  if (error) {
    console.error(`find_work_image_donor(${eventId}): ${error.message}`);
    return null;
  }
  const row = Array.isArray(data) && data.length > 0 ? data[0] : null;
  return row as WorkImageDonorMatch | null;
}

/** Wendet einen gefundenen Bild-Spender an: legt (falls nötig) eine
 * werk-gebundene images-Zeile an (origin_type "work" — dedupt automatisch
 * über ensureCoverImage() bei mehrfacher Anwendung für dasselbe Werk) und
 * protokolliert die Verknüpfung in event_image_reuse, damit sie in der
 * Admin-Übersicht (/work-image-reuse) nachvollziehbar und ablehnbar ist.
 * Gibt die images.id zurück, oder null bei Fehlschlag bzw. wenn genau diese
 * Event/Werk-Kombination bereits redaktionell abgelehnt wurde — eine
 * Ablehnung darf nicht beim nächsten Ingest-/Backfill-Lauf stillschweigend
 * erneut angewendet werden (gleiches Prinzip wie review_status=rejected bei
 * ensureCoverImage selbst). */
export async function applyWorkImageReuse(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  eventId: string,
  donor: WorkImageDonorMatch,
): Promise<string | null> {
  const { data: existingFlag } = await supabase
    .from("event_image_reuse")
    .select("status")
    .eq("event_id", eventId)
    .eq("work_id", donor.work_id)
    .maybeSingle();
  if (existingFlag?.status === "rejected") return null;

  const imageId = await ensureCoverImage(supabase, {
    sourceUrl: donor.image_url,
    originType: "work",
    originId: donor.work_id,
    credits: null,
  });
  if (!imageId) return null;

  const { error } = await supabase.from("event_image_reuse").upsert({
    event_id: eventId,
    donor_event_id: donor.donor_event_id,
    work_id: donor.work_id,
    matched_entity_type: donor.matched_entity_type,
    matched_entity_id: donor.matched_entity_id,
    matched_venue: donor.matched_venue,
    image_id: imageId,
    status: "active",
  }, { onConflict: "event_id,work_id" });
  if (error) {
    console.error(`applyWorkImageReuse: upsert failed for event ${eventId}: ${error.message}`);
  }
  return imageId;
}

/** Manuell im Adminportal an ein Werk verknüpfte Bilder (/work-image-reuse,
 * "Bild manuell einem Werk zuordnen") — bewusst VOR dem automatischen
 * Event-zu-Event-Spender geprüft, weil eine redaktionelle Zuordnung
 * verlässlicher ist als ein Match zwischen zwei fremden Veranstaltungen.
 * Bevorzugt ein venue-spezifisches Bild (z.B. Zauberflöte NUR am
 * Nationaltheater), sonst ein werkweites (venue_id null). Gibt direkt die
 * schon existierende images.id zurück — kein erneuter Download nötig, das
 * Bild wurde beim manuellen Verknüpfen bereits verarbeitet. */
async function findManualWorkImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  eventId: string,
): Promise<string | null> {
  const [{ data: event }, { data: works }] = await Promise.all([
    supabase.from("events").select("venue_id").eq("id", eventId).maybeSingle(),
    supabase.from("event_works").select("work_id").eq("event_id", eventId),
  ]);
  const workIds = ((works ?? []) as { work_id: string }[]).map((w) => w.work_id);
  if (workIds.length === 0) return null;

  if (event?.venue_id) {
    const { data: venueSpecific } = await supabase
      .from("images")
      .select("id")
      .eq("origin_type", "work")
      .in("origin_id", workIds)
      .eq("venue_id", event.venue_id)
      .neq("review_status", "rejected")
      .order("sort_order")
      .limit(1)
      .maybeSingle();
    if (venueSpecific?.id) return venueSpecific.id;
  }

  const { data: workWide } = await supabase
    .from("images")
    .select("id")
    .eq("origin_type", "work")
    .in("origin_id", workIds)
    .is("venue_id", null)
    .neq("review_status", "rejected")
    .order("sort_order")
    .limit(1)
    .maybeSingle();
  return workWide?.id ?? null;
}

/** Standardfall (Ingestion, Backfill): erst ein manuell verknüpftes
 * Werk-Bild, sonst der automatisch gefundene Event-zu-Event-Spender. Gibt
 * null zurück, wenn nichts Passendes gefunden wurde. */
export async function resolveWorkImageFallback(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  eventId: string,
): Promise<string | null> {
  const manualId = await findManualWorkImage(supabase, eventId);
  if (manualId) return manualId;

  const donor = await findWorkImageDonor(supabase, eventId);
  if (!donor) return null;
  return await applyWorkImageReuse(supabase, eventId, donor);
}
