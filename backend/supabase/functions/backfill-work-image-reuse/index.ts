import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveWorkImageFallback } from "../_shared/workImageReuse.ts";

// Seitenweise wie audit-persons-bulk (siehe dortiger Kommentar) — bei vielen
// Veranstaltungen ohne Bild würde ein einziger Aufruf über alle sonst in den
// Timeout laufen. Zielmenge: JEDE Veranstaltung ohne eigenes Bild
// (image_urls leer), auch wenn schon ein generischer Ensemble-/Personen-/
// Venue-Fallback als primary_image_id gesetzt ist — die Werk-Wiederverwendung
// ist spezifischer und darf einen bestehenden Fallback ersetzen (siehe
// Prioritäts-Kommentar in ingest-source/write.ts resolveFallbackImage).
const PAGE_SIZE = 100;

const jsonHeaders = { "content-type": "application/json; charset=utf-8" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Nur POST ist erlaubt." }, 405);
  }
  const authorized = await isEditor(req);
  if (!authorized) {
    return json({ error: "Keine Admin- oder Redaktionsberechtigung." }, 403);
  }

  let body: { offset?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    // leerer Body ist ok, dann offset 0
  }
  const offset = typeof body.offset === "number" && body.offset >= 0 ? body.offset : 0;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: events, error, count } = await supabase
    .from("events")
    .select("id, primary_image_id", { count: "exact" })
    .or("image_urls.is.null,image_urls.eq.{}")
    .order("id")
    .range(offset, offset + PAGE_SIZE - 1);
  if (error) {
    return json({ error: error.message }, 500);
  }

  const rows = (events ?? []) as { id: string; primary_image_id: string | null }[];
  const totalCount = count ?? offset + rows.length;

  let filledInPage = 0;
  for (const event of rows) {
    const imageId = await resolveWorkImageFallback(supabase, event.id);
    if (!imageId || imageId === event.primary_image_id) continue;
    const { error: updateError } = await supabase
      .from("events")
      .update({ primary_image_id: imageId })
      .eq("id", event.id);
    if (updateError) {
      console.error(`backfill-work-image-reuse: failed to set primary_image_id for ${event.id}: ${updateError.message}`);
      continue;
    }
    filledInPage++;
  }

  return json({
    status: "ok",
    offset,
    checkedInPage: rows.length,
    filledInPage,
    totalCount,
    done: offset + rows.length >= totalCount,
    checkedAt: new Date().toISOString(),
  });
});

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: jsonHeaders });
}

async function isEditor(req: Request): Promise<boolean> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return false;
  const client = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: userData, error: userError } = await client.auth.getUser();
  if (userError || !userData.user || userData.user.is_anonymous) return false;
  const { data, error } = await client.rpc("is_admin_or_editor");
  return !error && data === true;
}
