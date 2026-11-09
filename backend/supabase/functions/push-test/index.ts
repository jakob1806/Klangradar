// Erstellt von Claude Code (09.11.2026): Testmitteilung an die eigenen
// Geräte (Mitteilungs-Einstellungen → „Testmitteilung senden“). Antwortet
// mit einer Diagnose: wie viele Geräte registriert sind und ob Apple sie
// angenommen hat – ohne Tokens oder Schlüssel preiszugeben.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPushToTokens } from "../_shared/fcm.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const authorization = req.headers.get("Authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } });
  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json({ error: "Nicht angemeldet" }, 401);

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: tokens } = await db.from("push_tokens").select("token").eq("user_id", user.id);
  const list = (tokens ?? []).map((t: { token: string }) => t.token);
  if (!list.length) return json({ devices: 0, delivered: 0, note: "Kein Gerät registriert." });

  const results = await sendPushToTokens(list, {
    title: "Klangradar",
    body: "Testmitteilung: Mitteilungen kommen bei dir an. 🎻",
    data: { route: "/", kind: "test" },
  });
  const invalid = results.filter((r) => r.invalidToken).map((r) => r.token);
  if (invalid.length) await db.from("push_tokens").delete().in("token", invalid);
  const errors = [...new Set(results.filter((r) => !r.ok).map((r) => (r.error ?? "").slice(0, 120)).filter(Boolean))];
  return json({ devices: list.length, delivered: results.filter((r) => r.ok).length, removed: invalid.length, errors });
});
