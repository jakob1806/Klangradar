// Erstellt von Claude Code (Konzept Bildabdeckung, 01.11.2026): Porträts aus
// Orchester-Besetzungsseiten und Künstleragenturen (siehe
// _shared/artistPhotoSources.ts) für Personen OHNE Foto. Abgleich über den
// vollständigen Namen (ohne Akzente); bei Namensgleichheit mehrerer Personen
// wird nichts übernommen. Jedes Bild mit Quelle, Quellseite und
// Fotografen-Credit, Lizenzstatus official_press_image.
//
// Aufruf: POST {"source"?: key, "limit"?: 15, "dryRun"?: true}. Ohne source
// wechselt die Quelle stündlich (Cron).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { isAllowedByRobots } from "../_shared/robots.ts";
import { ensureCoverImageWithReason } from "../_shared/imagePipeline.ts";
import { ARTIST_SOURCES, type ArtistPhoto, nameKey } from "../_shared/artistPhotoSources.ts";

const UA = "KlangradarBot/1.0 (+https://www.klangradar.com)";

async function fetchHtml(url: string): Promise<string | null> {
  if (!(await isAllowedByRobots(url))) return null;
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA, "Accept": "text/html" }, signal: AbortSignal.timeout(15000) });
    return res.ok ? await res.text() : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 15, 1), 40);
  const dryRun = body.dryRun === true;
  const source = ARTIST_SOURCES.find((s) => s.key === body.source)
    ?? ARTIST_SOURCES[Math.floor(Date.now() / 3600000) % ARTIST_SOURCES.length];
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  // Personen ohne Foto, eindeutig über den Namen.
  const byKey = new Map<string, string[]>();
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db.from("persons").select("id, full_name").is("photo_url", null).range(from, from + 999);
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    for (const p of data ?? []) byKey.set(nameKey(p.full_name), [...(byKey.get(nameKey(p.full_name)) ?? []), p.id]);
    if (!data || data.length < 1000) break;
  }
  const unique = (key: string) => (byKey.get(key)?.length ?? 0) === 1;

  // Kandidaten der Quelle sammeln.
  const photos: ArtistPhoto[] = [];
  for (const page of source.rosterPages ?? []) {
    const html = await fetchHtml(page.url);
    if (html) photos.push(...page.parse(html, page.url));
  }
  let listed = photos.length;
  if (source.list) {
    const html = await fetchHtml(source.list.url);
    const entries = html ? source.list.parse(html) : [];
    listed = entries.length;
    for (const entry of entries.filter((e) => unique(nameKey(e.name))).slice(0, limit)) {
      const detail = await fetchHtml(entry.detailUrl);
      const photo = detail ? source.list.detail(detail, entry.detailUrl, entry.name) : null;
      if (photo) photos.push(photo);
    }
  }

  const matches = photos.filter((p) => p.credit && unique(nameKey(p.name))).slice(0, limit);
  const results: { name: string; ok: boolean; reason?: string }[] = [];
  for (const photo of matches) {
    const personId = byKey.get(nameKey(photo.name))![0];
    if (dryRun) { results.push({ name: photo.name, ok: true }); continue; }
    const { id, reason } = await ensureCoverImageWithReason(db, {
      sourceUrl: photo.imageUrl,
      originType: "person",
      originId: personId,
      sourcePageUrl: photo.pageUrl,
      sourceName: source.label,
      photographer: photo.credit,
      credits: `${photo.credit} · ${source.label}`,
      licenseStatus: "official_press_image",
      confidenceScore: 0.9,
      matchReason: `Name stimmt mit der Seite von ${source.label} überein.`,
      needsReview: false,
    });
    if (!id) { results.push({ name: photo.name, ok: false, reason }); continue; }
    const { data: image } = await db.from("images").select("storage_path").eq("id", id).maybeSingle();
    if (!image?.storage_path) { results.push({ name: photo.name, ok: false, reason: "kein Speicherpfad" }); continue; }
    const publicUrl = db.storage.from("ingested-images").getPublicUrl(image.storage_path).data.publicUrl;
    await db.from("persons").update({
      photo_url: publicUrl,
      image_search_checked_at: new Date().toISOString(),
      last_image_search_note: `Porträt von ${source.label} (${photo.credit}).`,
    }).eq("id", personId).is("photo_url", null);
    await db.from("images").update({ is_primary: true }).eq("id", id);
    results.push({ name: photo.name, ok: true });
  }

  return new Response(JSON.stringify({ source: source.key, listed, candidates: photos.length, matched: matches.length, dryRun, results }), {
    headers: { "Content-Type": "application/json" },
  });
});
