// Erstellt von Claude Code (11.11.2026): Last.fm-Hörprofil für den
// Musikgeschmack. Die App schickt nur den (öffentlichen) Last.fm-Namen;
// der API-Schlüssel bleibt auf dem Server (Secret LASTFM_API_KEY).
// Antwort: { artists: [{name, weight, genres}], tracks: [{title, artist, weight}] }
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function lastfm(method: string, params: Record<string, string>, key: string) {
  const url = new URL("https://ws.audioscrobbler.com/2.0/");
  url.search = new URLSearchParams({ method, api_key: key, format: "json", ...params }).toString();
  const res = await fetch(url, { signal: AbortSignal.timeout(10000), headers: { "User-Agent": "Klangradar/1.0" } });
  // deno-lint-ignore no-explicit-any
  const body: any = await res.json().catch(() => ({}));
  if (body?.error) throw new Error(body.error === 6 ? "user_not_found" : `lastfm_${body.error}`);
  return body;
}

Deno.serve(async (req) => {
  const userClient = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data } = await userClient.auth.getUser();
  if (!data?.user) return json({ error: "not_signed_in" }, 401);

  const key = Deno.env.get("LASTFM_API_KEY");
  if (!key) return json({ error: "not_configured" }, 503);
  const { username, period: rawPeriod } = await req.json().catch(() => ({}));
  // 13.11.2026: Zeitraum wählbar (Standard 12 Monate).
  const period = ["1month", "6month", "12month", "overall"].includes(String(rawPeriod)) ? String(rawPeriod) : "12month";
  const user = typeof username === "string" ? username.trim().slice(0, 64) : "";
  if (!/^[A-Za-z0-9_.-]{2,64}$/.test(user)) return json({ error: "invalid_username" }, 400);

  try {
    const [artistsBody, tracksBody, tagsBody] = await Promise.all([
      lastfm("user.gettopartists", { user, period, limit: "150" }, key),
      lastfm("user.gettoptracks", { user, period, limit: "200" }, key),
      lastfm("user.gettoptags", { user, limit: "10" }, key).catch(() => ({})),
    ]);
    // deno-lint-ignore no-explicit-any
    const tags: string[] = ((tagsBody?.toptags?.tag ?? []) as any[]).map((t) => String(t.name)).slice(0, 8);
    // deno-lint-ignore no-explicit-any
    const artists = ((artistsBody?.topartists?.artist ?? []) as any[]).map((a) => ({
      name: String(a.name ?? ""), weight: Math.log2(Number(a.playcount ?? 1) + 1), genres: tags,
    })).filter((a) => a.name);
    // deno-lint-ignore no-explicit-any
    const tracks = ((tracksBody?.toptracks?.track ?? []) as any[]).map((t) => ({
      title: String(t.name ?? ""), artist: String(t.artist?.name ?? ""), weight: Math.log2(Number(t.playcount ?? 1) + 1),
    })).filter((t) => t.title);
    return json({ artists, tracks });
  } catch (err) {
    const message = err instanceof Error ? err.message : "failed";
    return json({ error: message }, message === "user_not_found" ? 404 : 502);
  }
});
