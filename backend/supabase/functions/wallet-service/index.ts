// Erstellt von Claude Code (09.11.2026): Apple-Wallet-Webdienst
// (https://developer.apple.com/documentation/walletpasses/adding_a_web_service_to_update_passes).
// Endpunkte relativ zu webServiceURL:
//   POST/DELETE v1/devices/{device}/registrations/{passType}/{serial}
//   GET         v1/devices/{device}/registrations/{passType}?passesUpdatedSince=…
//   GET         v1/passes/{passType}/{serial}
//   POST        v1/log
// Intern: POST internal/push {event_id} (Datenbank-Trigger bei Konzertänderung)
// → leere Push-Nachricht an registrierte Geräte, Wallet holt die neue Karte.
// Ohne Supabase-JWT (verify_jwt = false), Schutz über das Karten-Token.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { walletAuthToken } from "../_shared/walletToken.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import forge from "npm:node-forge@1.3.1";

const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
const passType = Deno.env.get("WALLET_PASS_TYPE_ID") ?? "";

async function authorized(req: Request, serial: string): Promise<boolean> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("ApplePass ") ? header.slice(10).trim() : "";
  return token.length > 0 && token === await walletAuthToken(serial);
}

const empty = (status: number) => new Response(null, { status });

Deno.serve(async (req) => {
  const url = new URL(req.url);
  // Pfad nach …/wallet-service/
  const parts = url.pathname.split("/").filter(Boolean);
  const base = parts.indexOf("wallet-service");
  const path = parts.slice(base + 1).map(decodeURIComponent);

  // --- intern: Push an Geräte eines geänderten Konzerts ---
  if (path[0] === "internal" && path[1] === "push" && req.method === "POST") {
    const unauthorized = await requireInternalAuth(req);
    if (unauthorized) return unauthorized;
    const { event_id } = await req.json().catch(() => ({}));
    if (!event_id) return empty(400);
    const { data: regs } = await db.from("wallet_registrations")
      .select("push_token, wallet_passes!inner(event_id)").eq("wallet_passes.event_id", event_id);
    const tokens = [...new Set(((regs ?? []) as Array<{ push_token: string }>).map((r) => r.push_token))];
    const sent = await pushToWallet(tokens);
    return Response.json({ devices: tokens.length, sent });
  }

  if (path[0] !== "v1") return empty(404);

  // --- Protokoll von Wallet ---
  if (path[1] === "log") {
    const body = await req.json().catch(() => ({}));
    console.warn("wallet log", JSON.stringify(body).slice(0, 2000));
    return empty(200);
  }

  // --- Geräte an-/abmelden ---
  if (path[1] === "devices" && path[3] === "registrations") {
    const device = path[2];
    if (path[4] !== passType) return empty(404);
    const serial = path[5];
    if (serial) {
      if (!(await authorized(req, serial))) return empty(401);
      if (req.method === "POST") {
        const { pushToken } = await req.json().catch(() => ({}));
        if (!pushToken) return empty(400);
        const { data: exists } = await db.from("wallet_registrations").select("serial").eq("device_id", device).eq("serial", serial).maybeSingle();
        const { error } = await db.from("wallet_registrations").upsert({ device_id: device, serial, push_token: pushToken });
        if (error) return empty(error.code === "23503" ? 404 : 500); // Karte unbekannt
        return empty(exists ? 200 : 201);
      }
      if (req.method === "DELETE") {
        await db.from("wallet_registrations").delete().eq("device_id", device).eq("serial", serial);
        return empty(200);
      }
      return empty(405);
    }
    // Liste geänderter Karten eines Geräts
    const since = url.searchParams.get("passesUpdatedSince");
    const { data } = await db.from("wallet_registrations")
      .select("serial, wallet_passes!inner(updated_at)").eq("device_id", device);
    // deno-lint-ignore no-explicit-any
    const rows = ((data ?? []) as any[]).map((r) => ({ serial: r.serial as string, updated: new Date(r.wallet_passes.updated_at).getTime() }));
    const changed = rows.filter((r) => !since || r.updated > Number(since));
    if (!changed.length) return empty(204);
    return Response.json({ serialNumbers: changed.map((r) => r.serial), lastUpdated: String(Math.max(...rows.map((r) => r.updated))) });
  }

  // --- aktuelle Karte ---
  if (path[1] === "passes" && req.method === "GET") {
    if (path[2] !== passType) return empty(404);
    const serial = path[3];
    if (!serial || !(await authorized(req, serial))) return empty(401);
    const { data: pass } = await db.from("wallet_passes").select("params, updated_at").eq("serial", serial).maybeSingle();
    if (!pass) return empty(404);
    const updated = new Date(pass.updated_at);
    const since = req.headers.get("If-Modified-Since");
    if (since && Math.floor(updated.getTime() / 1000) <= Math.floor(new Date(since).getTime() / 1000)) return empty(304);
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/wallet-pass?${pass.params}`, {
      headers: { Authorization: `Bearer ${key}`, apikey: key },
    });
    if (!res.ok) return empty(500);
    return new Response(await res.arrayBuffer(), {
      headers: { "Content-Type": "application/vnd.apple.pkpass", "Last-Modified": updated.toUTCString() },
    });
  }

  return empty(404);
});

/** Zertifikat und Schlüssel der Pass-Typ-ID (aus WALLET_P12_BASE64) als PEM. */
function pemFromP12(): { cert: string; key: string } | null {
  try {
    const p12Der = forge.util.decode64(Deno.env.get("WALLET_P12_BASE64") ?? "");
    const p12 = forge.pkcs12.pkcs12FromAsn1(forge.asn1.fromDer(p12Der), Deno.env.get("WALLET_P12_PASSWORD") ?? "");
    const cert = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag]?.[0]?.cert;
    const key = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag]?.[0]?.key
      ?? p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag]?.[0]?.key;
    if (!cert || !key) return null;
    return { cert: forge.pki.certificateToPem(cert), key: forge.pki.privateKeyToPem(key) };
  } catch {
    return null;
  }
}

/** Leere Push-Nachricht an Wallet (Thema = Pass-Typ-ID), angemeldet mit dem
 * Pass-Zertifikat. Klappt das in der Laufzeitumgebung nicht, holt Wallet die
 * Karte beim nächsten Aktualisieren (Karte nach unten ziehen). */
async function pushToWallet(tokens: string[]): Promise<number> {
  const pem = tokens.length ? pemFromP12() : null;
  if (!pem) return 0;
  const { cert, key } = pem;
  let sent = 0;
  try {
    // deno-lint-ignore no-explicit-any
    const client = (Deno as any).createHttpClient({ cert, key });
    for (const token of tokens) {
      const res = await fetch(`https://api.push.apple.com/3/device/${token}`, {
        method: "POST",
        headers: { "apns-topic": passType, "apns-push-type": "background", "apns-priority": "5" },
        body: "{}",
        // deno-lint-ignore no-explicit-any
        client,
      } as any);
      if (res.ok) sent++;
      else if (res.status === 410) await db.from("wallet_registrations").delete().eq("push_token", token);
      await res.body?.cancel();
    }
    client.close?.();
  } catch (err) {
    console.warn("wallet push", err instanceof Error ? err.message : String(err));
  }
  return sent;
}
