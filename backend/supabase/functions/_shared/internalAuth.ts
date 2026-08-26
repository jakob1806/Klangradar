// Autorisierung für Functions, die mit dem Service-Role-Key arbeiten (RLS
// umgangen) und deshalb NICHT allein über Supabase' Standard-verify_jwt
// abgesichert werden dürfen: verify_jwt prüft nur "ist das irgendein
// gültiges Supabase-JWT" — und der Anon-Key, der das erfüllt, ist
// öffentlich (im App-Bundle, in admin/.env.local.example, in den
// pg_cron-Migrationen). Ohne diese Prüfung könnte jede Person mit dem
// Anon-Key jede dieser Functions beliebig oft mit vollem Service-Role-
// Zugriff aufrufen (Kosten-Abuse bei LLM-/Such-Aufrufen, Scraping-Abuse,
// Notification-Spam, unerwünschte Schreibzugriffe).
//
// Zwei legitime Aufrufer, zwei Prüfwege:
// 1. Admin-Dashboard (Nutzersession) -> Bearer-Token der eingeloggten
//    Person wird durchgereicht, wir prüfen is_admin_or_editor() per RPC
//    (gleiches Muster wie editorial-ai-assistant/audit-entity).
// 2. pg_cron / run-all-sources-Orchestrator (kein Nutzer) -> ein
//    gemeinsames Secret im Header "x-internal-secret", das nur der
//    DB-Cron-Job und Server-Actions im Admin-Dashboard kennen (als
//    Supabase-Function-Secret INTERNAL_FUNCTION_SECRET hinterlegt, siehe
//    docs/10-legal-status.md).
//
// Fehlt/mismatched beides -> 401/403, Function bricht sofort ab, bevor der
// Service-Role-Client überhaupt erstellt wird.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function bearer(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer (.+)$/i);
  return match ? match[1] : null;
}

/** Gibt eine 401/403-Response zurück, falls der Aufruf nicht autorisiert
 * ist, sonst null (Aufrufer macht mit dem eigentlichen Handler weiter). */
export async function requireInternalAuth(req: Request): Promise<Response | null> {
  const internalSecret = Deno.env.get("INTERNAL_FUNCTION_SECRET");
  const providedSecret = req.headers.get("x-internal-secret");
  if (internalSecret && providedSecret === internalSecret) {
    return null;
  }

  const token = bearer(req);
  if (!token) {
    return new Response(JSON.stringify({ error: "Nicht autorisiert" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const [{ data: userData }, { data: allowed }] = await Promise.all([
    userClient.auth.getUser(),
    userClient.rpc("is_admin_or_editor"),
  ]);

  if (!userData.user || allowed !== true) {
    return new Response(JSON.stringify({ error: "Nicht berechtigt" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  return null;
}
