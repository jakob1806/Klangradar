// Erstellt von Claude Code (26.10.2026): Nutzer:innen legen beim eigenen
// Konzerteintrag fehlende Personen, Ensembles, Werke oder Orte nur mit dem
// Namen an. Die Function sucht zuerst nach einem bestehenden Eintrag, legt
// sonst einen an (Orte per OpenStreetMap-Suche mit Adresse/Koordinaten),
// stößt die bestehende automatische Anreicherung an (Biografie, Bilder,
// Lebensdaten, Werkeinführung) und protokolliert die Anfrage für die Redaktion.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { json, resolveComposer, resolveEnsembles, resolvePerson, resolveWork, uniqueSlug } from "../_shared/eventParticipantResolution.ts";
import { USER_AGENT } from "../_shared/robots.ts";

type EntityType = "person" | "ensemble" | "venue" | "work";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const token = req.headers.get("Authorization")?.replace(/^Bearer /i, "") ?? "";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: userData } = await userClient.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) return json({ error: "Anmeldung erforderlich" }, 401);

  const body = await req.json().catch(() => ({}));
  const type = body.type as EntityType;
  const name = String(body.name ?? "").trim().replace(/\s+/g, " ");
  const context = body.context ? String(body.context).trim().slice(0, 200) : null;
  if (!["person", "ensemble", "venue", "work"].includes(type) || name.length < 2 || name.length > 200) {
    return json({ error: "Ungültige Anfrage" }, 400);
  }
  const supabase = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  // Missbrauchsschutz: höchstens 30 Anfragen pro Nutzer und Tag.
  const { count } = await supabase.from("entity_requests").select("id", { count: "exact", head: true })
    .eq("user_id", userId).gte("created_at", new Date(Date.now() - 86_400_000).toISOString());
  if ((count ?? 0) >= 30) return json({ error: "Tageslimit erreicht" }, 429);

  let id: string | null = null;
  let status: "created" | "existing" | "needs_review" = "created";
  let note: string | null = null;
  try {
    if (type === "person") {
      const { data: before } = await supabase.rpc("find_matching_person", { p_name: name, p_result_limit: 1 });
      id = await resolvePerson(supabase, { name, profileUrl: null, role: context, type: "person" });
      if (before?.length) status = "existing";
    } else if (type === "ensemble") {
      const { data: before } = await supabase.rpc("find_matching_ensemble", { p_name: name, p_result_limit: 1 });
      id = (await resolveEnsembles(supabase, name))[0] ?? null;
      if (before?.length) status = "existing";
      else if (id) await enrich("ensemble", id);
    } else if (type === "work") {
      const composerId = context ? await resolveComposer(supabase, context) : null;
      const { data: before } = await supabase.rpc("find_matching_work", { p_title: name, p_composer_id: composerId, p_result_limit: 1 }).then((r) => r, () => ({ data: null }));
      id = await resolveWork(supabase, name, composerId);
      if (before?.length) status = "existing";
    } else {
      const { data: existing } = await supabase.from("venues").select("id").ilike("name", name).limit(1);
      if (existing?.length) {
        id = existing[0].id;
        status = "existing";
      } else {
        const place = await geocode(name, context);
        if (!place) {
          status = "needs_review";
          note = "Ort nicht automatisch gefunden – bitte redaktionell anlegen.";
        } else {
          const { data: created, error } = await supabase.from("venues").insert({
            slug: await uniqueSlug(supabase, "venues", name),
            name,
            address_street: place.street,
            address_zip: place.zip,
            address_city: place.city,
            location: `SRID=4326;POINT(${place.lon} ${place.lat})`,
            is_verified: false,
          }).select("id").single();
          if (error) { status = "needs_review"; note = error.message; }
          else { id = created.id; await enrich("venue", id!); }
        }
      }
    }
  } catch (err) {
    status = "needs_review";
    note = err instanceof Error ? err.message : String(err);
  }

  await supabase.from("entity_requests").insert({
    user_id: userId, entity_type: type, name, context, status, created_entity_id: id, note,
  });
  return json({ id, status, name });

  async function enrich(entityType: "ensemble" | "venue", entityId: string) {
    const headers = { "Content-Type": "application/json", "x-internal-secret": Deno.env.get("INTERNAL_FUNCTION_SECRET") ?? "" };
    await Promise.allSettled([
      fetch(`${url}/functions/v1/enrich-entity-oncall`, { method: "POST", headers, body: JSON.stringify({ entityType, entityId }) }),
      fetch(`${url}/functions/v1/enrich-entity-images`, { method: "POST", headers, body: JSON.stringify({ type: entityType, limit: 1, entityIds: [entityId], fastFallback: true }) }),
    ]);
  }
});

async function geocode(name: string, city: string | null) {
  const q = [name, city].filter(Boolean).join(", ");
  const res = await fetch(`https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&limit=1&q=${encodeURIComponent(q)}`, {
    headers: { "User-Agent": USER_AGENT, "Accept-Language": "de" },
  });
  if (!res.ok) return null;
  const hit = (await res.json())?.[0];
  if (!hit) return null;
  const a = hit.address ?? {};
  return {
    lat: Number(hit.lat), lon: Number(hit.lon),
    street: [a.road, a.house_number].filter(Boolean).join(" ") || name,
    zip: a.postcode ?? "",
    city: a.city ?? a.town ?? a.village ?? city ?? "",
  };
}
