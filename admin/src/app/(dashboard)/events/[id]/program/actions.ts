"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Supa = Awaited<ReturnType<typeof createClient>>;
type EntityType = "person" | "ensemble";
type RoleKind = "komponist" | "dirigent" | "solist" | "chorleiter" | "moderator";

export interface ParsedParticipant {
  name: string;
  entityType: EntityType;
  roleLabel: string | null;
  roleKind: RoleKind | null;
  matchedId: string | null;
  matchedName: string | null;
}

export interface ParticipantParseState {
  status: "idle" | "success" | "error";
  participants: ParsedParticipant[];
  provider?: string;
  error?: string;
}

function slugifyBase(name: string): string {
  const umlauts: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss", Ä: "ae", Ö: "oe", Ü: "ue" };
  let value = name;
  for (const [from, to] of Object.entries(umlauts)) value = value.split(from).join(to);
  return value
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "") || "eintrag";
}

async function generateUniqueSlug(supabase: Supa, table: "persons" | "ensembles", name: string) {
  const base = slugifyBase(name);
  for (let attempt = 0; attempt < 20; attempt++) {
    const slug = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from(table).select("id").eq("slug", slug).maybeSingle();
    if (!data) return slug;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

function roleKindFrom(label: string, suggested?: string | null): RoleKind | null {
  const allowed = new Set<RoleKind>(["komponist", "dirigent", "solist", "chorleiter", "moderator"]);
  if (suggested && allowed.has(suggested as RoleKind)) return suggested as RoleKind;
  const value = label.toLocaleLowerCase("de");
  if (value.includes("kompon")) return "komponist";
  if (value.includes("dirigent") || value.includes("musikalische leitung")) return "dirigent";
  if (value.includes("chorleit")) return "chorleiter";
  if (value.includes("moder")) return "moderator";
  if (value && !value.includes("orchester") && !value.includes("chor") && !value.includes("ensemble")) return "solist";
  return null;
}

async function linkParticipant(
  supabase: Supa,
  eventId: string,
  personId: string | null,
  ensembleId: string | null,
  roleLabel: string | null,
  suggestedRole?: string | null,
) {
  let existingQuery = supabase.from("event_participants").select("id").eq("event_id", eventId);
  existingQuery = personId ? existingQuery.eq("person_id", personId) : existingQuery.eq("ensemble_id", ensembleId);
  const { data: existing } = await existingQuery.maybeSingle();
  const role = roleKindFrom(roleLabel ?? "", suggestedRole);
  const payload = { role, role_label: roleLabel };
  if (existing) {
    const { error } = await supabase.from("event_participants").update(payload).eq("id", existing.id);
    if (error) throw new Error(error.message);
  } else {
    const { error } = await supabase.from("event_participants").insert({
      event_id: eventId,
      person_id: personId,
      ensemble_id: ensembleId,
      ...payload,
    });
    if (error) throw new Error(error.message);
  }
}

async function nextWorkPosition(
  supabase: Awaited<ReturnType<typeof createClient>>,
  eventId: string,
) {
  const { data } = await supabase
    .from("event_works")
    .select("position")
    .eq("event_id", eventId)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data?.position ?? -1) + 1;
}

export async function addExistingWork(eventId: string, formData: FormData) {
  const workId = String(formData.get("work_id") ?? "");
  const afterIntermission = formData.get("after_intermission") === "on";
  if (!workId) return;

  const supabase = await createClient();
  const position = await nextWorkPosition(supabase, eventId);

  const { error } = await supabase.from("event_works").insert({
    event_id: eventId,
    work_id: workId,
    position,
    after_intermission: afterIntermission,
  });
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}

export async function createWorkAndAdd(eventId: string, formData: FormData) {
  const title = String(formData.get("title") ?? "").trim();
  const composerId = String(formData.get("composer_id") ?? "") || null;
  const catalogNumber = String(formData.get("catalog_number") ?? "").trim() || null;
  const afterIntermission = formData.get("after_intermission_new") === "on";
  if (!title) return;

  const supabase = await createClient();
  const { data: matches } = await supabase.rpc("find_matching_work", {
    p_title: title,
    p_composer_id: composerId,
    p_result_limit: 1,
  });
  let workId = matches?.[0]?.similarity >= 0.999 ? String(matches[0].id) : null;
  if (workId) {
    await supabase.from("entity_aliases").upsert(
      { entity_type: "work", entity_id: workId, alias: title },
      { onConflict: "entity_type,entity_id,alias_normalized" },
    );
  } else {
    const { data: work, error: workError } = await supabase
      .from("works")
      .insert({ title, composer_id: composerId, catalog_number: catalogNumber })
      .select("id")
      .single();
    if (workError) throw new Error(workError.message);
    workId = work.id;
  }

  const position = await nextWorkPosition(supabase, eventId);
  const { error } = await supabase.from("event_works").insert({
    event_id: eventId,
    work_id: workId,
    position,
    after_intermission: afterIntermission,
  });
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}

/** Vertauscht die Position mit dem direkten Nachbarn — Nutzeranfrage: "man
 * soll die Reihenfolge der Programmpunkte auch immer ändern können". Setzt
 * die verschobene Zeile kurz auf eine unbenutzte Zwischen-Position (-1),
 * um einen PK-Konflikt zu vermeiden, falls (event_id, work_id, position)
 * für einen Moment mit der Zielposition kollidieren würde — analog zum
 * bestehenden event_works-Umbiegen beim Werk-Duplikate-Merge
 * (duplicates/works/actions.ts). after_intermission bleibt unangetastet,
 * es hängt am work_id-Datensatz und wandert dadurch automatisch mit.
 */
export async function moveWork(
  eventId: string,
  workId: string,
  position: number,
  direction: "up" | "down",
) {
  const supabase = await createClient();
  const { data: rows } = await supabase
    .from("event_works")
    .select("work_id, position")
    .eq("event_id", eventId)
    .order("position", { ascending: true });

  const list = rows ?? [];
  const index = list.findIndex((r) => r.work_id === workId && r.position === position);
  const swapIndex = direction === "up" ? index - 1 : index + 1;
  if (index === -1 || swapIndex < 0 || swapIndex >= list.length) return;

  const a = list[index];
  const b = list[swapIndex];

  await supabase.from("event_works").update({ position: -1 }).eq("event_id", eventId).eq("work_id", a.work_id).eq("position", a.position);
  await supabase.from("event_works").update({ position: a.position }).eq("event_id", eventId).eq("work_id", b.work_id).eq("position", b.position);
  await supabase.from("event_works").update({ position: b.position }).eq("event_id", eventId).eq("work_id", a.work_id).eq("position", -1);

  revalidatePath(`/events/${eventId}/program`);
}

export async function removeWork(eventId: string, workId: string, position: number) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("event_works")
    .delete()
    .eq("event_id", eventId)
    .eq("work_id", workId)
    .eq("position", position);
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}

export async function addParticipant(eventId: string, formData: FormData) {
  const personId = String(formData.get("person_id") ?? "") || null;
  const ensembleId = String(formData.get("ensemble_id") ?? "") || null;
  const roleLabel = String(formData.get("role_label") ?? "").trim().slice(0, 160) || null;
  if (!personId && !ensembleId) return;

  const supabase = await createClient();
  await linkParticipant(supabase, eventId, personId, ensembleId, roleLabel);

  revalidatePath(`/events/${eventId}/program`);
}

export async function createPersonAndAdd(eventId: string, formData: FormData) {
  const fullName = String(formData.get("full_name") ?? "").trim();
  const roleLabel = String(formData.get("role_label") ?? "").trim().slice(0, 160) || null;
  if (!fullName) return;
  const supabase = await createClient();
  const existing = await findExactEntity(supabase, "person", fullName);
  let personId = existing?.id ?? null;
  if (!personId) {
    const slug = await generateUniqueSlug(supabase, "persons", fullName);
    const { data, error } = await supabase.from("persons").insert({ full_name: fullName, slug, is_verified: false }).select("id").single();
    if (error) throw new Error(error.message);
    personId = data.id;
  }
  await linkParticipant(supabase, eventId, personId, null, roleLabel);
  revalidatePath(`/events/${eventId}/program`);
  revalidatePath("/persons");
}

export async function createEnsembleAndAdd(eventId: string, formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const roleLabel = String(formData.get("role_label") ?? "").trim().slice(0, 160) || null;
  if (!name) return;
  const supabase = await createClient();
  const { data: resolution } = await supabase.rpc("resolve_ensemble_entities", { p_name: name });
  const resolvedIds = (resolution ?? []).map((row: { id: string | null }) => row.id).filter((id: string | null): id is string => id !== null);
  if (resolution?.some((row: { resolution: string }) => ["ignore", "ambiguous"].includes(row.resolution))) return;
  if (resolvedIds.length > 0) {
    for (const ensembleId of resolvedIds) await linkParticipant(supabase, eventId, null, ensembleId, roleLabel);
    revalidatePath(`/events/${eventId}/program`);
    return;
  }
  const existing = await findExactEntity(supabase, "ensemble", name);
  let ensembleId = existing?.id ?? null;
  if (!ensembleId) {
    const slug = await generateUniqueSlug(supabase, "ensembles", name);
    const { data, error } = await supabase.from("ensembles").insert({ name, slug, type: "sonstiges", is_verified: false }).select("id").single();
    if (error) throw new Error(error.message);
    ensembleId = data.id;
  }
  await linkParticipant(supabase, eventId, null, ensembleId, roleLabel);
  revalidatePath(`/events/${eventId}/program`);
  revalidatePath("/ensembles");
}

async function findExactEntity(supabase: Supa, entityType: EntityType, name: string) {
  const { data: resolved } = await supabase.rpc("resolve_entity_alias", {
    p_entity_type: entityType,
    p_name: name,
  });
  if (resolved?.[0]) {
    return { id: String(resolved[0].id), name: String(resolved[0].canonical_name) };
  }
  const table = entityType === "person" ? "persons" : "ensembles";
  const column = entityType === "person" ? "full_name" : "name";
  const { data } = await supabase.from(table).select(`id, ${column}`).ilike(column, name).limit(1).maybeSingle();
  if (!data) return null;
  return { id: data.id as string, name: String(data[column as keyof typeof data] ?? name) };
}

export async function parseParticipantText(
  _eventId: string,
  _previous: ParticipantParseState,
  formData: FormData,
): Promise<ParticipantParseState> {
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
    const validItems = parsed.flatMap((item): { name: string; entityType: EntityType; roleLabel: string | null; roleKind: RoleKind | null }[] => {
      if (!item || typeof item !== "object") return [];
      const value = item as Record<string, unknown>;
      const name = typeof value.name === "string" ? value.name.trim() : "";
      const entityType: EntityType | null = value.entityType === "person" || value.entityType === "ensemble" ? value.entityType : null;
      if (!name || !entityType) return [];
      return [{
        name,
        entityType,
        roleLabel: typeof value.roleLabel === "string" ? value.roleLabel.trim().slice(0, 160) || null : null,
        roleKind: typeof value.roleKind === "string"
          && ["komponist", "dirigent", "solist", "chorleiter", "moderator"].includes(value.roleKind)
            ? value.roleKind as RoleKind
            : null,
      }];
    });
    const participants: ParsedParticipant[] = await Promise.all(validItems.map(async (item) => {
      const match = await findExactEntity(supabase, item.entityType, item.name);
      return {
        ...item,
        matchedId: match?.id ?? null,
        matchedName: match?.name ?? null,
      };
    }));
    return participants.length > 0
      ? { status: "success", participants, provider: typeof body.provider === "string" ? body.provider : undefined }
      : { status: "error", participants: [], error: "Im Text wurden keine eindeutigen Mitwirkenden erkannt." };
  } catch (error) {
    return { status: "error", participants: [], error: error instanceof Error ? error.message : String(error) };
  }
}

export async function importParsedParticipants(eventId: string, formData: FormData) {
  const count = Math.min(Number(formData.get("participant_count") ?? 0), 50);
  if (!Number.isFinite(count) || count < 1) return;
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) throw new Error("Die Admin-Sitzung ist abgelaufen. Bitte erneut anmelden.");

  for (let index = 0; index < count; index++) {
    if (formData.get(`selected_${index}`) !== "on") continue;
    const name = String(formData.get(`name_${index}`) ?? "").trim();
    const entityType = String(formData.get(`entity_type_${index}`) ?? "") as EntityType;
    const roleLabel = String(formData.get(`role_label_${index}`) ?? "").trim().slice(0, 160) || null;
    const roleKind = String(formData.get(`role_kind_${index}`) ?? "") || null;
    const matchedId = String(formData.get(`matched_id_${index}`) ?? "") || null;
    if (!name || (entityType !== "person" && entityType !== "ensemble")) continue;

    let entityId = matchedId;
    if (!entityId) entityId = (await findExactEntity(supabase, entityType, name))?.id ?? null;
    if (!entityId) {
      const table = entityType === "person" ? "persons" : "ensembles";
      const slug = await generateUniqueSlug(supabase, table, name);
      if (entityType === "person") {
        const { data, error } = await supabase
          .from("persons")
          .insert({ full_name: name, slug, is_verified: false })
          .select("id")
          .single();
        if (error) throw new Error(error.message);
        entityId = data.id;
      } else {
        const { data, error } = await supabase
          .from("ensembles")
          .insert({ name, slug, type: "sonstiges", is_verified: false })
          .select("id")
          .single();
        if (error) throw new Error(error.message);
        entityId = data.id;
      }
    }
    await linkParticipant(
      supabase,
      eventId,
      entityType === "person" ? entityId : null,
      entityType === "ensemble" ? entityId : null,
      roleLabel,
      roleKind,
    );
  }

  revalidatePath(`/events/${eventId}/program`);
  revalidatePath("/persons");
  revalidatePath("/ensembles");
}

export async function removeParticipant(eventId: string, participantId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("event_participants").delete().eq("id", participantId);
  if (error) throw new Error(error.message);

  revalidatePath(`/events/${eventId}/program`);
}
