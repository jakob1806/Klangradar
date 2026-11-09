// Erstellt von Claude Code (09.11.2026): Authentifizierungs-Token je
// Wallet-Karte, aus der Seriennummer abgeleitet (HMAC) – muss nicht
// gespeichert werden und ist für Dritte nicht erratbar.
export async function walletAuthToken(serial: string): Promise<string> {
  const secret = Deno.env.get("WALLET_AUTH_SECRET") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`wallet:${serial}`)));
  return Array.from(sig.slice(0, 20), (b) => b.toString(16).padStart(2, "0")).join("");
}
