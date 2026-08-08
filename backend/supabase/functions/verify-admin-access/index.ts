// Nutzerwunsch: "auch wäre es noch praktisch, wenn ich in der app auch das
// admin portal auf machen kann. z.b. über die einstellungen mit einem
// bestimmten passwort." Das eigentliche Admin-Dashboard hat bereits einen
// vollwertigen Login (E-Mail-Code + Rollenprüfung, siehe admin/src/proxy.ts)
// — diese Funktion ist bewusst nur eine zusätzliche Hürde in der App, damit
// der Link nicht direkt für alle App-Nutzer:innen sichtbar ist. Das
// Passwort liegt deshalb NICHT im App-Code (dort wäre es aus dem Bundle
// extrahierbar), sondern als Function-Secret hier — die App schickt nur
// den eingegebenen Text, nie das echte Passwort selbst.
Deno.serve(async (req) => {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ valid: false }), { status: 400 });
  }

  const submitted = typeof body.password === "string" ? body.password : "";
  const expected = Deno.env.get("ADMIN_PORTAL_PASSWORD") ?? "";
  const portalUrl = Deno.env.get("ADMIN_PORTAL_URL") ?? "";

  // Timing-sicherer Vergleich statt "===" — verhindert, dass die Laufzeit
  // des Vergleichs selbst (früher Abbruch bei erstem abweichenden Zeichen)
  // Rückschlüsse auf einzelne Passwort-Zeichen zulässt.
  const valid = submitted.length > 0 && timingSafeEqual(submitted, expected);

  return new Response(
    JSON.stringify(valid ? { valid: true, portalUrl } : { valid: false }),
    { headers: { "Content-Type": "application/json" } },
  );
});

function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  // Läuft bewusst über die längere der beiden Längen weiter (statt bei
  // Längen-Mismatch sofort false zurückzugeben) — sonst würde allein die
  // Antwortzeit schon die korrekte Passwortlänge verraten.
  const maxLength = Math.max(aBytes.length, bBytes.length);
  let diff = aBytes.length === bBytes.length ? 0 : 1;
  for (let i = 0; i < maxLength; i++) {
    diff |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0);
  }
  return diff === 0;
}
