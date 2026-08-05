// Server-seitiger FCM-Versand (HTTP v1 API) — Grundlage für Phase A.1 des
// Erweiterungsplans (docs/09-feature-expansion-plan.md): die Client-Seite
// (core/push/push_service.dart) registriert Tokens in `push_tokens` und die
// Einstellungsseite existiert bereits, aber bisher löst NICHTS serverseitig
// tatsächlich einen Push aus (siehe Kommentar dort: "folgt als eigener
// Ausbauschritt"). Dieses Modul schließt genau diese Lücke.
//
// FCM v1 braucht einen OAuth2-Access-Token aus einem Google-Service-Account
// (kein einfacher Server-Key mehr wie bei der alten Legacy-API) — dafür wird
// ein JWT mit dem privaten Schlüssel des Service Accounts signiert (RS256,
// Web Crypto API) und gegen Googles Token-Endpoint getauscht.
//
// Braucht das Supabase-Secret FCM_SERVICE_ACCOUNT_JSON: der komplette Inhalt
// der Firebase-Service-Account-JSON-Datei (Firebase Console → Projekt-
// einstellungen → Dienstkonten → Neuen privaten Schlüssel generieren), als
// EIN Secret gesetzt via `supabase secrets set FCM_SERVICE_ACCOUNT_JSON='...'`.
// Ohne dieses Secret liefert sendPushToTokens einen klaren Fehler statt
// stillschweigend nichts zu tun.

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function parseServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new Error(
      "FCM_SERVICE_ACCOUNT_JSON ist nicht gesetzt — Firebase-Service-Account-JSON als Supabase-Secret hinterlegen.",
    );
  }
  const parsed = JSON.parse(raw);
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON fehlt project_id/client_email/private_key.");
  }
  return parsed;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(pemBody);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60) {
    return cachedAccessToken.token;
  }

  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const encoder = new TextEncoder();
  const unsigned = `${base64UrlEncode(encoder.encode(JSON.stringify(header)))}.${
    base64UrlEncode(encoder.encode(JSON.stringify(claim)))
  }`;
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(unsigned),
  );
  const jwt = `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`FCM-Token-Tausch fehlgeschlagen (${res.status}): ${await res.text()}`);
  }
  const data = await res.json();
  cachedAccessToken = { token: data.access_token, expiresAt: now + (data.expires_in ?? 3600) };
  return data.access_token;
}

/** Prüft nur, ob FCM_SERVICE_ACCOUNT_JSON gültig ist und Google einen
 * Access-Token dafür ausstellt — ohne dass dafür ein echter Nutzer/Push-
 * Token in der DB existieren muss. Für den Rollout-Check nach dem Setzen
 * des Secrets, bevor die ersten echten Nutzer/Favoriten da sind. */
export async function verifyFcmCredentials(): Promise<
  { ok: true; projectId: string } | { ok: false; error: string }
> {
  try {
    const account = parseServiceAccount();
    await getAccessToken(account);
    return { ok: true, projectId: account.project_id };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

export interface PushPayload {
  title: string;
  body: string;
  /** Deep-Link-Daten fürs Öffnen der richtigen Seite beim Tap, z.B. { route: "/event/<slug>" }. */
  data?: Record<string, string>;
}

export interface PushSendResult {
  token: string;
  ok: boolean;
  /** true, wenn FCM den Token als ungültig/nicht mehr registriert meldet — Aufrufer sollte ihn aus push_tokens löschen. */
  invalidToken: boolean;
  error?: string;
}

/** Sendet dieselbe Nachricht an eine Liste von FCM-Tokens (sequenziell, die
 * v1-API hat keinen echten Multicast-Endpoint mehr). Wirft nie pro Token —
 * Fehler landen im Ergebnis-Array, damit ein einzelner toter Token nicht den
 * ganzen Batch abbricht. */
export async function sendPushToTokens(
  tokens: string[],
  payload: PushPayload,
): Promise<PushSendResult[]> {
  if (tokens.length === 0) return [];
  const account = parseServiceAccount();
  const accessToken = await getAccessToken(account);

  const results: PushSendResult[] = [];
  for (const token of tokens) {
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: payload.title, body: payload.body },
              data: payload.data ?? {},
            },
          }),
        },
      );
      if (res.ok) {
        results.push({ token, ok: true, invalidToken: false });
      } else {
        const errText = await res.text();
        // UNREGISTERED/INVALID_ARGUMENT auf einen Token hin heißt: App
        // deinstalliert oder Token abgelaufen — dauerhaft, kein Retry sinnvoll.
        const invalidToken = res.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/.test(errText);
        results.push({ token, ok: false, invalidToken, error: errText });
      }
    } catch (err) {
      results.push({
        token,
        ok: false,
        invalidToken: false,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
  return results;
}
