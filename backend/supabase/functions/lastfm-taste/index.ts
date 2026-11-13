// Erstellt von Claude Code (11.11.2026): Last.fm-Hörprofil für den
// Musikgeschmack. Die App schickt nur den (öffentlichen) Last.fm-Namen;
// der API-Schlüssel bleibt auf dem Server (Secret LASTFM_API_KEY).
// Antwort: { artists: [{name, weight, genres}], tracks: [{title, artist, weight}] }
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { crypto as stdCrypto } from "https://deno.land/std@0.224.0/crypto/mod.ts";
import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";

// 13.11.2026: Anmelden per Last.fm-Fenster (statt Namen eintippen).
// GET ?login=1        → Weiterleitung zur Last.fm-Anmeldeseite
// GET ?callback=1&token → zurück in die App (de.klangradar.native://lastfm-callback)
// POST {token}        → Token gegen Sitzung tauschen (Secret LASTFM_SHARED_SECRET), Name ermitteln
const SELF_URL = `${Deno.env.get("SUPABASE_URL") ?? ""}/functions/v1/lastfm-taste`;

async function sessionName(token: string, key: string, secret: string): Promise<string> {
  const params: Record<string, string> = { api_key: key, method: "auth.getSession", token };
  const raw = Object.keys(params).sort().map((k) => k + params[k]).join("") + secret;
  const sig = encodeHex(await stdCrypto.subtle.digest("MD5", new TextEncoder().encode(raw)));
  const url = new URL("https://ws.audioscrobbler.com/2.0/");
  url.search = new URLSearchParams({ ...params, api_sig: sig, format: "json" }).toString();
  const res = await fetch(url, { signal: AbortSignal.timeout(10000), headers: { "User-Agent": "Klangradar/1.0" } });
  // deno-lint-ignore no-explicit-any
  const body: any = await res.json().catch(() => ({}));
  const name = body?.session?.name;
  if (typeof name !== "string" || !name) throw new Error("login_failed");
  return name;
}

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
  const reqUrl = new URL(req.url);
  if (req.method === "GET") {
    const key = Deno.env.get("LASTFM_API_KEY") ?? "";
    if (reqUrl.searchParams.get("login") === "1") {
      const cb = `${SELF_URL}?callback=1`;
      return Response.redirect(`https://www.last.fm/api/auth/?api_key=${encodeURIComponent(key)}&cb=${encodeURIComponent(cb)}`, 302);
    }
    if (reqUrl.searchParams.get("callback") === "1") {
      const token = (reqUrl.searchParams.get("token") ?? "").replace(/[^A-Za-z0-9_-]/g, "").slice(0, 64);
      return new Response(null, { status: 302, headers: { Location: `de.klangradar.native://lastfm-callback?token=${token}` } });
    }
    return json({ error: "not_found" }, 404);
  }
  const userClient = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data } = await userClient.auth.getUser();
  if (!data?.user) return json({ error: "not_signed_in" }, 401);

  const key = Deno.env.get("LASTFM_API_KEY");
  if (!key) return json({ error: "not_configured" }, 503);
  const { username: rawUser, token: loginToken, period: rawPeriod } = await req.json().catch(() => ({}));
  let username = rawUser;
  if (typeof loginToken === "string" && loginToken) {
    const secret = Deno.env.get("LASTFM_SHARED_SECRET");
    if (!secret) return json({ error: "not_configured" }, 503);
    try { username = await sessionName(loginToken, key, secret); } catch { return json({ error: "login_failed" }, 401); }
  }
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
    return json({ username: user, artists, tracks });
  } catch (err) {
    const message = err instanceof Error ? err.message : "failed";
    return json({ error: message }, message === "user_not_found" ? 404 : 502);
  }
});
