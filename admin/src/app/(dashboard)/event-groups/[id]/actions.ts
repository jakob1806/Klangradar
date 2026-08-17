"use server";

// "Broadcast"-Bearbeitung: eine Aktion hier wirkt auf event_works/
// event_participants der AUSGEWÄHLTEN Mitgliedsevents der Gruppe, statt
// eine eigene programs/program_items-Struktur einzuführen — event_works
// ist an event_id gebunden (siehe events/[id]/program/actions.ts), das
// bleibt für die App-Seite unverändert, hier wird nur mehrfach dieselbe
// Operation ausgeführt. Duplikate pro Event werden übersprungen (nicht
// jedes Event startet zwangsläufig mit demselben Stand).
//
// Nutzeranfrage: "man kann nicht ändern, bei welchen Terminen eine Person
// dabei ist, und beim Hinzufügen nicht auswählen, wie viele Termine
// betroffen sind" — alle Add-Aktionen nehmen deshalb jetzt eine explizite
// event_ids-Liste aus dem Formular entgegen (Checkbox-Liste in der UI,
// vorbelegt mit allen Terminen) statt implizit "alle". setWork/
// ParticipantEventMembership erlaubt nachträglich, die Zuordnung pro
// bereits hinzugefügtem Werk/Mitwirkenden zu ändern.

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Supa = Awaited<ReturnType<typeof createClient>>;

// Dupliziert aus enrich-event-references/index.ts generateUniqueSlug —
// persons.slug/ensembles.slug sind NOT NULL, kein gemeinsamer Modul-Raum
// zwischen Edge Functions (Deno) und der Next.js-Admin-App.
function slugifyBase(name: string): string {
  const umlauts: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss", Ä: "ae", Ö: "oe", Ü: "ue" };
  let s = name;
  for (const [from, to] of Object.entries(umlauts)) s = s.split(from).join(to);
  return (
    s
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 80)
      .replace(/-+$/g, "") || "eintrag"
  );
}

async function generateUniqueSlug(supabase: Supa, table: "persons" | "ensembles", name: string): Promise<string> {
  const base = slugifyBase(name);
  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from(table).select("id").eq("slug", candidate).maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

async function resolveCanonicalEntity(supabase: Supa, entityType: "person" | "ensemble", name: string): Promise<string | null> {
  const { data } = await supabase.rpc("resolve_entity_alias", {
    p_entity_type: entityType,
    p_name: name,
  });
  return data?.[0]?.id ? String(data[0].id) : null;
}

async function memberEventIds(supabase: Supa, groupId: string): Promise<string[]> {
  const { data } = await supabase.from("events").select("id").eq("program_id", groupId);
  return (data ?? []).map((e) => e.id);
}

// Analog zu findExactEntity in events/[id]/program/actions.ts: Alias-Auflösung
// zuerst, sonst Fallback auf exakten (case-insensitive) Namenstreffer — kein
// gemeinsamer Modul-Raum zwischen den beiden Ordnern, deshalb dupliziert
// statt importiert (siehe Datei-Kommentar zu generateUniqueSlug oben).
async function findMatchForPreview(
  supabase: Supa,
  entityType: "person" | "ensemble",
  name: string,
): Promise<{ id: string; name: string } | null> {
  const { data: resolved } = await supabase.rpc("resolve_entity_alias", {
    p_entity_type: entityType,
    p_name: name,
  });
  if (resolved?.[0]) return { id: String(resolved[0].id), name: String(resolved[0].canonical_name) };
  const table = entityType === "person" ? "persons" : "ensembles";
  const column = entityType === "person" ? "full_name" : "name";
  const { data } = await supabase.from(table).select(`id, ${column}`).ilike(column, name).limit(1).maybeSingle();
  if (!data) return null;
  return { id: data.id as string, name: String(data[column as keyof typeof data] ?? name) };
}

function selectedEventIds(formData: FormData, fallback: string[]): string[] {
  const selected = formData.getAll("event_ids").map(String);
  return selected.length > 0 ? selected : fallback;
}

async function nextWorkPosition(supabase: Supa, eventId: string) {
  const { data } = await supabase
    .from("event_works")
    .select("position")
    .eq("event_id", eventId)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data?.position ?? -1) + 1;
}

async function addWorkToEvents(supabase: Supa, eventIds: string[], workId: string, afterIntermission: boolean) {
  for (const eventId of eventIds) {
    const { data: existing } = await supabase
      .from("event_works")
      .select("event_id")
      .eq("event_id", eventId)
      .eq("work_id", workId)
      .maybeSingle();
    if (existing) continue;

    const position = await nextWorkPosition(supabase, eventId);
    await supabase.from("event_works").insert({
      event_id: eventId,
      work_id: workId,
      position,
      after_intermission: afterIntermission,
    });
  }
}

export async function addExistingWorkToGroup(groupId: string, formData: FormData) {
  const workId = String(formData.get("work_id") ?? "");
  const afterIntermission = formData.get("after_intermission") === "on";
  if (!workId) return;

  const supabase = await createClient();
  const eventIds = selectedEventIds(formData, await memberEventIds(supabase, groupId));
  await addWorkToEvents(supabase, eventIds, workId, afterIntermission);

  revalidatePath(`/event-groups/${groupId}`);
}

export async function createWorkAndAddToGroup(groupId: string, formData: FormData) {
  const title = String(formData.get("title") ?? "").trim();
  const composerId = String(formData.get("composer_id") ?? "") || null;
  const catalogNumber = String(formData.get("catalog_number") ?? "").trim() || null;
  const afterIntermission = formData.get("after_intermission_new") === "on";
  if (!title) return;

  const supabase = await createClient();

  const { data: work, error } = await supabase
    .from("works")
    .insert({ title, composer_id: composerId, catalog_number: catalogNumber })
    .select("id")
    .single();
  if (error) throw new Error(error.message);

  const eventIds = selectedEventIds(formData, await memberEventIds(supabase, groupId));
  await addWorkToEvents(supabase, eventIds, work.id, afterIntermission);

  revalidatePath(`/event-groups/${groupId}`);
}

/** Entfernt das Werk aus JEDEM Mitgliedsevent, das es gerade hat — Klick auf
 * "Entfernen" in der deduplizierten Liste bezieht sich auf die ganze
 * Gruppe. Für eine Teilmenge siehe setWorkEventMembership. */
export async function removeWorkFromGroup(groupId: string, workId: string) {
  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);
  if (eventIds.length === 0) return;

  const { error } = await supabase.from("event_works").delete().eq("work_id", workId).in("event_id", eventIds);
  if (error) throw new Error(error.message);

  revalidatePath(`/event-groups/${groupId}`);
}

/** Fügt ein Bild der Bildergalerie JEDES Mitgliedsevents hinzu (Nutzeranfrage:
 * "man muss auch ein Bild für die gesamte Gruppe, alle Konzerte der Gruppe,
 * hinzufügen können") — es gibt keine eigene Galerie auf Gruppenebene, die
 * App liest Bilder pro Event (images mit origin_type='event'), also wird
 * dasselbe Bild bei jedem Mitgliedsevent eingetragen, das es noch nicht hat.
 * Landet an oberster Position (sort_order 0) und wird damit die
 * Miniaturansicht — vorhandene Event-eigene Bilder bleiben erhalten,
 * rutschen nur eine Position nach hinten.
 *
 * Ersetzt dabei ein zuvor über DIESEN Uploader gesetztes Gruppenbild, statt
 * es zusätzlich zu stapeln — jeder erneute Upload verschob sonst nur die
 * sort_order weiter, ohne den alten Eintrag je zu löschen. Bei wiederholtem
 * Hochladen (z.B. Korrektur eines falschen Bilds) sammelten sich dadurch
 * beliebig viele alte Kopien an (Nutzerfeedback: "es wird nicht das
 * Eventgruppenbild angezeigt" — tatsächlich lag ownGalleryImageUrls durch
 * einen separaten Groß-/Kleinschreibungs-Bug beim UUID-Abgleich immer leer
 * und die App fiel auf ein Mitwirkenden-Foto zurück; die Stapelung machte
 * das Debuggen zusätzlich unübersichtlich). Erkennungsmerkmal für "das ist
 * ein früherer Gruppenbild-Upload": der Storage-Pfad-Präfix
 * entity-photos/event-groups/ — individuell je Event hochgeladene Bilder
 * (anderer Pfad) bleiben unangetastet. */
export async function addGroupImage(groupId: string, sourceUrl: string) {
  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);

  for (const eventId of eventIds) {
    const { error: deleteError } = await supabase
      .from("images")
      .delete()
      .eq("origin_type", "event")
      .eq("origin_id", eventId)
      .like("source_url", "%/entity-photos/event-groups/%");
    if (deleteError) throw new Error(deleteError.message);

    const { data: currentImages } = await supabase
      .from("images")
      .select("id, sort_order")
      .eq("origin_type", "event")
      .eq("origin_id", eventId)
      .order("sort_order", { ascending: true });

    // Alle verbleibenden (nicht-Gruppenbild-)Bilder um eine Position nach
    // hinten schieben, damit das neue Gruppenbild an Position 0 landet,
    // ohne sort_order-Werte zu duplizieren.
    for (let i = (currentImages ?? []).length - 1; i >= 0; i--) {
      await supabase
        .from("images")
        .update({ sort_order: i + 1 })
        .eq("id", currentImages![i].id);
    }

    await supabase.from("images").insert({
      origin_type: "event",
      origin_id: eventId,
      source_url: sourceUrl,
      // Siehe gallery-actions.ts addGalleryImage für die Begründung: NICHT
      // storage_path: sourceUrl, sonst baut die App eine kaputte,
      // doppelt-verschachtelte Storage-URL (sourceUrl ist eine volle
      // externe/entity-photos-URL, kein relativer ingested-images-Pfad).
      storage_path: null,
      sort_order: 0,
      license_status: "confirmed_free",
      needs_review: false,
    });
  }

  revalidatePath(`/event-groups/${groupId}`);
}

/** Entfernt das Gruppenbild wieder von allen Mitgliedsevents (Nutzeranfrage:
 * die Bearbeitungsansicht soll zeigen, OB und WELCHES Gruppenbild bereits
 * hinterlegt ist — dazu gehört auch ein Weg, es wieder zu entfernen, analog
 * zum Löschen in der normalen Event-Galerie). Löscht gezielt die Zeile mit
 * genau dieser sourceUrl statt pauschal sort_order=0, damit ein eigenes
 * Event-Bild an Position 1 nicht mit hochrutscht/verloren geht. */
export async function removeGroupImage(groupId: string, sourceUrl: string) {
  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);
  if (eventIds.length === 0) return;

  const { error } = await supabase
    .from("images")
    .delete()
    .eq("origin_type", "event")
    .in("origin_id", eventIds)
    .eq("source_url", sourceUrl);
  if (error) throw new Error(error.message);

  revalidatePath(`/event-groups/${groupId}`);
}

/** Verschiebt ein Werk in der (deduplizierten) Gruppen-Programmliste um
 * einen Platz — wirkt auf ALLE Mitgliedsevents gleichzeitig, damit die
 * Reihenfolge über die ganze Gruppe konsistent bleibt. Die Referenz-
 * Reihenfolge kommt vom ersten Mitgliedsevent, das dieses Werk enthält
 * (die Gruppen-Broadcast-Logik hält die Reihenfolgen ohnehin synchron);
 * pro Event wird dieselbe (event_id, work_id)-Positionsvertauschung
 * angewendet wie bei einem einzelnen Event (siehe events/[id]/program/
 * actions.ts moveWork), nur für jedes Event einzeln wiederholt. */
export async function moveWorkInGroup(groupId: string, workId: string, direction: "up" | "down") {
  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);
  if (eventIds.length === 0) return;

  const { data: referenceRows } = await supabase
    .from("event_works")
    .select("event_id, work_id, position")
    .in("event_id", eventIds)
    .eq("event_id", eventIds[0])
    .order("position", { ascending: true });

  const list = referenceRows ?? [];
  const index = list.findIndex((r) => r.work_id === workId);
  const swapIndex = direction === "up" ? index - 1 : index + 1;
  if (index === -1 || swapIndex < 0 || swapIndex >= list.length) return;
  const otherWorkId = list[swapIndex].work_id;

  for (const eventId of eventIds) {
    const { data: rows } = await supabase
      .from("event_works")
      .select("work_id, position")
      .eq("event_id", eventId)
      .in("work_id", [workId, otherWorkId]);
    const a = (rows ?? []).find((r) => r.work_id === workId);
    const b = (rows ?? []).find((r) => r.work_id === otherWorkId);
    if (!a || !b) continue; // Event hat eines der beiden Werke nicht (nur X/N Termine) — überspringen

    await supabase.from("event_works").update({ position: -1 }).eq("event_id", eventId).eq("work_id", a.work_id).eq("position", a.position);
    await supabase.from("event_works").update({ position: a.position }).eq("event_id", eventId).eq("work_id", b.work_id).eq("position", b.position);
    await supabase.from("event_works").update({ position: b.position }).eq("event_id", eventId).eq("work_id", a.work_id).eq("position", -1);
  }

  revalidatePath(`/event-groups/${groupId}`);
}

/** Setzt, bei welchen Terminen ein bereits hinzugefügtes Werk dabei ist —
 * fügt fehlende hinzu, entfernt überzählige. Macht die "nur X/N Termine"-
 * Anzeige in der Gruppenübersicht tatsächlich bearbeitbar. */
export async function setWorkEventMembership(groupId: string, workId: string, eventIds: string[]) {
  const supabase = await createClient();
  const allMemberIds = await memberEventIds(supabase, groupId);
  const targetIds = new Set(eventIds.filter((id) => allMemberIds.includes(id)));

  const { data: currentLinks } = await supabase
    .from("event_works")
    .select("event_id")
    .eq("work_id", workId)
    .in("event_id", allMemberIds);
  const currentIds = new Set((currentLinks ?? []).map((l) => l.event_id));

  const toAdd = [...targetIds].filter((id) => !currentIds.has(id));
  const toRemove = [...currentIds].filter((id) => !targetIds.has(id));

  await addWorkToEvents(supabase, toAdd, workId, false);
  if (toRemove.length > 0) {
    await supabase.from("event_works").delete().eq("work_id", workId).in("event_id", toRemove);
  }

  revalidatePath(`/event-groups/${groupId}`);
}

async function addParticipantToEvents(
  supabase: Supa,
  eventIds: string[],
  personId: string | null,
  ensembleId: string | null,
  roleLabel: string | null,
  suggestedRole: string | null = null,
) {
  const normalized = (roleLabel ?? "").toLocaleLowerCase("de");
  const role = suggestedRole
    ?? (normalized.includes("kompon") ? "komponist"
      : normalized.includes("dirigent") || normalized.includes("musikalische leitung") ? "dirigent"
      : normalized.includes("chorleit") ? "chorleiter"
      : normalized.includes("moder") ? "moderator"
      : normalized && !normalized.includes("orchester") && !normalized.includes("chor") && !normalized.includes("ensemble") ? "solist"
      : null);
  for (const eventId of eventIds) {
    let query = supabase.from("event_participants").select("id").eq("event_id", eventId);
    query = personId ? query.eq("person_id", personId) : query.eq("ensemble_id", ensembleId);
    const { data: existing } = await query.maybeSingle();
    if (existing) continue;

    await supabase.from("event_participants").insert({
      event_id: eventId,
      person_id: personId,
      ensemble_id: ensembleId,
      role,
      role_label: roleLabel,
    });
  }
}

export async function addParticipantToGroup(groupId: string, formData: FormData) {
  const personId = String(formData.get("person_id") ?? "") || null;
  const ensembleId = String(formData.get("ensemble_id") ?? "") || null;
  const roleLabel = String(formData.get("role_label") ?? "").trim().slice(0, 160) || null;
  if (!personId && !ensembleId) return;

  const supabase = await createClient();
  const eventIds = selectedEventIds(formData, await memberEventIds(supabase, groupId));
  await addParticipantToEvents(supabase, eventIds, personId, ensembleId, roleLabel);

  revalidatePath(`/event-groups/${groupId}`);
}

/** Legt eine komplett neue Person an (statt nur aus bestehenden wählen zu
 * können, siehe Datei-Kommentar) und fügt sie direkt den ausgewählten
 * Terminen hinzu — is_verified:false wie bei jeder redaktionell frisch
 * angelegten Person (siehe entity-candidates/actions.ts approveEntityCandidate). */
export async function createPersonAndAddToGroup(groupId: string, formData: FormData) {
  const fullName = String(formData.get("full_name") ?? "").trim();
  const roleLabel = String(formData.get("role_label") ?? "").trim().slice(0, 160) || null;
  if (!fullName) return;

  const supabase = await createClient();
  let personId = await resolveCanonicalEntity(supabase, "person", fullName);
  if (!personId) {
    const slug = await generateUniqueSlug(supabase, "persons", fullName);
    const { data: person, error } = await supabase
      .from("persons")
      .insert({ full_name: fullName, slug, is_verified: false })
      .select("id")
      .single();
    if (error) throw new Error(error.message);
    personId = person.id;
  }

  const eventIds = selectedEventIds(formData, await memberEventIds(supabase, groupId));
  await addParticipantToEvents(supabase, eventIds, personId, null, roleLabel);

  revalidatePath(`/event-groups/${groupId}`);
}

export async function createEnsembleAndAddToGroup(groupId: string, formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const roleLabel = String(formData.get("role_label") ?? "").trim().slice(0, 160) || null;
  if (!name) return;

  const supabase = await createClient();
  const eventIds = selectedEventIds(formData, await memberEventIds(supabase, groupId));
  const { data: resolution } = await supabase.rpc("resolve_ensemble_entities", { p_name: name });
  if (resolution?.some((row: { resolution: string }) => ["ignore", "ambiguous"].includes(row.resolution))) return;
  const resolvedIds = (resolution ?? []).map((row: { id: string | null }) => row.id).filter((id: string | null): id is string => id !== null);
  if (resolvedIds.length > 0) {
    for (const ensembleId of resolvedIds) await addParticipantToEvents(supabase, eventIds, null, ensembleId, roleLabel);
    revalidatePath(`/event-groups/${groupId}`);
    return;
  }
  let ensembleId = await resolveCanonicalEntity(supabase, "ensemble", name);
  if (!ensembleId) {
    const slug = await generateUniqueSlug(supabase, "ensembles", name);
    const { data: ensemble, error } = await supabase
      .from("ensembles")
      .insert({ name, slug, type: "sonstiges", is_verified: false })
      .select("id")
      .single();
    if (error) throw new Error(error.message);
    ensembleId = ensemble.id;
  }

  await addParticipantToEvents(supabase, eventIds, null, ensembleId, roleLabel);

  revalidatePath(`/event-groups/${groupId}`);
}

export async function removeParticipantFromGroup(
  groupId: string,
  personId: string | null,
  ensembleId: string | null,
) {
  const supabase = await createClient();
  const eventIds = await memberEventIds(supabase, groupId);
  if (eventIds.length === 0) return;

  let query = supabase.from("event_participants").delete().in("event_id", eventIds);
  query = personId ? query.eq("person_id", personId) : query.eq("ensemble_id", ensembleId);
  const { error } = await query;
  if (error) throw new Error(error.message);

  revalidatePath(`/event-groups/${groupId}`);
}

/** Analog zu setWorkEventMembership, für Mitwirkende. */
export async function setParticipantEventMembership(
  groupId: string,
  personId: string | null,
  ensembleId: string | null,
  roleLabel: string | null,
  role: string | null,
  eventIds: string[],
) {
  const supabase = await createClient();
  const allMemberIds = await memberEventIds(supabase, groupId);
  const targetIds = new Set(eventIds.filter((id) => allMemberIds.includes(id)));

  let currentQuery = supabase.from("event_participants").select("event_id").in("event_id", allMemberIds);
  currentQuery = personId ? currentQuery.eq("person_id", personId) : currentQuery.eq("ensemble_id", ensembleId);
  const { data: currentLinks } = await currentQuery;
  const currentIds = new Set((currentLinks ?? []).map((l) => l.event_id));

  const toAdd = [...targetIds].filter((id) => !currentIds.has(id));
  const toRemove = [...currentIds].filter((id) => !targetIds.has(id));

  await addParticipantToEvents(supabase, toAdd, personId, ensembleId, roleLabel, role);
  if (toRemove.length > 0) {
    let delQuery = supabase.from("event_participants").delete().in("event_id", toRemove);
    delQuery = personId ? delQuery.eq("person_id", personId) : delQuery.eq("ensemble_id", ensembleId);
    await delQuery;
  }

  revalidatePath(`/event-groups/${groupId}`);
}

// Gruppen-Pendant zum "Besetzung mit KI einlesen"-Flow bei Einzelevents
// (events/[id]/program/actions.ts parseParticipantText/importParsedParticipants,
// selbe Edge Function parse-event-participants). Der einzige Unterschied:
// der Import broadcastet über addParticipantToEvents auf die per
// EventChecklist ausgewählten Mitgliedstermine statt auf eine einzelne
// event_id zu schreiben.
type GroupParticipantEntityType = "person" | "ensemble";
type GroupParticipantRoleKind = "komponist" | "dirigent" | "solist" | "chorleiter" | "moderator";

export interface ParsedGroupParticipant {
  name: string;
  entityType: GroupParticipantEntityType;
  roleLabel: string | null;
  roleKind: GroupParticipantRoleKind | null;
  matchedId: string | null;
  matchedName: string | null;
}

export interface GroupParticipantParseState {
  status: "idle" | "success" | "error";
  participants: ParsedGroupParticipant[];
  provider?: string;
  error?: string;
}

export async function parseParticipantTextForGroup(
  _groupId: string,
  _previous: GroupParticipantParseState,
  formData: FormData,
): Promise<GroupParticipantParseState> {
  const text = String(formData.get("participant_text") ?? "").trim();
  if (!text) return { status: "error", participants: [], error: "Bitte zuerst eine Besetzung einfügen." };

  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  try {
    const supabase = await createClient();
    const [{ data: userData }, { data: sessionData }] = await Promise.all([
      supabase.auth.getUser(),
      supabase.auth.getSession(),
    ]);
    if (!userData.user || !sessionData.session?.access_token) {
      return { status: "error", participants: [], error: "Die Admin-Sitzung ist abgelaufen. Bitte erneut anmelden." };
    }

    const response = await fetch(`${baseUrl}/functions/v1/parse-event-participants`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey,
        Authorization: `Bearer ${sessionData.session.access_token}`,
      },
      body: JSON.stringify({ text }),
      signal: AbortSignal.timeout(60_000),
    });
    const body = await response.json().catch(() => null);
    if (!response.ok || !body) {
      return { status: "error", participants: [], error: body?.error ?? `KI-Auswertung fehlgeschlagen (HTTP ${response.status}).` };
    }

    const parsed: unknown[] = Array.isArray(body.participants) ? body.participants.slice(0, 50) : [];
    const validItems = parsed.flatMap((item): {
      name: string;
      entityType: GroupParticipantEntityType;
      roleLabel: string | null;
      roleKind: GroupParticipantRoleKind | null;
    }[] => {
      if (!item || typeof item !== "object") return [];
      const value = item as Record<string, unknown>;
      const name = typeof value.name === "string" ? value.name.trim() : "";
      const entityType: GroupParticipantEntityType | null =
        value.entityType === "person" || value.entityType === "ensemble" ? value.entityType : null;
      if (!name || !entityType) return [];
      return [{
        name,
        entityType,
        roleLabel: typeof value.roleLabel === "string" ? value.roleLabel.trim().slice(0, 160) || null : null,
        roleKind: typeof value.roleKind === "string"
          && ["komponist", "dirigent", "solist", "chorleiter", "moderator"].includes(value.roleKind)
            ? (value.roleKind as GroupParticipantRoleKind)
            : null,
      }];
    });
    const participants: ParsedGroupParticipant[] = await Promise.all(validItems.map(async (item) => {
      const match = await findMatchForPreview(supabase, item.entityType, item.name);
      return { ...item, matchedId: match?.id ?? null, matchedName: match?.name ?? null };
    }));
    return participants.length > 0
      ? { status: "success", participants, provider: typeof body.provider === "string" ? body.provider : undefined }
      : { status: "error", participants: [], error: "Im Text wurden keine eindeutigen Mitwirkenden erkannt." };
  } catch (error) {
    return { status: "error", participants: [], error: error instanceof Error ? error.message : String(error) };
  }
}

export async function importParsedParticipantsToGroup(groupId: string, formData: FormData) {
  const count = Math.min(Number(formData.get("participant_count") ?? 0), 50);
  if (!Number.isFinite(count) || count < 1) return;

  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) throw new Error("Die Admin-Sitzung ist abgelaufen. Bitte erneut anmelden.");

  const eventIds = selectedEventIds(formData, await memberEventIds(supabase, groupId));

  for (let index = 0; index < count; index++) {
    if (formData.get(`selected_${index}`) !== "on") continue;
    const name = String(formData.get(`name_${index}`) ?? "").trim();
    const entityType = String(formData.get(`entity_type_${index}`) ?? "") as GroupParticipantEntityType;
    const roleLabel = String(formData.get(`role_label_${index}`) ?? "").trim().slice(0, 160) || null;
    const roleKind = String(formData.get(`role_kind_${index}`) ?? "") || null;
    const matchedId = String(formData.get(`matched_id_${index}`) ?? "") || null;
    if (!name || (entityType !== "person" && entityType !== "ensemble")) continue;

    let entityId = matchedId;
    if (!entityId) entityId = (await findMatchForPreview(supabase, entityType, name))?.id ?? null;
    if (!entityId) {
      const table = entityType === "person" ? "persons" : "ensembles";
      const slug = await generateUniqueSlug(supabase, table, name);
      if (entityType === "person") {
        const { data, error } = await supabase.from("persons").insert({ full_name: name, slug, is_verified: false }).select("id").single();
        if (error) throw new Error(error.message);
        entityId = data.id;
      } else {
        const { data, error } = await supabase.from("ensembles").insert({ name, slug, type: "sonstiges", is_verified: false }).select("id").single();
        if (error) throw new Error(error.message);
        entityId = data.id;
      }
    }

    await addParticipantToEvents(
      supabase,
      eventIds,
      entityType === "person" ? entityId : null,
      entityType === "ensemble" ? entityId : null,
      roleLabel,
      roleKind,
    );
  }

  revalidatePath(`/event-groups/${groupId}`);
}
